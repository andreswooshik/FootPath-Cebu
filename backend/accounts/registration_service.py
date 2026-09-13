import hashlib
import json
import logging

from django.db import transaction
from django.db.models import Q
from firebase_admin import auth as firebase_auth
from rest_framework.exceptions import APIException, PermissionDenied, ValidationError

from academy.models import AuditLog
from .models import Club, FirebaseProvisioningCleanup, PlayerRegistration, Roles, User
from .services import provision_player, provision_user

logger = logging.getLogger(__name__)


class RegistrationConflict(APIException):
    status_code = 409
    default_detail = 'This registration has already been submitted with different details.'


def coordinator_club(actor):
    if not actor.is_active or actor.role != Roles.COORDINATOR:
        raise PermissionDenied('Only an active Coordinator can register players.')
    if actor.club_id is None or not actor.club.is_active:
        raise PermissionDenied('Your club must be active.')
    return actor.club


def check_guardian_duplicate(*, club, data):
    duplicate = User.objects.filter(club=club, role=Roles.GUARDIAN).filter(
        Q(email__iexact=data['email']) | Q(mobile_number=data['mobileNumber'])
    ).first()
    if duplicate:
        raise RegistrationConflict({
            'detail': 'A guardian with this email or mobile number already exists.',
            'existingGuardianId': str(duplicate.pk) if duplicate.is_active else None,
        })
    if User.objects.filter(email__iexact=data['email']).exists():
        raise ValidationError({'email': 'An account with this email already exists.'})


def registration_result(receipt, *, guardian_password=None, player_password=None, replayed=False):
    return {
        'playerId': str(receipt.player_id),
        'guardianId': str(receipt.guardian_id),
        'coordinatorId': str(receipt.coordinator_id),
        'guardianCreated': receipt.guardian_created,
        'playerEmail': receipt.player.email,
        'guardianEmail': receipt.guardian.email,
        'guardianTemporaryPassword': guardian_password,
        'playerTemporaryPassword': player_password,
        'replayed': replayed,
    }


def cleanup_identity(uid):
    # Never remove an identity that was committed or subsequently linked.
    if User.objects.filter(firebase_uid=uid).exists():
        return True
    try:
        firebase_auth.delete_user(uid)
    except firebase_auth.UserNotFoundError:
        pass
    return True


def register_player(*, actor, data):
    club = coordinator_club(actor)
    payload_hash = hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()
    created_identities = []
    try:
        with transaction.atomic():
            # Serialize requests for this club, including duplicate checks.
            locked_club = Club.objects.select_for_update().get(pk=club.pk)
            if not locked_club.is_active:
                raise PermissionDenied('Your club must be active.')
            receipt = PlayerRegistration.objects.filter(
                coordinator=actor, request_key=data['requestId']
            ).select_related('player', 'guardian').first()
            if receipt:
                if receipt.payload_hash != payload_hash:
                    raise RegistrationConflict()
                return registration_result(receipt, replayed=True)

            player_data = data['player']
            guardian_data = data.get('newGuardian')
            player_email = player_data['email']
            if player_email and User.objects.filter(email__iexact=player_email).exists():
                raise ValidationError({'player': {'email': 'An account with this email already exists.'}})
            if guardian_data and player_email == guardian_data['email']:
                raise ValidationError({'player': {'email': 'Use a separate player email or leave it blank.'}})
            guardian_password = None
            if guardian_data:
                check_guardian_duplicate(club=club, data=guardian_data)
                guardian, guardian_password, _ = provision_user(
                    email=guardian_data['email'], first_name=guardian_data['firstName'],
                    last_name=guardian_data['lastName'], role=Roles.GUARDIAN, club=club,
                    created_identities=created_identities,
                )
                guardian.mobile_number = guardian_data['mobileNumber']
                guardian.save(update_fields=['mobile_number'])
            else:
                guardian = User.objects.select_for_update().filter(
                    pk=data['existingGuardianId'], club=club, role=Roles.GUARDIAN, is_active=True
                ).first()
                if guardian is None:
                    raise ValidationError({'existingGuardianId': 'Select an active guardian in your club.'})
            player, _, player_password, _ = provision_player(
                email=player_email, first_name=player_data['firstName'],
                last_name=player_data['lastName'], middle_initial=player_data['middleInitial'],
                date_of_birth=player_data['dateOfBirth'], club=club, guardian=guardian,
                created_identities=created_identities,
            )
            receipt = PlayerRegistration.objects.create(
                coordinator=actor, request_key=data['requestId'], payload_hash=payload_hash,
                player=player, guardian=guardian, guardian_created=guardian_data is not None,
            )
            AuditLog.record(actor, 'player.registered', target=str(player.pk), detail=json.dumps({
                'guardianId': guardian.pk, 'guardianCreated': receipt.guardian_created,
            }))
            result = registration_result(
                receipt, guardian_password=guardian_password, player_password=player_password
            )
        return result
    except Exception:
        # Firebase is external to SQL. Compensate only identities created here,
        # after rollback, and retain failed cleanup for a scheduled retry.
        for uid in reversed(created_identities):
            try:
                cleanup_identity(uid)
            except Exception:
                FirebaseProvisioningCleanup.objects.get_or_create(firebase_uid=uid)
                logger.error('Registration identity cleanup queued for retry.')
        raise
