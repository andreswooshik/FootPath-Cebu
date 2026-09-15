"""Coordinator-owned reads and safe retirement for club people."""

import logging

from django.db import transaction
from django.shortcuts import get_object_or_404
from firebase_admin import auth as firebase_auth
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from academy.model_operations import AuditLog
from academy.model_tournaments import TournamentSquadEntry
from academy.storage import delete_photo, invalidate_signed_photo_url
from accounts.firebase import ensure_initialized
from accounts.models import FirebaseProvisioningCleanup, PlayerRegistration, Roles, User
from accounts.permissions import IsCoordinator

logger = logging.getLogger(__name__)

_ROLES_BY_PATH = {
    'players': Roles.PLAYER,
    'guardians': Roles.GUARDIAN,
    'coaches': Roles.COACH,
}


def _display_name(user, *, player_profile=None):
    middle_initial = (
        player_profile.middle_initial if player_profile is not None else user.middle_initial
    )
    return ' '.join(
        part
        for part in (
            user.first_name,
            f'{middle_initial}.' if middle_initial else '',
            user.last_name,
        )
        if part
    ) or (user.email.split('@')[0] if user.email else f'Person {user.pk}')


def _person_payload(person):
    profile = getattr(person, 'player_profile', None)
    middle_initial = profile.middle_initial if profile is not None else person.middle_initial
    payload = {
        'id': str(person.pk),
        'role': person.role,
        'roleDisplay': person.get_role_display(),
        'firstName': person.first_name,
        'middleInitial': middle_initial or '',
        'lastName': person.last_name,
        'name': _display_name(person, player_profile=profile),
        'email': person.email or '',
        'mobileNumber': person.mobile_number or '',
        'linkedPeople': [],
    }
    if person.role == Roles.PLAYER:
        payload.update(
            dateOfBirth=profile.date_of_birth.isoformat() if profile.date_of_birth else None,
            age=profile.age,
            classYear=profile.class_year,
            ageTier=profile.age_tier,
            ageTierDisplay=profile.get_age_tier_display(),
            position=profile.position or None,
            linkedPeople=[
                {
                    'id': str(link.guardian_id),
                    'name': _display_name(link.guardian),
                    'email': link.guardian.email or '',
                    'mobileNumber': link.guardian.mobile_number or '',
                }
                for link in person.player_links.select_related('guardian').filter(
                    guardian__is_active=True
                )
            ],
        )
    elif person.role == Roles.GUARDIAN:
        payload['linkedPeople'] = [
            {
                'id': str(link.player_id),
                'name': _display_name(
                    link.player,
                    player_profile=getattr(link.player, 'player_profile', None),
                ),
                'email': '',
                'mobileNumber': '',
            }
            for link in person.guardian_links.select_related('player__player_profile').filter(
                player__is_active=True
            )
        ]
    return payload


def _delete_firebase_identity(firebase_uid):
    """Delete remotely after local access is revoked; queue transient failures."""
    if not firebase_uid:
        return
    try:
        ensure_initialized()
        firebase_auth.delete_user(firebase_uid)
    except firebase_auth.UserNotFoundError:
        return
    except Exception:
        FirebaseProvisioningCleanup.objects.get_or_create(firebase_uid=firebase_uid)
        logger.exception('Person retirement identity cleanup queued for retry.')


class CoordinatorPersonDetailView(APIView):
    """Read or delete one active person in the coordinator's club."""

    permission_classes = [IsCoordinator]

    def _person(self, request, role, person_id, *, for_update=False):
        expected_role = _ROLES_BY_PATH.get(role)
        if expected_role is None:
            return None
        queryset = User.objects.select_related('club', 'player_profile')
        if expected_role == Roles.PLAYER:
            queryset = queryset.filter(player_profile__isnull=False)
        if for_update:
            queryset = queryset.select_for_update()
        return get_object_or_404(
            queryset,
            pk=person_id,
            role=expected_role,
            club_id=request.user.club_id,
            is_active=True,
        )

    def get(self, request, role, person_id):
        if request.user.club_id is None or not request.user.club.is_active:
            return Response(
                {'detail': 'Your club must be active.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        person = self._person(request, role, person_id)
        if person is None:
            return Response(
                {'detail': 'Unknown person role.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(_person_payload(person))

    def delete(self, request, role, person_id):
        if request.user.club_id is None or not request.user.club.is_active:
            return Response(
                {'detail': 'Your club must be active.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        with transaction.atomic():
            person = self._person(request, role, person_id, for_update=True)
            if person is None:
                return Response(
                    {'detail': 'Unknown person role.'},
                    status=status.HTTP_404_NOT_FOUND,
                )
            if person.role == Roles.GUARDIAN:
                linked_count = person.guardian_links.filter(player__is_active=True).count()
                if linked_count:
                    noun = 'player' if linked_count == 1 else 'players'
                    return Response(
                        {
                            'detail': (
                                f'This guardian still has {linked_count} linked {noun}. '
                                'Reassign or remove them before deleting this account.'
                            ),
                            'code': 'guardian_has_linked_players',
                            'linkedPlayerCount': linked_count,
                        },
                        status=status.HTTP_409_CONFLICT,
                    )

            firebase_uid = person.firebase_uid
            person_id = str(person.pk)
            person_role = person.role
            profile = getattr(person, 'player_profile', None)
            photo_path = profile.photo_path if profile is not None else None
            if person.role == Roles.PLAYER:
                # These two receipt/selection models intentionally use PROTECT.
                # A Coordinator-requested permanent deletion removes them first;
                # the User deletion then cascades through the player-owned
                # profile, links, assessments, attendance, injuries, and stats.
                PlayerRegistration.objects.filter(player=person).delete()
                TournamentSquadEntry.objects.filter(player=person).delete()
                person.delete()
                detail = 'Player profile and all related records permanently deleted.'
            else:
                person.is_active = False
                person.firebase_uid = None
                person.save(update_fields=['is_active', 'firebase_uid'])
                detail = 'Account access retired by club coordinator.'
            AuditLog.record(
                request.user,
                f'{person_role.lower()}.deleted',
                target=person_id,
                detail=detail,
            )

        _delete_firebase_identity(firebase_uid)
        if person_role == Roles.PLAYER and photo_path:
            invalidate_signed_photo_url(photo_path)
            delete_photo(photo_path)
        return Response(status=status.HTTP_204_NO_CONTENT)
