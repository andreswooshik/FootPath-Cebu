"""Domain-focused API views extracted from the legacy view module."""

from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import (
    PermissionDenied,
    ValidationError,
)
from rest_framework.response import Response
from rest_framework.views import APIView

from academy._view_support import (
    _guardian_may_read,
    _in_same_club,
    _may_read_match_statistics,
)
from academy.assessment_framework import framework_for
from academy.model_operations import AuditLog
from academy.model_players import (
    AssessmentReason,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerProfile,
    PlayerStatsAssessment,
)
from academy.notifications import notify_assessment_saved
from academy.pin_service import (
    InvalidCurrentPin,
    InvalidPin,
    PinLocked,
    PinNotSet,
    has_pin,
    pin_status,
    reset_pin,
    set_pin,
    verify_pin,
)
from academy.player_stats import (
    catalog_for,
    overall,
    role_group_for,
)
from academy.player_unlock import (
    issue_player_unlock,
    require_player_unlock,
)
from academy.serializer_players import (
    AssessmentSerializer,
    DevelopmentAssessmentWriteSerializer,
    PlayerAssessmentSnapshotSerializer,
    PlayerDevelopmentAssessmentSerializer,
    PlayerPositionSerializer,
    PlayerSelectorSerializer,
    PlayerSerializer,
    PlayerStatsAssessmentSerializer,
    PlayerStatsAssessmentWriteSerializer,
)
from accounts.guardian_access import (
    guardian_can_access_player,
    valid_guardian_links,
)
from accounts.models import (
    Roles,
    User,
)

from .pagination import list_response


class SquadListView(APIView):
    """GET /api/players/ — the roster. Coach (own club only) and Admin (all)."""

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view the squad.')
        profiles = PlayerProfile.objects.select_related('user')
        # Coaches see only their own club's roster; Admin sees every club.
        if request.user.role == Roles.COACH:
            if request.user.club_id is None:
                profiles = profiles.none()
            else:
                profiles = profiles.filter(user__club_id=request.user.club_id)
        return list_response(request, profiles, PlayerSerializer)


class MyProfileView(APIView):
    """GET /api/players/me/ — the signed-in player's own profile."""

    def get(self, request):
        if request.user.role != Roles.PLAYER:
            raise PermissionDenied('Only players have a player profile.')
        profile = get_object_or_404(PlayerProfile.objects.select_related('user'), user=request.user)
        return Response(PlayerSerializer(profile).data)


class LinkedPlayersView(APIView):
    """GET /api/players/linked/ — the guardian's linked children."""

    def get(self, request):
        if request.user.role != Roles.GUARDIAN:
            raise PermissionDenied('Only guardians have linked players.')
        player_ids = valid_guardian_links(guardian=request.user).values_list('player_id', flat=True)
        profiles = PlayerProfile.objects.select_related('user').filter(user_id__in=player_ids)
        return list_response(request, profiles, PlayerSelectorSerializer)


class PlayerDetailView(APIView):
    """Return one player profile after normal authorization and PIN unlock."""

    def get(self, request, player_id):
        if not _guardian_may_read(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        profile = get_object_or_404(PlayerProfile.objects.select_related('user'), user_id=player_id)
        return Response(PlayerSerializer(profile).data)


def _pin_profile(player_id):
    return get_object_or_404(PlayerProfile.objects.select_related('user'), user_id=player_id)


def _require_unlock_when_pin_exists(request, player_id):
    """Apply the privacy gate only after a player has configured a PIN.

    Linked guardians may view a managed player's profile before the household
    PIN is created. Once a PIN exists, the short-lived unlock grant remains
    mandatory for the same profile and its child-scoped records.
    """
    if request.user.role != Roles.GUARDIAN:
        return
    if has_pin(_pin_profile(player_id).user):
        require_player_unlock(request, player_id)


def _may_manage_pin(user, player_id):
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.PLAYER:
        return str(user.id) == str(player_id)
    if user.role == Roles.COORDINATOR:
        return _in_same_club(user, player_id)
    if user.role == Roles.GUARDIAN:
        return guardian_can_access_player(user, player_id)
    return False


def _has_recent_firebase_reauthentication(request, max_age_seconds=300):
    """Require a recently reauthenticated Firebase ID token for recovery.

    Firebase puts the time of the last password verification in ``auth_time``.
    The Flutter client reauthenticates first and then forces a fresh token for
    the reset call.  Keeping this check server-side prevents a stolen older
    bearer token from silently clearing a player's PIN.
    """
    claims = request.auth
    if not isinstance(claims, dict):
        return False
    try:
        auth_time = float(claims['auth_time'])
    except (KeyError, TypeError, ValueError):
        return False
    return timezone.now().timestamp() - auth_time <= max_age_seconds


class PlayerPrivacyPinView(APIView):
    """GET status; PUT lets the player create or change their own PIN."""

    throttle_scope = 'pin'

    def get(self, request, player_id):
        if not _may_manage_pin(request.user, player_id):
            raise PermissionDenied('You cannot access that player PIN.')
        return Response(pin_status(_pin_profile(player_id).user))

    def put(self, request, player_id):
        is_player = request.user.role == Roles.PLAYER and str(request.user.id) == str(player_id)
        is_guardian_initial_setup = (
            request.user.role == Roles.GUARDIAN
            and guardian_can_access_player(request.user, player_id)
            and not has_pin(_pin_profile(player_id).user)
        )
        if not is_player and not is_guardian_initial_setup:
            raise PermissionDenied(
                'Only the player can change an existing PIN. A linked guardian '
                'may set the first PIN for a managed player.'
            )
        player = _pin_profile(player_id).user
        pin = request.data.get('pin')
        try:
            set_pin(
                player,
                pin,
                current_pin=request.data.get('currentPin'),
            )
        except InvalidCurrentPin as exc:
            raise ValidationError(str(exc))
        except ValueError as exc:
            raise ValidationError(str(exc))
        AuditLog.record(request.user, 'player_pin.changed', target=player.email)
        result = pin_status(player)
        result['unlockToken'] = issue_player_unlock(request.user.id, player.id)
        return Response(result)


class PlayerPrivacyPinVerifyView(APIView):
    """POST verifies the player's PIN without returning any secret material."""

    throttle_scope = 'pin'

    def post(self, request, player_id):
        is_player = request.user.role == Roles.PLAYER and str(request.user.id) == str(player_id)
        is_linked_guardian = request.user.role == Roles.GUARDIAN and guardian_can_access_player(
            request.user, player_id
        )
        if not is_player and not is_linked_guardian:
            raise PermissionDenied('Only the player or a linked guardian can verify this PIN.')
        player = _pin_profile(player_id).user
        try:
            verify_pin(player, request.data.get('pin'))
        except PinLocked as exc:
            return Response(
                {'detail': str(exc), 'lockedUntil': exc.locked_until.isoformat()},
                status=status.HTTP_423_LOCKED,
            )
        except PinNotSet as exc:
            raise ValidationError(str(exc))
        except InvalidPin as exc:
            raise ValidationError(str(exc))
        return Response(
            {
                'verified': True,
                'unlockToken': issue_player_unlock(request.user.id, player.id),
            }
        )


class PlayerPrivacyPinResetView(APIView):
    """POST clears a PIN for a linked guardian or same-club coordinator."""

    throttle_scope = 'pin'

    def post(self, request, player_id):
        if not _may_manage_pin(request.user, player_id):
            raise PermissionDenied('You cannot reset that player PIN.')
        if request.user.role not in (Roles.ADMIN, Roles.COORDINATOR, Roles.GUARDIAN):
            raise PermissionDenied('Only a guardian or coordinator can reset a PIN.')
        if request.user.role == Roles.GUARDIAN and not _has_recent_firebase_reauthentication(
            request
        ):
            raise PermissionDenied(
                'Recent guardian verification is required before resetting a PIN.'
            )
        player = _pin_profile(player_id).user
        reset_pin(player)
        AuditLog.record(
            request.user,
            'player_pin.reset',
            target=player.email,
            detail=request.user.get_role_display(),
        )
        return Response(pin_status(player))


class PlayerAssessmentView(APIView):
    """PUT /api/players/<id>/assessment/ — coach updates the six ratings."""

    @staticmethod
    def _profile_for_coach(user, player_id):
        if user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can assess players.')
        profile = get_object_or_404(PlayerProfile.objects.select_related('user'), user_id=player_id)
        if user.club_id is None or profile.user.club_id != user.club_id:
            raise PermissionDenied('That player is not in your club.')
        return profile

    def get(self, request, player_id):
        profile = self._profile_for_coach(request.user, player_id)
        latest = (
            PlayerDevelopmentAssessment.objects.select_related('player', 'assessed_by')
            .filter(player_id=player_id)
            .first()
        )
        return Response(
            {
                'framework': framework_for(profile.age_tier, profile.position),
                'latestAssessment': (
                    PlayerDevelopmentAssessmentSerializer(latest).data if latest else None
                ),
            }
        )

    def put(self, request, player_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can assess players.')
        profile = get_object_or_404(PlayerProfile.objects.select_related('user'), user_id=player_id)
        # Tenancy: a coach may only assess players in their own club.
        if request.user.club_id is None or profile.user.club_id != request.user.club_id:
            raise PermissionDenied('That player is not in your club.')
        if 'developmentRatings' in request.data:
            return self._put_development(request, profile)
        with transaction.atomic():
            profile = (
                PlayerProfile.objects.select_for_update().select_related('user').get(pk=profile.pk)
            )
            serializer = AssessmentSerializer(profile, data=request.data, partial=True)
            serializer.is_valid(raise_exception=True)
            reason = serializer.validated_data.get(
                'assessmentReason', AssessmentReason.GENERAL_REVIEW
            )
            changed = any(
                getattr(profile, field) != value
                for field, value in serializer.validated_data.items()
                if field != 'assessmentReason'
            )
            if changed:
                profile = serializer.save()
                PlayerAssessmentSnapshot.from_profile(
                    profile,
                    assessed_by=request.user,
                    reason=reason,
                )
                AuditLog.record(
                    request.user,
                    'assessment.saved',
                    target=profile.user.email,
                    detail=reason,
                )
                # Notify only after both the current view and its immutable
                # snapshot are durable. A no-op produces neither duplicate
                # history nor a misleading notification.
                notify_assessment_saved(profile)
        return Response(PlayerSerializer(profile).data)

    def _put_development(self, request, profile):
        legacy_fields = {
            'ratings',
            'pace',
            'shooting',
            'passing',
            'dribbling',
            'defending',
            'physical',
            'diving',
            'handling',
            'kicking',
            'reflexes',
            'speed',
            'positioning',
        }
        if legacy_fields.intersection(request.data):
            raise ValidationError(
                {
                    'developmentRatings': (
                        'Do not mix legacy 0-99 ratings with a development assessment.'
                    ),
                }
            )
        with transaction.atomic():
            profile = (
                PlayerProfile.objects.select_for_update().select_related('user').get(pk=profile.pk)
            )
            serializer = DevelopmentAssessmentWriteSerializer(
                data=request.data,
                context={'profile': profile},
            )
            serializer.is_valid(raise_exception=True)
            data = serializer.validated_data
            reason = data['assessmentReason']
            new_notes = data.get('coachNotes', profile.coach_notes)
            changed = any(
                (
                    profile.development_framework_version != data['frameworkVersion'],
                    profile.development_scores != data['developmentRatings'],
                    profile.development_strengths != data['strengths'],
                    profile.development_targets != data['developmentTargets'],
                    profile.coach_notes != new_notes,
                )
            )
            if changed:
                profile.development_framework_version = data['frameworkVersion']
                profile.development_scores = data['developmentRatings']
                profile.development_strengths = data['strengths']
                profile.development_targets = data['developmentTargets']
                profile.development_assessed_at = timezone.now()
                profile.coach_notes = new_notes
                profile.save(
                    update_fields=[
                        'development_framework_version',
                        'development_scores',
                        'development_strengths',
                        'development_targets',
                        'development_assessed_at',
                        'coach_notes',
                    ]
                )
                PlayerDevelopmentAssessment.from_profile(
                    profile,
                    assessed_by=request.user,
                    reason=reason,
                )
                AuditLog.record(
                    request.user,
                    'development_assessment.saved',
                    target=profile.user.email,
                    detail=reason,
                )
                notify_assessment_saved(profile)
        return Response(PlayerSerializer(profile).data)


class PlayerAssessmentHistoryView(APIView):
    """Authorized, privacy-gated immutable assessment history."""

    def get(self, request, player_id):
        if not _may_read_match_statistics(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
        rows = PlayerAssessmentSnapshot.objects.select_related('player', 'assessed_by').filter(
            player_id=player_id
        )
        return Response(PlayerAssessmentSnapshotSerializer(rows, many=True).data)


class PlayerStatsView(APIView):
    """Separate, append-only 0–99 Player Stats history and creation API."""

    def _profile(self, player_id):
        return get_object_or_404(PlayerProfile.objects.select_related('user'), user_id=player_id)

    def _payload(self, profile):
        group, attributes = catalog_for(profile.position)
        compatible = list(
            PlayerStatsAssessment.objects.select_related('assessed_by').filter(
                player=profile.user,
                role_group=group,
                catalog_version=1,
            )
        )
        latest = compatible[0] if compatible else None
        comparison = (
            self._comparison(compatible[1], compatible[0].scores)
            if len(compatible) >= 2
            else self._comparison(None, None)
        )
        legacy = PlayerAssessmentSnapshot.objects.select_related('assessed_by').filter(
            player=profile.user
        )
        return {
            'catalog': {
                'version': 1,
                'position': profile.position,
                'roleGroup': group,
                'attributes': attributes,
            },
            'latestCompatibleStats': PlayerStatsAssessmentSerializer(latest).data
            if latest
            else None,
            'comparison': comparison,
            'history': PlayerStatsAssessmentSerializer(compatible, many=True).data,
            'legacyStatsHistory': PlayerAssessmentSnapshotSerializer(legacy, many=True).data,
            'isBaseline': latest is None,
        }

    @staticmethod
    def _comparison(previous, new_scores):
        if previous is None:
            return {
                'baseline': True,
                'previousOverall': None,
                'newOverall': overall(new_scores) if new_scores else None,
                'overallDelta': None,
                'attributes': {},
            }
        new_overall = overall(new_scores) if new_scores else previous.overall
        changes = (
            {}
            if new_scores is None
            else {
                key: {
                    'previous': previous.scores[key],
                    'new': value,
                    'delta': value - previous.scores[key],
                }
                for key, value in new_scores.items()
            }
        )
        return {
            'baseline': False,
            'previousOverall': previous.overall,
            'newOverall': new_overall,
            'overallDelta': new_overall - previous.overall,
            'attributes': changes,
        }

    def get(self, request, player_id):
        if not _may_read_match_statistics(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        return Response(self._payload(self._profile(player_id)))

    def post(self, request, player_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can create Player Stats assessments.')
        profile = self._profile(player_id)
        if request.user.club_id is None or profile.user.club_id != request.user.club_id:
            raise PermissionDenied('That player is not in your club.')
        with transaction.atomic():
            profile = (
                PlayerProfile.objects.select_for_update().select_related('user').get(pk=profile.pk)
            )
            serializer = PlayerStatsAssessmentWriteSerializer(
                data=request.data, context={'profile': profile}
            )
            serializer.is_valid(raise_exception=True)
            data = serializer.validated_data
            group = role_group_for(profile.position)
            previous = (
                PlayerStatsAssessment.objects.select_for_update()
                .filter(
                    player=profile.user,
                    role_group=group,
                    catalog_version=data['catalogVersion'],
                )
                .first()
            )
            if previous and previous.scores == data['scores']:
                raise ValidationError(
                    {
                        'scores': 'This is unchanged from the latest compatible Player Stats assessment.'
                    }
                )
            record = PlayerStatsAssessment.objects.create(
                player=profile.user,
                assessed_by=request.user,
                position=profile.position,
                role_group=group,
                catalog_version=data['catalogVersion'],
                scores=data['scores'],
                overall=overall(data['scores']),
                reason=data['reason'],
                coach_notes=data['coachNotes'],
            )
            AuditLog.record(
                request.user, 'player_stats.saved', target=profile.user.email, detail=data['reason']
            )
            notify_assessment_saved(profile)
        return Response(
            {
                'assessment': PlayerStatsAssessmentSerializer(record).data,
                'comparison': self._comparison(previous, record.scores),
            },
            status=status.HTTP_201_CREATED,
        )


class PlayerPositionView(APIView):
    """PUT /api/players/<id>/position/ — coach assigns or changes a player's
    position. Was a client-side stub (ApiPlayerRepository.savePosition threw
    UnimplementedError) with no backend endpoint at all until this view."""

    def put(self, request, player_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can assign a position.')
        profile = get_object_or_404(PlayerProfile.objects.select_related('user'), user_id=player_id)
        # Tenancy: a coach may only edit players in their own club — same
        # check as PlayerAssessmentView.
        if request.user.club_id is None or profile.user.club_id != request.user.club_id:
            raise PermissionDenied('That player is not in your club.')
        serializer = PlayerPositionSerializer(profile, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        AuditLog.record(
            request.user,
            'position.changed',
            target=profile.user.email,
            detail=profile.position,
        )
        return Response(PlayerSerializer(profile).data)
