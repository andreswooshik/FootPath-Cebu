"""Academy REST endpoints.

Authentication is the project-wide FirebaseAuthentication (settings.py).
Authorization is enforced two ways, both server-side (never trust the client):
  - endpoint-level RBAC via accounts.permissions.role_required(...);
  - object-level scoping in each queryset/handler (a guardian only ever reaches
    a player they are linked to — audit finding F3).
"""
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.db.models import Avg, Count, Prefetch, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.exceptions import APIException, PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import GuardianLink, Roles, User
from accounts.permissions import IsAdmin
from accounts.serializers import UserSerializer
from accounts.services import (
    ProvisioningError,
    provision_player,
)

from .assessment_framework import framework_for
from .models import (
    AgeTierSetting,
    AssessmentReason,
    Attendance,
    AttendanceStatus,
    AuditLog,
    ConfirmationStatus,
    DeviceToken,
    Dispute,
    DisputeResponse,
    EligibilityHistory,
    FixtureStatus,
    FootballMatch,
    MatchCategory,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    InjuryStatusUpdateRequest,
    InjuryUpdateReviewStatus,
    NotificationRecord,
    PlayerMatchPerformance,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerProfile,
    PlayerPrivacyPin,
    SessionConfirmation,
    TrainingSession,
    TrainingSessionStatus,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
)
from .notifications import (
    _recipients_for_session,
    notify_assessment_saved,
    notify_session_cancelled,
    notify_session_scheduled,
    notify_session_updated,
    notify_tournament_roster_published,
)
from .pin_service import (
    InvalidCurrentPin,
    InvalidPin,
    PinLocked,
    PinNotSet,
    reset_pin,
    set_pin,
    verify_pin,
    pin_status,
    has_pin,
)
from .serializers import (
    AdminCreatePlayerSerializer,
    AgeTierSettingSerializer,
    AssessmentSerializer,
    DevelopmentAssessmentWriteSerializer,
    AttendanceSerializer,
    DisputeCreateSerializer,
    DisputeResponseCreateSerializer,
    DisputeSerializer,
    EligibilityHistorySerializer,
    CoachMatchRatingSerializer,
    FootballMatchSerializer,
    InjuryRecordSerializer,
    InjuryStatusUpdateRequestSerializer,
    NotificationRecordSerializer,
    PlayerMatchPerformanceSerializer,
    PlayerAssessmentSnapshotSerializer,
    PlayerDevelopmentAssessmentSerializer,
    PlayerMatchStatisticsWriteSerializer,
    PlayerPositionSerializer,
    PlayerSerializer,
    PlayerSelectorSerializer,
    SessionAttendanceRecordSerializer,
    SessionConfirmationSerializer,
    TrainingSessionSerializer,
    TournamentAgeBracketWriteSerializer,
    TournamentFixtureResultWriteSerializer,
    TournamentFixtureWriteSerializer,
    TournamentScheduleSerializer,
    TournamentScheduleWriteSerializer,
    TournamentSquadSerializer,
    TournamentSquadWriteSerializer,
)
from .match_statistics import build_performance_summary
from .growth import (
    build_assessment_growth,
    build_development_assessment_growth,
    build_match_growth,
    build_tournament_groups,
    build_training_groups,
    limited,
    resolve_growth_filter,
)
from .player_unlock import issue_player_unlock, require_player_unlock
from .storage import (
    delete_photo,
    delete_tournament_document,
    invalidate_signed_photo_url,
    invalidate_signed_tournament_document_url,
    upload_photo,
    upload_tournament_document,
    validate_photo_upload,
    validate_tournament_document,
)
from .tournament_results import complete_tournament_fixture
from .tournament_rosters import invalid_squad_entries, roster_eligibility
from .schedule_conflicts import (
    cancel_conflicting_training,
    conflicting_fixture_for_training,
    conflicting_training_for_fixtures,
    fixture_conflict_payload,
)

# Roles that participate in the dispute process: the coach flags, School
# Staff and Admin review/respond. Players and guardians have no access.
DISPUTE_ROLES = (Roles.COACH, Roles.SCHOOL_STAFF, Roles.ADMIN)


class WorkflowConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_code = 'conflict'

    def __init__(self, code, message, **details):
        super().__init__({'code': code, 'message': message, **details})


def _confirmed(request, field='confirmTrainingCancellations'):
    return str(request.data.get(field, '')).lower() in ('true', '1', 'yes', 'on')


def _training_cancellation_details(conflicts):
    return {
        'count': len(conflicts),
        'sessions': [
            {
                'id': str(session.id),
                'title': session.title,
                'date': session.date.isoformat(),
                'startTime': session.start_time,
                'endTime': session.end_time,
                'ageTiers': session.age_tiers,
                'fixture': fixture_conflict_payload(fixture),
            }
            for session, fixture in conflicts
        ],
    }


def _in_same_club(user, player_id):
    """True if `player_id` names a user in `user`'s club (multi-tenant scope).

    A missing requester club always fails closed: legacy club-less accounts are
    not a shared tenant. ADMIN is club-less by design and is handled by an
    explicit cross-club branch before this helper is called.
    """
    if user.club_id is None:
        return False
    row = User.objects.filter(pk=player_id).values('club_id').first()
    return row is not None and row['club_id'] == user.club_id


def _guardian_may_read(user, player_id):
    """True if `user` is allowed to read the given player's data."""
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.COACH:
        # Coaches are club-scoped: only players in their own club (tenancy).
        return _in_same_club(user, player_id)
    if user.role == Roles.PLAYER:
        return str(user.id) == str(player_id)
    if user.role == Roles.GUARDIAN:
        return GuardianLink.objects.filter(
            guardian=user, player_id=player_id
        ).exists()
    return False


def _may_read_match_statistics(user, player_id):
    """Authorize the player and the adults responsible for their development."""
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.COACH:
        return _in_same_club(user, player_id)
    if user.role == Roles.PLAYER:
        return str(user.id) == str(player_id)
    if user.role == Roles.GUARDIAN:
        return GuardianLink.objects.filter(
            guardian=user,
            player_id=player_id,
        ).exists()
    return False


def _may_read_eligibility(user, player_id):
    """True if `user` may read a player's eligibility history.

    Deliberately narrower than [_guardian_may_read]: the coach is excluded —
    academic eligibility is the School Staff's domain, not the coach's. Allowed:
    the player themselves, their linked guardian(s), any School Staff (in the
    same club), Admin.
    """
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.SCHOOL_STAFF:
        return _in_same_club(user, player_id)
    if user.role == Roles.PLAYER:
        return str(user.id) == str(player_id)
    if user.role == Roles.GUARDIAN:
        return GuardianLink.objects.filter(
            guardian=user, player_id=player_id
        ).exists()
    return False


def _sessions_for(user):
    """The TrainingSession queryset visible to `user`: their own club's
    sessions, or every club's for Admin."""
    qs = TrainingSession.objects.annotate(
        present_attendee_count=Count(
            'attendance_records',
            filter=Q(attendance_records__status=AttendanceStatus.PRESENT),
        )
    )
    if user.role == Roles.ADMIN:
        return qs
    if user.club_id is None:
        return qs.none()
    return qs.filter(club_id=user.club_id)


def _session_in_user_scope(user, session):
    """True if `user` may see/act on `session` under club tenancy (Admin: any
    club; everyone else: only their own club's sessions)."""
    if user.role == Roles.ADMIN:
        return True
    return user.club_id is not None and session.club_id == user.club_id


def _matches_for(user):
    """Club-scoped match queryset; Admin can inspect every club."""
    qs = FootballMatch.objects.select_related(
        'club', 'created_by', 'source_fixture__age_bracket',
    )
    if user.role == Roles.ADMIN:
        return qs
    if user.club_id is None:
        return qs.none()
    return qs.filter(club_id=user.club_id)


def _role_match(request, match_id, role):
    """Return a same-club match for one explicit role."""
    if request.user.role != role:
        raise PermissionDenied(f'Only {role.lower()} accounts can perform this action.')
    if request.user.club_id is None:
        raise PermissionDenied('Your account must belong to a club.')
    return get_object_or_404(
        FootballMatch.objects.select_related(
            'club', 'source_fixture__age_bracket__schedule',
        ),
        pk=match_id,
        club_id=request.user.club_id,
    )


def _match_age_bracket(match):
    """Return a linked age bracket without breaking legacy/ad-hoc matches."""
    try:
        return match.source_fixture.age_bracket
    except TournamentFixture.DoesNotExist:
        return None


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
        return Response(PlayerSerializer(profiles, many=True).data)


class MyProfileView(APIView):
    """GET /api/players/me/ — the signed-in player's own profile."""

    def get(self, request):
        if request.user.role != Roles.PLAYER:
            raise PermissionDenied('Only players have a player profile.')
        profile = get_object_or_404(
            PlayerProfile.objects.select_related('user'), user=request.user
        )
        return Response(PlayerSerializer(profile).data)


class LinkedPlayersView(APIView):
    """GET /api/players/linked/ — the guardian's linked children."""

    def get(self, request):
        if request.user.role != Roles.GUARDIAN:
            raise PermissionDenied('Only guardians have linked players.')
        player_ids = GuardianLink.objects.filter(
            guardian=request.user
        ).values_list('player_id', flat=True)
        profiles = PlayerProfile.objects.select_related('user').filter(
            user_id__in=player_ids
        )
        return Response(PlayerSelectorSerializer(profiles, many=True).data)


class PlayerDetailView(APIView):
    """Return one player profile after normal authorization and PIN unlock."""

    def get(self, request, player_id):
        if not _guardian_may_read(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        profile = get_object_or_404(
            PlayerProfile.objects.select_related('user'), user_id=player_id
        )
        return Response(PlayerSerializer(profile).data)


def _pin_profile(player_id):
    return get_object_or_404(
        PlayerProfile.objects.select_related('user'), user_id=player_id
    )


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
        return GuardianLink.objects.filter(
            guardian=user, player_id=player_id
        ).exists()
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

    def get(self, request, player_id):
        if not _may_manage_pin(request.user, player_id):
            raise PermissionDenied('You cannot access that player PIN.')
        return Response(pin_status(_pin_profile(player_id).user))

    def put(self, request, player_id):
        is_player = (
            request.user.role == Roles.PLAYER
            and str(request.user.id) == str(player_id)
        )
        is_guardian_initial_setup = (
            request.user.role == Roles.GUARDIAN
            and GuardianLink.objects.filter(
                guardian=request.user, player_id=player_id
            ).exists()
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

    def post(self, request, player_id):
        is_player = (
            request.user.role == Roles.PLAYER
            and str(request.user.id) == str(player_id)
        )
        is_linked_guardian = (
            request.user.role == Roles.GUARDIAN
            and GuardianLink.objects.filter(
                guardian=request.user, player_id=player_id
            ).exists()
        )
        if not is_player and not is_linked_guardian:
            raise PermissionDenied(
                'Only the player or a linked guardian can verify this PIN.'
            )
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
        return Response({
            'verified': True,
            'unlockToken': issue_player_unlock(request.user.id, player.id),
        })


class PlayerPrivacyPinResetView(APIView):
    """POST clears a PIN for a linked guardian or same-club coordinator."""

    def post(self, request, player_id):
        if not _may_manage_pin(request.user, player_id):
            raise PermissionDenied('You cannot reset that player PIN.')
        if request.user.role not in (Roles.ADMIN, Roles.COORDINATOR, Roles.GUARDIAN):
            raise PermissionDenied('Only a guardian or coordinator can reset a PIN.')
        if (
            request.user.role == Roles.GUARDIAN
            and not _has_recent_firebase_reauthentication(request)
        ):
            raise PermissionDenied(
                'Recent guardian verification is required before resetting a PIN.'
            )
        player = _pin_profile(player_id).user
        reset_pin(player)
        AuditLog.record(
            request.user, 'player_pin.reset', target=player.email,
            detail=request.user.get_role_display(),
        )
        return Response(pin_status(player))


class PlayerAssessmentView(APIView):
    """PUT /api/players/<id>/assessment/ — coach updates the six ratings."""

    @staticmethod
    def _profile_for_coach(user, player_id):
        if user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can assess players.')
        profile = get_object_or_404(
            PlayerProfile.objects.select_related('user'), user_id=player_id
        )
        if user.club_id is None or profile.user.club_id != user.club_id:
            raise PermissionDenied('That player is not in your club.')
        return profile

    def get(self, request, player_id):
        profile = self._profile_for_coach(request.user, player_id)
        latest = PlayerDevelopmentAssessment.objects.select_related(
            'player', 'assessed_by'
        ).filter(player_id=player_id).first()
        return Response({
            'framework': framework_for(profile.age_tier, profile.position),
            'latestAssessment': (
                PlayerDevelopmentAssessmentSerializer(latest).data
                if latest else None
            ),
        })

    def put(self, request, player_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can assess players.')
        profile = get_object_or_404(
            PlayerProfile.objects.select_related('user'), user_id=player_id
        )
        # Tenancy: a coach may only assess players in their own club.
        if (
            request.user.club_id is None
            or profile.user.club_id != request.user.club_id
        ):
            raise PermissionDenied('That player is not in your club.')
        if 'developmentRatings' in request.data:
            return self._put_development(request, profile)
        with transaction.atomic():
            profile = PlayerProfile.objects.select_for_update().select_related(
                'user'
            ).get(pk=profile.pk)
            serializer = AssessmentSerializer(
                profile, data=request.data, partial=True
            )
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
                transaction.on_commit(lambda: notify_assessment_saved(profile))
        return Response(PlayerSerializer(profile).data)

    def _put_development(self, request, profile):
        legacy_fields = {
            'ratings', 'pace', 'shooting', 'passing', 'dribbling',
            'defending', 'physical', 'diving', 'handling', 'kicking',
            'reflexes', 'speed', 'positioning',
        }
        if legacy_fields.intersection(request.data):
            raise ValidationError({
                'developmentRatings': (
                    'Do not mix legacy 0-99 ratings with a development assessment.'
                ),
            })
        with transaction.atomic():
            profile = PlayerProfile.objects.select_for_update().select_related(
                'user'
            ).get(pk=profile.pk)
            serializer = DevelopmentAssessmentWriteSerializer(
                data=request.data,
                context={'profile': profile},
            )
            serializer.is_valid(raise_exception=True)
            data = serializer.validated_data
            reason = data['assessmentReason']
            new_notes = data.get('coachNotes', profile.coach_notes)
            changed = any((
                profile.development_framework_version
                != data['frameworkVersion'],
                profile.development_scores != data['developmentRatings'],
                profile.development_strengths != data['strengths'],
                profile.development_targets != data['developmentTargets'],
                profile.coach_notes != new_notes,
            ))
            if changed:
                profile.development_framework_version = data['frameworkVersion']
                profile.development_scores = data['developmentRatings']
                profile.development_strengths = data['strengths']
                profile.development_targets = data['developmentTargets']
                profile.development_assessed_at = timezone.now()
                profile.coach_notes = new_notes
                profile.save(update_fields=[
                    'development_framework_version', 'development_scores',
                    'development_strengths', 'development_targets',
                    'development_assessed_at', 'coach_notes',
                ])
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
                transaction.on_commit(
                    lambda profile=profile: notify_assessment_saved(profile)
                )
        return Response(PlayerSerializer(profile).data)


class PlayerAssessmentHistoryView(APIView):
    """Authorized, privacy-gated immutable assessment history."""

    def get(self, request, player_id):
        if not _may_read_match_statistics(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
        rows = PlayerAssessmentSnapshot.objects.select_related(
            'player', 'assessed_by'
        ).filter(player_id=player_id)
        return Response(
            PlayerAssessmentSnapshotSerializer(rows, many=True).data
        )


class PlayerPositionView(APIView):
    """PUT /api/players/<id>/position/ — coach assigns or changes a player's
    position. Was a client-side stub (ApiPlayerRepository.savePosition threw
    UnimplementedError) with no backend endpoint at all until this view."""

    def put(self, request, player_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can assign a position.')
        profile = get_object_or_404(
            PlayerProfile.objects.select_related('user'), user_id=player_id
        )
        # Tenancy: a coach may only edit players in their own club — same
        # check as PlayerAssessmentView.
        if (
            request.user.club_id is None
            or profile.user.club_id != request.user.club_id
        ):
            raise PermissionDenied('That player is not in your club.')
        serializer = PlayerPositionSerializer(
            profile, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        AuditLog.record(
            request.user, 'position.changed',
            target=profile.user.email, detail=profile.position,
        )
        return Response(PlayerSerializer(profile).data)


class AttendanceListView(APIView):
    """GET /api/attendance/?player=<id> — one player's attendance history.

    Object-level authz: a guardian may only read a player they are linked to; a
    player only themselves; coach/admin anyone. This is the fix for the BOLA
    risk in the audit (F3).
    """

    def get(self, request):
        player_id = request.query_params.get('player')
        if not player_id:
            raise ValidationError('A player query parameter is required.')
        if not _guardian_may_read(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        records = Attendance.objects.select_related(
            'session', 'recorded_by', 'player'
        ).filter(player_id=player_id)
        return Response(AttendanceSerializer(records, many=True).data)


class SessionAttendanceView(APIView):
    """GET/POST /api/attendance/session/<session_id>/ — one session's roll call.

    GET (coach/admin) returns every record for the session. POST (coach only)
    replaces the session's attendance wholesale: rows are upserted per player
    and rows for players absent from the payload are pruned, so re-finalising a
    session corrects it rather than duplicating it (matching the client's
    MockAttendanceRepository semantics).
    """

    def get(self, request, session_id):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view session attendance.')
        session = get_object_or_404(TrainingSession, pk=session_id)
        if not _session_in_user_scope(request.user, session):
            raise PermissionDenied('That session is not in your club.')
        if session.status == TrainingSessionStatus.CANCELLED:
            raise WorkflowConflict(
                'SESSION_CANCELLED',
                'Attendance is unavailable for a cancelled training session.',
            )
        records = Attendance.objects.select_related('session', 'recorded_by').filter(
            session_id=session_id
        )
        return Response(AttendanceSerializer(records, many=True).data)

    def post(self, request, session_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can record attendance.')
        session = get_object_or_404(TrainingSession, pk=session_id)
        if not _session_in_user_scope(request.user, session):
            raise PermissionDenied('That session is not in your club.')
        if session.status == TrainingSessionStatus.CANCELLED:
            raise WorkflowConflict(
                'SESSION_CANCELLED',
                'Attendance is unavailable for a cancelled training session.',
            )
        # Attendance is recorded close to when it happens: the session day
        # through two days after — never before the session. Mirrors the
        # client's TrainingSession.isAttendanceOpen guard.
        days_since = (timezone.localdate() - session.date).days
        if not 0 <= days_since <= 2:
            raise ValidationError(
                'Attendance can only be logged on the session day or up to '
                '2 days after.'
            )
        serializer = SessionAttendanceRecordSerializer(
            data=request.data.get('records', []), many=True
        )
        serializer.is_valid(raise_exception=True)
        # Tenancy: every player in the roll call must be in the coach's own club
        # (the serializer only checks the PLAYER role, not the club).
        submitted_ids = {r['playerId'] for r in serializer.validated_data}
        in_club = set(
            User.objects.filter(
                pk__in=submitted_ids, club_id=request.user.club_id
            ).values_list('id', flat=True)
        )
        if in_club != submitted_ids:
            raise PermissionDenied('One or more players are not in your club.')
        with transaction.atomic():
            kept_player_ids = []
            for record in serializer.validated_data:
                Attendance.objects.update_or_create(
                    player_id=record['playerId'],
                    session=session,
                    defaults={
                        'status': record['status'],
                        'effort': record.get('effort'),
                        'performance_score': record.get('performanceScore'),
                        'note': record.get('note') or '',
                        'recorded_by': request.user,
                    },
                )
                kept_player_ids.append(record['playerId'])
            Attendance.objects.filter(session=session).exclude(
                player_id__in=kept_player_ids
            ).delete()
            if session.status == TrainingSessionStatus.SCHEDULED:
                session.status = TrainingSessionStatus.COMPLETED
                session.save(update_fields=['status'])
        records = Attendance.objects.select_related('session', 'recorded_by').filter(
            session=session
        )
        return Response(AttendanceSerializer(records, many=True).data)


class TrainingSessionListCreateView(APIView):
    """GET (own club's sessions; Admin all) / POST (coach only)
    /api/training-sessions/."""

    def get(self, request):
        sessions = _sessions_for(request.user)
        return Response(TrainingSessionSerializer(sessions, many=True).data)

    def post(self, request):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can schedule sessions.')
        if request.user.club_id is None:
            raise PermissionDenied('Coach account must belong to a club.')
        serializer = TrainingSessionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        draft = TrainingSession(**serializer.validated_data)
        session_start, session_end = draft.interval()
        fixture = conflicting_fixture_for_training(
            club_id=request.user.club_id,
            tiers=draft.age_tiers,
            start=session_start,
            end=session_end,
        )
        if fixture is not None:
            conflict = fixture_conflict_payload(fixture)
            raise WorkflowConflict(
                'TOURNAMENT_SCHEDULE_CONFLICT',
                conflict['message'],
                conflict=conflict,
            )
        # Tenancy: the session belongs to the scheduling coach's club (set
        # server-side; the client never supplies it).
        session = serializer.save(
            created_by=request.user, club=request.user.club
        )
        AuditLog.record(
            request.user, 'session.scheduled',
            target=session.title, detail=str(session.date),
        )
        # Fan out the push only after the row is durably committed.
        transaction.on_commit(lambda: notify_session_scheduled(session))
        return Response(
            TrainingSessionSerializer(session).data, status=status.HTTP_201_CREATED
        )


def _tournament_schedule_data(value, request, *, many=False):
    return TournamentScheduleSerializer(
        value,
        many=many,
        context={'request': request},
    ).data


class TournamentScheduleListView(APIView):
    """Role-aware tournament list and Coordinator draft creation."""

    _roles = (
        Roles.COORDINATOR,
        Roles.COACH,
        Roles.PLAYER,
        Roles.GUARDIAN,
        Roles.ADMIN,
    )

    def get(self, request):
        if request.user.role not in self._roles:
            raise PermissionDenied(
                'Your role cannot view mobile tournament schedules.'
            )
        schedules = (
            TournamentSchedule.objects.all()
            .select_related('club')
            .prefetch_related(
                Prefetch(
                    'fixtures',
                    queryset=TournamentFixture.objects.select_related(
                        'age_bracket', 'completed_match',
                    ),
                ),
                'age_brackets__squad__entries__player__player_profile',
            )
        )
        if request.user.role == Roles.ADMIN:
            pass
        elif request.user.club_id is None:
            schedules = schedules.none()
        else:
            schedules = schedules.filter(club_id=request.user.club_id)
            if request.user.role != Roles.COORDINATOR:
                schedules = schedules.filter(is_published=True)
        return Response(
            _tournament_schedule_data(schedules, request, many=True)
        )

    def post(self, request):
        if request.user.role != Roles.COORDINATOR:
            raise PermissionDenied('Only Coordinators can create tournaments.')
        if request.user.club_id is None:
            raise PermissionDenied('Coordinator account must belong to a club.')
        serializer = TournamentScheduleWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        document = request.FILES.get('document')
        content_type = None
        if document is not None:
            try:
                content_type = validate_tournament_document(document)
            except ValueError as exc:
                raise ValidationError({'document': str(exc)}) from exc
        document_path = ''
        try:
            with transaction.atomic():
                schedule = serializer.save(
                    club=request.user.club,
                    uploaded_by=request.user,
                    is_published=False,
                    published_at=None,
                )
                if document is not None:
                    document_path = upload_tournament_document(
                        request.user.club_id,
                        schedule.id,
                        document.read(),
                        content_type,
                    )
                    schedule.document_path = document_path
                    schedule.save(update_fields=['document_path', 'updated_at'])
        except RuntimeError as exc:
            if document_path:
                delete_tournament_document(document_path)
            raise ValidationError({'document': str(exc)}) from exc
        AuditLog.record(
            request.user,
            'tournament.draft_created',
            target=schedule.title,
            detail=(
                f'{schedule.starts_on} | '
                f'{"document uploaded" if document else "manual schedule"}'
            ),
        )
        return Response(
            _tournament_schedule_data(schedule, request),
            status=status.HTTP_201_CREATED,
        )


def _coordinator_mobile_schedule(user, schedule_id, *, lock=False):
    if user.role != Roles.COORDINATOR:
        raise PermissionDenied('Only Coordinators can manage tournaments.')
    if user.club_id is None:
        raise PermissionDenied('Coordinator account must belong to a club.')
    queryset = TournamentSchedule.objects.prefetch_related(
            Prefetch(
                'fixtures',
                queryset=TournamentFixture.objects.select_related(
                    'age_bracket', 'completed_match',
                ),
            ),
            'age_brackets__squad__entries__player__player_profile',
        )
    if lock:
        queryset = queryset.select_for_update()
    return get_object_or_404(
        queryset,
        pk=schedule_id,
        club_id=user.club_id,
    )


class TournamentScheduleDetailView(APIView):
    """Read, edit, or safely remove one Coordinator-owned tournament."""

    def get(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        return Response(_tournament_schedule_data(schedule, request))

    def patch(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        old_title = schedule.title
        old_date = schedule.starts_on
        with transaction.atomic():
            serializer = TournamentScheduleWriteSerializer(
                schedule, data=request.data, partial=True,
            )
            serializer.is_valid(raise_exception=True)
            schedule = serializer.save()
            invalid = []
            for bracket in schedule.age_brackets.all():
                invalid.extend(
                    (entry, result)
                    for entry, result in invalid_squad_entries(bracket)
                    if result.code in ('OVERAGE', 'DOB_REQUIRED', 'PROFILE_REQUIRED')
                )
            if invalid:
                names = ', '.join(
                    entry.player.get_full_name() or entry.player.email
                    for entry, _ in invalid
                )
                raise ValidationError({
                    'startsOn': f'Roster members must be reviewed first: {names}.'
                })
        AuditLog.record(
            request.user,
            'tournament.updated',
            target=schedule.title,
            detail=(
                f'{old_title} ({old_date}) -> '
                f'{schedule.title} ({schedule.starts_on})'
            ),
        )
        return Response(_tournament_schedule_data(schedule, request))

    def delete(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        if schedule.fixtures.filter(completed_match__isnull=False).exists():
            raise ValidationError({
                'tournament': (
                    'This tournament has completed matches and cannot be deleted.'
                )
            })
        target = schedule.title
        document_path = schedule.document_path
        schedule.delete()
        delete_tournament_document(document_path)
        AuditLog.record(request.user, 'tournament.deleted', target=target)
        return Response(status=status.HTTP_204_NO_CONTENT)


class TournamentSchedulePublishView(APIView):
    """Publish a configured tournament to the whole club."""

    def post(self, request, schedule_id):
        with transaction.atomic():
            schedule = _coordinator_mobile_schedule(
                request.user, schedule_id, lock=True,
            )
            errors = schedule.publication_errors()
            if errors:
                raise ValidationError(errors)
            if schedule.is_published:
                return Response(_tournament_schedule_data(schedule, request))
            fixtures = list(
                TournamentFixture.objects.select_for_update().select_related(
                    'schedule', 'age_bracket',
                ).filter(schedule=schedule)
            )
            conflicts = conflicting_training_for_fixtures(fixtures, lock=True)
            if conflicts and not _confirmed(request):
                raise WorkflowConflict(
                    'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
                    'Publishing this tournament will cancel conflicting future '
                    'training sessions. Confirm to continue.',
                    cancellation=_training_cancellation_details(conflicts),
                )
            schedule.is_published = True
            schedule.published_at = timezone.now()
            schedule.save(update_fields=[
                'is_published', 'published_at', 'updated_at',
            ])
            cancel_conflicting_training(
                fixtures,
                actor=request.user,
                action='tournament.published',
            )
            AuditLog.record(
                request.user,
                'tournament.published',
                target=schedule.title,
                detail=str(schedule.starts_on),
            )
        return Response(_tournament_schedule_data(schedule, request))


class TournamentScheduleDocumentView(APIView):
    """Replace or remove the private official schedule document."""

    def post(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        document = request.FILES.get('document')
        if document is None:
            raise ValidationError({'document': 'Choose a document to upload.'})
        try:
            content_type = validate_tournament_document(document)
        except ValueError as exc:
            raise ValidationError({'document': str(exc)}) from exc
        old_path = schedule.document_path
        try:
            new_path = upload_tournament_document(
                request.user.club_id,
                schedule.id,
                document.read(),
                content_type,
            )
        except RuntimeError as exc:
            raise ValidationError({'document': str(exc)}) from exc
        schedule.document_path = new_path
        schedule.uploaded_by = request.user
        schedule.save(update_fields=[
            'document_path', 'uploaded_by', 'updated_at',
        ])
        if old_path and old_path != new_path:
            invalidate_signed_tournament_document_url(old_path)
            delete_tournament_document(old_path)
        invalidate_signed_tournament_document_url(new_path)
        AuditLog.record(
            request.user,
            'tournament.document_replaced' if old_path
            else 'tournament.document_uploaded',
            target=schedule.title,
        )
        return Response(_tournament_schedule_data(schedule, request))

    def delete(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        old_path = schedule.document_path
        if not old_path:
            return Response(status=status.HTTP_204_NO_CONTENT)
        schedule.document_path = ''
        schedule.save(update_fields=['document_path', 'updated_at'])
        invalidate_signed_tournament_document_url(old_path)
        delete_tournament_document(old_path)
        AuditLog.record(
            request.user,
            'tournament.document_removed',
            target=schedule.title,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class TournamentFixtureCreateView(APIView):
    """Add a manually-entered fixture to the shared tournament schedule."""

    def post(self, request, schedule_id):
        with transaction.atomic():
            schedule = _coordinator_mobile_schedule(
                request.user, schedule_id, lock=True,
            )
            serializer = TournamentFixtureWriteSerializer(
                data=request.data,
                context={'schedule': schedule},
            )
            serializer.is_valid(raise_exception=True)
            fixture = serializer.save(schedule=schedule)
            if schedule.is_published:
                conflicts = conflicting_training_for_fixtures(
                    [fixture], lock=True,
                )
                if conflicts and not _confirmed(request):
                    raise WorkflowConflict(
                        'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
                        'Adding this fixture will cancel conflicting future '
                        'training sessions. Confirm to continue.',
                        cancellation=_training_cancellation_details(conflicts),
                    )
                cancel_conflicting_training(
                    [fixture],
                    actor=request.user,
                    action='tournament.fixture_created',
                )
            AuditLog.record(
                request.user,
                'tournament.fixture_created',
                target=f'{schedule.title} vs {fixture.opponent}',
                detail=fixture.kickoff_at.isoformat(),
            )
        schedule.refresh_from_db()
        return Response(
            _tournament_schedule_data(schedule, request),
            status=status.HTTP_201_CREATED,
        )


def _coordinator_mobile_fixture(user, fixture_id, *, lock=False):
    if user.role != Roles.COORDINATOR:
        raise PermissionDenied('Only Coordinators can manage fixtures.')
    if user.club_id is None:
        raise PermissionDenied('Coordinator account must belong to a club.')
    queryset = TournamentFixture.objects.select_related(
        'schedule', 'age_bracket', 'completed_match',
    )
    if lock:
        queryset = queryset.select_for_update()
    return get_object_or_404(
        queryset,
        pk=fixture_id,
        schedule__club_id=user.club_id,
    )


class TournamentFixtureDetailView(APIView):
    def patch(self, request, fixture_id):
        with transaction.atomic():
            fixture = _coordinator_mobile_fixture(
                request.user, fixture_id, lock=True,
            )
            if (
                fixture.completed_match_id
                or fixture.status == FixtureStatus.COMPLETED
            ):
                raise ValidationError({
                    'fixture': 'A completed fixture\'s schedule cannot be edited.'
                })
            serializer = TournamentFixtureWriteSerializer(
                fixture,
                data=request.data,
                partial=True,
                context={'schedule': fixture.schedule},
            )
            serializer.is_valid(raise_exception=True)
            fixture = serializer.save()
            if fixture.schedule.is_published:
                conflicts = conflicting_training_for_fixtures(
                    [fixture], lock=True,
                )
                if conflicts and not _confirmed(request):
                    raise WorkflowConflict(
                        'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
                        'Rescheduling this fixture will cancel conflicting '
                        'future training sessions. Confirm to continue.',
                        cancellation=_training_cancellation_details(conflicts),
                    )
                cancel_conflicting_training(
                    [fixture],
                    actor=request.user,
                    action='tournament.fixture_updated',
                )
            AuditLog.record(
                request.user,
                'tournament.fixture_updated',
                target=f'{fixture.schedule.title} vs {fixture.opponent}',
                detail=fixture.kickoff_at.isoformat(),
            )
        fixture.schedule.refresh_from_db()
        return Response(_tournament_schedule_data(fixture.schedule, request))

    def delete(self, request, fixture_id):
        fixture = _coordinator_mobile_fixture(request.user, fixture_id)
        if fixture.completed_match_id or fixture.status == FixtureStatus.COMPLETED:
            raise ValidationError({
                'fixture': 'A completed fixture cannot be deleted.'
            })
        schedule = fixture.schedule
        target = f'{schedule.title} vs {fixture.opponent}'
        fixture.delete()
        AuditLog.record(
            request.user,
            'tournament.fixture_deleted',
            target=target,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class TournamentFixtureResultView(APIView):
    """Atomically create the tournament match and all participant statistics."""

    def post(self, request, fixture_id):
        serializer = TournamentFixtureResultWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = serializer.validated_data
        with transaction.atomic():
            fixture = _coordinator_mobile_fixture(
                request.user, fixture_id, lock=True,
            )
            try:
                complete_tournament_fixture(
                    fixture=fixture,
                    actor=request.user,
                    payload=payload,
                )
            except DjangoValidationError as exc:
                raise ValidationError(exc.message_dict) from exc
        fixture.schedule.refresh_from_db()
        return Response(_tournament_schedule_data(fixture.schedule, request))


class TournamentAgeBracketCreateView(APIView):
    """Add one flexible U-age bracket to a Coordinator's tournament."""

    def post(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        serializer = TournamentAgeBracketWriteSerializer(
            data=request.data,
            context={'schedule': schedule},
        )
        serializer.is_valid(raise_exception=True)
        bracket = serializer.save(schedule=schedule)
        TournamentSchedule.objects.filter(pk=schedule.pk).update(
            updated_at=timezone.now()
        )
        AuditLog.record(
            request.user,
            'tournament.bracket_added',
            target=f'{schedule.title} {bracket.label}',
            detail=bracket.scheduled_at or 'Schedule time TBD',
        )
        schedule.refresh_from_db()
        return Response(
            _tournament_schedule_data(schedule, request),
            status=status.HTTP_201_CREATED,
        )


def _coordinator_mobile_bracket(user, bracket_id, *, lock=False):
    if user.role != Roles.COORDINATOR:
        raise PermissionDenied('Only Coordinators can manage age brackets.')
    if user.club_id is None:
        raise PermissionDenied('Coordinator account must belong to a club.')
    queryset = TournamentAgeBracket.objects.select_related('schedule')
    if lock:
        queryset = queryset.select_for_update()
    return get_object_or_404(
        queryset,
        pk=bracket_id,
        schedule__club_id=user.club_id,
    )


class TournamentAgeBracketDetailView(APIView):
    def patch(self, request, bracket_id):
        with transaction.atomic():
            bracket = _coordinator_mobile_bracket(
                request.user, bracket_id, lock=True,
            )
            serializer = TournamentAgeBracketWriteSerializer(
                bracket,
                data=request.data,
                partial=True,
                context={'schedule': bracket.schedule},
            )
            serializer.is_valid(raise_exception=True)
            bracket = serializer.save()
            invalid = [
                (entry, result)
                for entry, result in invalid_squad_entries(bracket)
                if result.code in ('OVERAGE', 'DOB_REQUIRED', 'PROFILE_REQUIRED')
            ]
            if invalid:
                names = ', '.join(
                    entry.player.get_full_name() or entry.player.email
                    for entry, _ in invalid
                )
                raise ValidationError({
                    'maxAge': f'Roster members must be reviewed first: {names}.'
                })
            if bracket.schedule.is_published:
                fixtures = list(
                    TournamentFixture.objects.select_for_update().select_related(
                        'schedule', 'age_bracket',
                    ).filter(age_bracket=bracket)
                )
                conflicts = conflicting_training_for_fixtures(
                    fixtures, lock=True,
                )
                if conflicts and not _confirmed(request):
                    raise WorkflowConflict(
                        'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
                        'Changing this bracket association will cancel '
                        'conflicting future training sessions. Confirm to '
                        'continue.',
                        cancellation=_training_cancellation_details(conflicts),
                    )
                cancel_conflicting_training(
                    fixtures,
                    actor=request.user,
                    action='tournament.bracket_updated',
                )
        TournamentSchedule.objects.filter(pk=bracket.schedule_id).update(
            updated_at=timezone.now()
        )
        AuditLog.record(
            request.user,
            'tournament.bracket_updated',
            target=f'{bracket.schedule.title} {bracket.label}',
            detail=bracket.scheduled_at or 'Schedule time TBD',
        )
        bracket.schedule.refresh_from_db()
        return Response(_tournament_schedule_data(bracket.schedule, request))

    def delete(self, request, bracket_id):
        bracket = _coordinator_mobile_bracket(request.user, bracket_id)
        schedule = bracket.schedule
        if schedule.is_published:
            raise ValidationError({
                'ageBracket': 'Published tournament brackets cannot be removed.'
            })
        if bracket.fixtures.exists():
            raise ValidationError({
                'ageBracket': 'Remove linked fixtures before deleting this bracket.'
            })
        try:
            squad_has_entries = bracket.squad.entries.exists()
        except TournamentSquad.DoesNotExist:
            squad_has_entries = False
        if squad_has_entries:
            raise ValidationError({
                'ageBracket': 'Remove roster members before deleting this bracket.'
            })
        target = f'{schedule.title} {bracket.label}'
        bracket.delete()
        TournamentSchedule.objects.filter(pk=schedule.pk).update(
            updated_at=timezone.now()
        )
        AuditLog.record(
            request.user,
            'tournament.bracket_removed',
            target=target,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


def _mobile_tournament_bracket(user, bracket_id):
    allowed = (
        Roles.COORDINATOR,
        Roles.COACH,
        Roles.PLAYER,
        Roles.GUARDIAN,
        Roles.ADMIN,
    )
    if user.role not in allowed:
        raise PermissionDenied('Your role cannot view tournament rosters.')
    brackets = TournamentAgeBracket.objects.select_related(
        'schedule', 'schedule__club',
    )
    if user.role != Roles.ADMIN:
        if user.club_id is None:
            raise PermissionDenied('Your account must belong to a club.')
        brackets = brackets.filter(schedule__club_id=user.club_id)
    bracket = get_object_or_404(brackets, pk=bracket_id)
    if (
        user.role not in (Roles.COACH, Roles.COORDINATOR, Roles.ADMIN)
        and not bracket.schedule.is_published
    ):
        raise PermissionDenied('This tournament has not been published.')
    return bracket


def _squad_data(squad, request):
    return TournamentSquadSerializer(
        squad,
        context={'request': request},
    ).data


class TournamentSquadDetailView(APIView):
    """Read a role-visible roster or atomically save it as a Coach."""

    def get(self, request, bracket_id):
        bracket = _mobile_tournament_bracket(request.user, bracket_id)
        try:
            squad = TournamentSquad.objects.prefetch_related(
                'entries__player__player_profile',
            ).get(bracket=bracket)
        except TournamentSquad.DoesNotExist:
            if request.user.role not in (
                Roles.COACH, Roles.COORDINATOR, Roles.ADMIN,
            ):
                raise PermissionDenied('No published roster is available.')
            return Response({
                'id': None,
                'bracketId': str(bracket.id),
                'status': TournamentSquadStatus.DRAFT,
                'publishedAt': None,
                'entries': [],
            })
        if (
            squad.status != TournamentSquadStatus.PUBLISHED
            and request.user.role not in (
                Roles.COACH, Roles.COORDINATOR, Roles.ADMIN,
            )
        ):
            raise PermissionDenied('No published roster is available.')
        return Response(_squad_data(squad, request))

    def put(self, request, bracket_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only Coaches can manage tournament rosters.')
        bracket = _mobile_tournament_bracket(request.user, bracket_id)
        serializer = TournamentSquadWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        rows = serializer.validated_data['entries']
        player_ids = [row['playerId'] for row in rows]
        players = {
            player.id: player
            for player in User.objects.filter(
                id__in=player_ids,
                role=Roles.PLAYER,
                club_id=request.user.club_id,
                is_active=True,
            ).select_related('player_profile')
        }
        missing = sorted(set(player_ids) - set(players))
        if missing:
            raise ValidationError({
                'entries': f'Unknown or inactive club player IDs: {missing}.'
            })
        blocked = {
            player_id: result.reason
            for player_id, player in players.items()
            if (result := roster_eligibility(player, bracket)).blocked
        }
        if blocked:
            raise ValidationError({'entries': blocked})

        with transaction.atomic():
            squad, _ = TournamentSquad.objects.select_for_update().get_or_create(
                bracket=bracket,
                defaults={'updated_by': request.user},
            )
            if squad.status == TournamentSquadStatus.PUBLISHED:
                raise WorkflowConflict(
                    'ROSTER_LOCKED',
                    'This roster has been published and can no longer be changed.',
                )
            current = {
                entry.player_id: entry
                for entry in squad.entries.select_related('player')
            }
            incoming = set(player_ids)
            removed = set(current) - incoming
            added = incoming - set(current)
            changed_positions = []
            if removed:
                squad.entries.filter(player_id__in=removed).delete()
            for row in rows:
                player_id = row['playerId']
                position = row.get('position', '')
                entry = current.get(player_id)
                if entry is None:
                    TournamentSquadEntry.objects.create(
                        squad=squad,
                        player=players[player_id],
                        position=position,
                        added_by=request.user,
                    )
                elif entry.position != position:
                    entry.position = position
                    entry.save(update_fields=['position', 'updated_at'])
                    changed_positions.append(player_id)
            squad.updated_by = request.user
            squad.save(update_fields=['updated_by', 'updated_at'])
            AuditLog.record(
                request.user,
                'tournament.squad_saved',
                target=f'{bracket.schedule.title} {bracket.label}',
                detail=(
                    f'added={sorted(added)}; removed={sorted(removed)}; '
                    f'positions={sorted(changed_positions)}'
                ),
            )
        squad = TournamentSquad.objects.prefetch_related(
            'entries__player__player_profile',
        ).get(pk=squad.pk)
        return Response(_squad_data(squad, request))


class TournamentSquadCandidatesView(APIView):
    """Coach-only player choices with privacy-safe eligibility outcomes."""

    def get(self, request, bracket_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only Coaches can select roster members.')
        bracket = _mobile_tournament_bracket(request.user, bracket_id)
        try:
            squad = bracket.squad
            selected = {
                entry.player_id: entry.position
                for entry in squad.entries.all()
            }
        except TournamentSquad.DoesNotExist:
            selected = {}
        players = User.objects.filter(
            role=Roles.PLAYER,
            club_id=request.user.club_id,
            is_active=True,
        ).select_related('player_profile').order_by(
            'last_name', 'first_name', 'email',
        )
        data = []
        for player in players:
            result = roster_eligibility(player, bracket)
            name = player.get_full_name().strip() or player.email.split('@')[0]
            try:
                current_position = player.player_profile.position
            except PlayerProfile.DoesNotExist:
                current_position = ''
            data.append({
                'playerId': str(player.id),
                'playerName': name,
                'currentPosition': current_position,
                'eligibility': result.state,
                'eligibilityCode': result.code,
                'eligibilityReason': result.reason,
                'selected': player.id in selected,
                'tournamentPosition': selected.get(player.id, ''),
            })
        return Response(data)


class TournamentSquadPublishView(APIView):
    def post(self, request, bracket_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only Coaches can publish tournament rosters.')
        bracket = _mobile_tournament_bracket(request.user, bracket_id)
        if not bracket.schedule.is_published:
            raise ValidationError({
                'tournament': 'The Coordinator must publish the tournament first.'
            })
        with transaction.atomic():
            squad = get_object_or_404(
                TournamentSquad.objects.select_for_update().prefetch_related(
                    'entries__player__player_profile',
                ),
                bracket=bracket,
            )
            if squad.status == TournamentSquadStatus.PUBLISHED:
                raise WorkflowConflict(
                    'ROSTER_ALREADY_PUBLISHED',
                    'This roster has already been published.',
                )
            entries = list(squad.entries.all())
            if not entries:
                raise ValidationError({'entries': 'Add at least one player first.'})
            blocked = {
                str(entry.player_id): result.reason
                for entry in entries
                if (result := roster_eligibility(entry.player, bracket)).blocked
            }
            if blocked:
                raise ValidationError({'entries': blocked})
            squad.status = TournamentSquadStatus.PUBLISHED
            squad.published_at = timezone.now()
            squad.updated_by = request.user
            squad.save(update_fields=[
                'status', 'published_at', 'updated_by', 'updated_at',
            ])
            AuditLog.record(
                request.user,
                'tournament.squad_published',
                target=f'{bracket.schedule.title} {bracket.label}',
                detail=f'{len(entries)} players',
            )
            transaction.on_commit(
                lambda: notify_tournament_roster_published(squad)
            )
        return Response(_squad_data(squad, request))


class FootballMatchListCreateView(APIView):
    """List completed matches or let a Coordinator record a result."""

    def get(self, request):
        if request.user.role not in (
            Roles.COORDINATOR, Roles.COACH, Roles.ADMIN,
        ):
            raise PermissionDenied('Your role cannot view club match records.')
        return Response(
            FootballMatchSerializer(_matches_for(request.user), many=True).data
        )

    def post(self, request):
        if request.user.role != Roles.COORDINATOR:
            raise PermissionDenied('Only Coordinators can create match records.')
        if request.user.club_id is None:
            raise PermissionDenied('Coordinator account must belong to a club.')

        fixture_id = request.data.get('fixtureId')
        if fixture_id not in (None, ''):
            raise ValidationError({
                'fixtureId': (
                    'Use the fixture Record Result action so participants and '
                    'objective statistics are saved atomically.'
                )
            })
        match_data = request.data.copy()
        match_data.pop('fixtureId', None)
        serializer = FootballMatchSerializer(data=match_data)
        serializer.is_valid(raise_exception=True)
        match = serializer.save(
            club=request.user.club,
            created_by=request.user,
        )
        AuditLog.record(
            request.user,
            'match.created',
            target=str(match.pk),
            detail=(
                f'{match.opponent} | {match.played_on} | ad-hoc'
            ),
        )
        return Response(
            FootballMatchSerializer(match).data,
            status=status.HTTP_201_CREATED,
        )


class FootballMatchDetailView(APIView):
    """Read or correct match metadata without changing tenant ownership."""

    def get(self, request, match_id):
        if request.user.role not in (
            Roles.COORDINATOR, Roles.COACH, Roles.ADMIN,
        ):
            raise PermissionDenied('Your role cannot view club match records.')
        match = get_object_or_404(_matches_for(request.user), pk=match_id)
        return Response(FootballMatchSerializer(match).data)

    def put(self, request, match_id):
        match = _role_match(request, match_id, Roles.COORDINATOR)
        data = request.data.copy()
        data.pop('fixtureId', None)
        if hasattr(match, 'source_fixture'):
            data = {
                key: data[key]
                for key in ('ourScore', 'opponentScore')
                if key in data
            }
        serializer = FootballMatchSerializer(
            match, data=data, partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        AuditLog.record(
            request.user,
            'match.updated',
            target=str(match.pk),
            detail=f'{match.opponent} | {match.played_on}',
        )
        return Response(FootballMatchSerializer(match).data)


class MatchPerformanceListView(APIView):
    """Role-redacted read view for all recorded players in one match."""

    def get(self, request, match_id):
        if request.user.role not in (
            Roles.COORDINATOR, Roles.COACH, Roles.ADMIN,
        ):
            raise PermissionDenied('Your role cannot view match performances.')
        match = get_object_or_404(_matches_for(request.user), pk=match_id)
        rows = PlayerMatchPerformance.objects.select_related(
            'match', 'player', 'match__club',
        ).filter(match=match)
        return Response(PlayerMatchPerformanceSerializer(
            rows, many=True, context={'request': request},
        ).data)


class MatchRosterView(APIView):
    """Server-filtered current match choices plus existing historical rows."""

    def get(self, request, match_id):
        if request.user.role not in (
            Roles.COORDINATOR, Roles.COACH, Roles.ADMIN,
        ):
            raise PermissionDenied('Your role cannot view this match roster.')
        match = get_object_or_404(_matches_for(request.user), pk=match_id)
        bracket = _match_age_bracket(match)
        include_out_of_squad = (
            request.query_params.get('includeOutOfSquad', '').lower() == 'true'
        )
        if include_out_of_squad and request.user.role != Roles.COORDINATOR:
            raise PermissionDenied(
                'Only Coordinators can review out-of-squad match candidates.'
            )
        profiles = PlayerProfile.objects.select_related('user').filter(
            user__club_id=match.club_id,
            user__role=Roles.PLAYER,
            user__is_active=True,
        ).order_by('user__last_name', 'user__first_name', 'user__id')
        performances = {
            row.player_id: row
            for row in PlayerMatchPerformance.objects.select_related(
                'match', 'player', 'match__club',
            ).filter(match=match)
        }
        squad_entries = {}
        if bracket is not None:
            squad_entries = {
                entry.player_id: entry
                for entry in TournamentSquadEntry.objects.select_related(
                    'player__player_profile',
                ).filter(
                    squad__bracket=bracket,
                    squad__status=TournamentSquadStatus.PUBLISHED,
                )
            }
        active_injury_statuses = {}
        for player_id, injury_status in InjuryRecord.objects.filter(
            player__club_id=match.club_id,
            review_status=InjuryReportStatus.CONFIRMED,
            status__in=(InjuryStatus.ACTIVE, InjuryStatus.RECOVERING),
        ).values_list('player_id', 'status'):
            current = active_injury_statuses.get(player_id)
            if current is None or injury_status == InjuryStatus.ACTIVE:
                active_injury_statuses[player_id] = injury_status
        result = []
        for profile in profiles:
            performance = performances.get(profile.user_id)
            squad_entry = squad_entries.get(profile.user_id)
            eligibility = (
                roster_eligibility(profile.user, bracket)
                if bracket is not None else None
            )
            in_tournament_squad = squad_entry is not None
            if bracket is not None:
                if eligibility.blocked and performance is None:
                    continue
                if (
                    not include_out_of_squad
                    and not in_tournament_squad
                    and performance is None
                ):
                    continue
            selectable = eligibility is None or not eligibility.blocked
            result.append({
                'id': str(profile.user_id),
                'name': (
                    f'{profile.user.first_name} {profile.user.last_name}'.strip()
                    or profile.user.email.split('@')[0]
                ),
                'registeredPosition': profile.position,
                'tournamentPosition': (
                    squad_entry.position if squad_entry is not None else ''
                ),
                'inTournamentSquad': in_tournament_squad,
                'requiresSquadOverride': (
                    bracket is not None and not in_tournament_squad
                ),
                'isSelectable': selectable,
                'availability': (
                    eligibility.state if eligibility is not None else 'ELIGIBLE'
                ),
                'availabilityReason': (
                    eligibility.reason if eligibility is not None else ''
                ),
                'activeInjuryStatus': active_injury_statuses.get(
                    profile.user_id
                ),
                'performance': (
                    PlayerMatchPerformanceSerializer(
                        performance, context={'request': request},
                    ).data
                    if performance else None
                ),
                'ratingStatus': (
                    'RATED'
                    if performance and performance.coach_rating is not None
                    else 'AWAITING_RATING'
                    if performance
                    else 'AWAITING_STATISTICS'
                ),
            })
        return Response(result)


class MatchPerformanceDetailView(APIView):
    """Coordinator-owned objective statistics for one player/match."""

    def put(self, request, match_id, player_id):
        match = _role_match(request, match_id, Roles.COORDINATOR)
        player = get_object_or_404(
            User.objects.select_related('player_profile'),
            pk=player_id,
            role=Roles.PLAYER,
            club_id=request.user.club_id,
        )
        bracket = _match_age_bracket(match)
        active_injuries = InjuryRecord.objects.filter(
            player=player,
            review_status=InjuryReportStatus.CONFIRMED,
            status__in=(InjuryStatus.ACTIVE, InjuryStatus.RECOVERING),
        ) if bracket is None else InjuryRecord.objects.none()
        injury_override = str(
            request.data.get('injuryOverrideAcknowledged', '')
        ).lower() == 'true'
        if active_injuries.exists() and not injury_override:
            return Response(
                {
                    'code': 'ACTIVE_INJURY_WARNING',
                    'detail': (
                        'This player has a confirmed Active or Recovering '
                        'injury. Acknowledge the warning to continue.'
                    ),
                    'injuries': [
                        {
                            'id': str(injury.id),
                            'description': injury.description,
                            'status': injury.status,
                        }
                        for injury in active_injuries
                    ],
                },
                status=status.HTTP_409_CONFLICT,
            )
        data = request.data.copy()
        data.pop('injuryOverrideAcknowledged', None)
        requested_squad_reason = str(
            data.pop('squadOverrideReason', '')
        ).strip()
        if len(requested_squad_reason) > 500:
            raise ValidationError({
                'squadOverrideReason': 'Use 500 characters or fewer.'
            })
        squad_override_applied = False
        squad_override_reason = ''
        with transaction.atomic():
            # Lock the parent to serialize two submissions for the same match;
            # the unique DB constraint is the final duplicate-write guard.
            match = FootballMatch.objects.select_for_update().select_related(
                'source_fixture__age_bracket__schedule',
            ).get(pk=match.pk)
            bracket = _match_age_bracket(match)
            existing = PlayerMatchPerformance.objects.select_for_update().filter(
                match=match, player=player,
            ).first()
            save_kwargs = {}
            if bracket is not None:
                eligibility = roster_eligibility(player, bracket)
                if eligibility.blocked:
                    raise ValidationError({
                        'player': {
                            'code': eligibility.code,
                            'detail': eligibility.reason,
                        }
                    })
                squad = TournamentSquad.objects.select_for_update().filter(
                    bracket=bracket,
                    status=TournamentSquadStatus.PUBLISHED,
                ).first()
                in_published_squad = (
                    squad is not None
                    and squad.entries.filter(player=player).exists()
                )
                if not in_published_squad:
                    previous_reason = (
                        existing.squad_override_reason if existing else ''
                    )
                    squad_override_reason = (
                        requested_squad_reason or previous_reason
                    ).strip()
                    if not squad_override_reason:
                        raise ValidationError({
                            'squadOverrideReason': (
                                'Explain why this eligible out-of-squad player '
                                'is being added to the match.'
                            )
                        })
                    if squad_override_reason != previous_reason:
                        save_kwargs.update({
                            'squad_override_reason': squad_override_reason,
                            'squad_override_by': request.user,
                            'squad_override_at': timezone.now(),
                        })
                        squad_override_applied = True
            serializer = PlayerMatchStatisticsWriteSerializer(
                existing, data=data,
            )
            serializer.is_valid(raise_exception=True)
            proposed_goals = serializer.validated_data.get(
                'goals', existing.goals if existing else 0,
            )
            other_goals = PlayerMatchPerformance.objects.filter(
                match=match,
            ).exclude(player=player).aggregate(total=Sum('goals'))['total'] or 0
            if other_goals + proposed_goals > match.our_score:
                raise ValidationError({
                    'goals': 'Recorded player goals exceed the team score.'
                })
            proposed_conceded = serializer.validated_data.get(
                'goals_conceded', existing.goals_conceded if existing else 0,
            )
            if proposed_conceded > match.opponent_score:
                raise ValidationError({
                    'goalsConceded': (
                        'Goals conceded cannot exceed the opponent score.'
                    )
                })
            performance = serializer.save(
                match=match,
                player=player,
                recorded_by=request.user,
                **save_kwargs,
            )
        AuditLog.record(
            request.user,
            'match.performance_saved',
            target=f'{match.pk}:{player.pk}',
        )
        if injury_override and active_injuries.exists():
            AuditLog.record(
                request.user,
                'match.injury_override',
                target=f'{match.pk}:{player.pk}',
                detail=','.join(str(item.id) for item in active_injuries),
            )
        if squad_override_applied:
            AuditLog.record(
                request.user,
                'match.squad_override',
                target=f'{match.pk}:{player.pk}',
                detail=squad_override_reason,
            )
        return Response(
            PlayerMatchPerformanceSerializer(
                performance, context={'request': request},
            ).data,
            status=status.HTTP_200_OK if existing else status.HTTP_201_CREATED,
        )

    def delete(self, request, match_id, player_id):
        match = _role_match(request, match_id, Roles.COORDINATOR)
        performance = get_object_or_404(
            PlayerMatchPerformance,
            match=match,
            player_id=player_id,
        )
        if (
            performance.coach_rating is not None
            and request.query_params.get('confirmRated', '').lower() != 'true'
        ):
            return Response(
                {'detail': 'Deleting these statistics also removes the Coach rating.'},
                status=status.HTTP_409_CONFLICT,
            )
        performance.delete()
        AuditLog.record(
            request.user,
            'match.performance_deleted',
            target=f'{match.pk}:{player_id}',
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class MatchPerformanceRatingView(APIView):
    """Coach-only rating and optional notes for existing objective statistics."""

    def put(self, request, match_id, player_id):
        match = _role_match(request, match_id, Roles.COACH)
        with transaction.atomic():
            performance = get_object_or_404(
                PlayerMatchPerformance.objects.select_for_update().select_related(
                    'match', 'player',
                ),
                match=match,
                player_id=player_id,
            )
            serializer = CoachMatchRatingSerializer(
                performance,
                data=request.data,
                partial=False,
            )
            serializer.is_valid(raise_exception=True)
            performance = serializer.save(
                rated_by=request.user,
                rated_at=timezone.now(),
            )
        AuditLog.record(
            request.user,
            'match.rating_saved',
            target=f'{match.pk}:{player_id}',
        )
        return Response(PlayerMatchPerformanceSerializer(
            performance, context={'request': request},
        ).data)

    def delete(self, request, match_id, player_id):
        match = _role_match(request, match_id, Roles.COACH)
        performance = get_object_or_404(
            PlayerMatchPerformance,
            match=match,
            player_id=player_id,
        )
        performance.coach_rating = None
        performance.notes = ''
        performance.rated_by = None
        performance.rated_at = None
        performance.save(update_fields=[
            'coach_rating', 'notes', 'rated_by', 'rated_at', 'updated_at',
        ])
        AuditLog.record(
            request.user,
            'match.rating_cleared',
            target=f'{match.pk}:{player_id}',
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class PlayerMatchStatisticsView(APIView):
    """Historical match totals and trend rows for one authorized player."""

    _MAX_ROWS = 100

    def get(self, request, player_id):
        if not _may_read_match_statistics(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        player = get_object_or_404(
            User.objects.select_related('player_profile'),
            pk=player_id,
            role=Roles.PLAYER,
        )

        rows = PlayerMatchPerformance.objects.select_related(
            'match', 'match__club', 'player',
        ).filter(player=player)
        from_text = request.query_params.get('from')
        to_text = request.query_params.get('to')
        if from_text:
            from_date = parse_date(from_text)
            if from_date is None:
                raise ValidationError({'from': 'Use YYYY-MM-DD.'})
            rows = rows.filter(match__played_on__gte=from_date)
        if to_text:
            to_date = parse_date(to_text)
            if to_date is None:
                raise ValidationError({'to': 'Use YYYY-MM-DD.'})
            rows = rows.filter(match__played_on__lte=to_date)
        if from_text and to_text and from_date > to_date:
            raise ValidationError({'to': 'End date must not precede start date.'})

        selected_range = request.query_params.get('range')
        selected_limit = None
        if selected_range is not None:
            selected_range = selected_range.lower()
            if selected_range not in ('last5', 'last10', 'all'):
                raise ValidationError({'range': 'Use last5, last10, or all.'})
            selected_limit = {'last5': 5, 'last10': 10}.get(selected_range)
        elif 'limit' in request.query_params:
            try:
                selected_limit = int(request.query_params['limit'])
            except (TypeError, ValueError) as exc:
                raise ValidationError({'limit': 'Use a whole number.'}) from exc
            if not 1 <= selected_limit <= self._MAX_ROWS:
                raise ValidationError({
                    'limit': f'Choose a value from 1 to {self._MAX_ROWS}.'
                })

        # The summary uses the complete selected range. Only the history
        # payload is capped, so an "All" total is never silently truncated by
        # the response-size safeguard.
        summary_records = list(
            rows[:selected_limit] if selected_limit is not None else rows
        )
        records = summary_records[:self._MAX_ROWS]
        name = f'{player.first_name} {player.last_name}'.strip()
        return Response({
            'playerId': str(player.id),
            'playerName': name or player.email.split('@')[0],
            'range': selected_range or (
                f'last{selected_limit}' if selected_limit is not None else 'all'
            ),
            'summary': build_performance_summary(summary_records),
            'performances': PlayerMatchPerformanceSerializer(
                records, many=True, context={'request': request},
            ).data,
        })


class PlayerGrowthView(APIView):
    """Categorized historical growth for one authorized player."""

    def get(self, request, player_id):
        if not _may_read_match_statistics(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        player = get_object_or_404(
            User.objects.select_related('player_profile'),
            pk=player_id,
            role=Roles.PLAYER,
        )
        selected = resolve_growth_filter(request.query_params)
        category = selected['category']
        from_date = selected['from']
        to_date = selected['to']
        limit = selected['limit']

        def include(name):
            return category in ('all', name)

        assessment_rows = []
        development_rows = []
        if include('assessment'):
            snapshots = PlayerAssessmentSnapshot.objects.select_related(
                'player', 'assessed_by'
            ).filter(player=player)
            if from_date:
                snapshots = snapshots.filter(created_at__date__gte=from_date)
            if to_date:
                snapshots = snapshots.filter(created_at__date__lte=to_date)
            assessment_rows = limited(snapshots, limit)
            development = PlayerDevelopmentAssessment.objects.select_related(
                'player', 'assessed_by'
            ).filter(player=player)
            if from_date:
                development = development.filter(
                    created_at__date__gte=from_date
                )
            if to_date:
                development = development.filter(created_at__date__lte=to_date)
            development_rows = limited(development, limit)

        training_rows = []
        if include('training'):
            attendance = Attendance.objects.select_related(
                'session', 'recorded_by', 'player'
            ).filter(player=player, session__isnull=False)
            if from_date:
                attendance = attendance.filter(session__date__gte=from_date)
            if to_date:
                attendance = attendance.filter(session__date__lte=to_date)
            all_training = list(attendance.order_by('-session__date', '-id'))
            if limit is None:
                training_rows = all_training
            else:
                counts = {}
                for row in all_training:
                    focus = row.session.focus
                    counts.setdefault(focus, 0)
                    if counts[focus] < limit:
                        training_rows.append(row)
                        counts[focus] += 1

        match_base = PlayerMatchPerformance.objects.select_related(
            'player', 'match', 'match__club',
            'match__source_fixture__schedule',
            'match__source_fixture__age_bracket',
        ).filter(player=player)
        if from_date:
            match_base = match_base.filter(match__played_on__gte=from_date)
        if to_date:
            match_base = match_base.filter(match__played_on__lte=to_date)

        regular_rows = []
        if include('regular_match'):
            regular_rows = limited(
                match_base.exclude(match__category=MatchCategory.TOURNAMENT),
                limit,
            )
        tournament_rows = []
        if include('tournament'):
            tournament_rows = limited(
                match_base.filter(
                    match__category=MatchCategory.TOURNAMENT,
                    match__source_fixture__isnull=False,
                ),
                limit,
            )

        assessment_data = {
            'summary': build_assessment_growth(assessment_rows),
            'history': PlayerAssessmentSnapshotSerializer(
                assessment_rows, many=True
            ).data,
            'framework': framework_for(
                player.player_profile.age_tier,
                player.player_profile.position,
            ),
            'developmentSummary': build_development_assessment_growth(
                development_rows
            ),
            'developmentHistory': PlayerDevelopmentAssessmentSerializer(
                development_rows, many=True
            ).data,
        } if include('assessment') else None

        training_groups = build_training_groups(training_rows)
        if include('training'):
            for group in training_groups:
                rows = [
                    row for row in training_rows
                    if row.session.focus == group['focus']
                ]
                group['history'] = AttendanceSerializer(rows, many=True).data

        regular_data = {
            **build_match_growth(regular_rows),
            'history': PlayerMatchPerformanceSerializer(
                regular_rows, many=True, context={'request': request}
            ).data,
        } if include('regular_match') else None

        tournament_groups = build_tournament_groups(tournament_rows)
        if include('tournament'):
            for group in tournament_groups:
                rows = [
                    row for row in tournament_rows
                    if str(row.match.source_fixture.schedule_id)
                    == group['tournamentId']
                    and (
                        str(row.match.source_fixture.age_bracket_id)
                        if row.match.source_fixture.age_bracket_id else None
                    ) == group['ageBracketId']
                ]
                group['growth'] = build_match_growth(rows)
                group['history'] = PlayerMatchPerformanceSerializer(
                    rows, many=True, context={'request': request}
                ).data

        name = f'{player.first_name} {player.last_name}'.strip()
        return Response({
            'playerId': str(player.id),
            'playerName': name or player.email.split('@')[0],
            'position': player.player_profile.position,
            'filter': {
                'range': selected['range'],
                'from': from_date.isoformat() if from_date else None,
                'to': to_date.isoformat() if to_date else None,
                'category': category,
            },
            'assessments': assessment_data,
            'training': {'groups': training_groups} if include('training') else None,
            'regularMatches': regular_data,
            'tournaments': {'groups': tournament_groups}
            if include('tournament') else None,
        })


class SquadProgressView(APIView):
    """GET /api/progress/squad/ — per-player attendance and effort aggregates
    for the requester's club: the data behind the coach's Progress tab.

    Coach sees only their own club; Super Admin sees every club. One aggregate
    query, not one per player.
    """

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied(
                'Only Coaches and the Super Admin can view squad progress.'
            )

        profiles = PlayerProfile.objects.select_related('user')
        attendance = Attendance.objects.all()
        if request.user.role == Roles.COACH:
            if request.user.club_id is None:
                profiles = profiles.none()
                attendance = attendance.none()
            else:
                profiles = profiles.filter(
                    user__club_id=request.user.club_id
                )
                attendance = attendance.filter(
                    player__club_id=request.user.club_id
                )
        profiles = profiles.order_by('user__first_name', 'user__last_name')
        stats = {
            row['player_id']: row
            for row in attendance.values('player_id').annotate(
                present=Count('id', filter=Q(status=AttendanceStatus.PRESENT)),
                absent=Count('id', filter=Q(status=AttendanceStatus.ABSENT)),
                excused=Count('id', filter=Q(status=AttendanceStatus.EXCUSED)),
                avg_effort=Avg('effort'),
            )
        }

        def row(profile):
            s = stats.get(profile.user_id, {})
            avg_effort = s.get('avg_effort')
            return {
                'id': str(profile.user_id),
                'name': (
                    f'{profile.user.first_name} {profile.user.last_name}'.strip()
                    or profile.user.email.split('@')[0]
                    or f'Player {profile.user_id}'
                ),
                'position': profile.position,
                'ageTier': profile.age_tier,
                'present': s.get('present', 0),
                'absent': s.get('absent', 0),
                'excused': s.get('excused', 0),
                'avgEffort': (
                    round(avg_effort) if avg_effort is not None else None
                ),
            }

        return Response([row(p) for p in profiles])


class TrainingSessionDetailView(APIView):
    """PUT/DELETE /api/training-sessions/<pk>/ — a coach edits or cancels a
    scheduled session. Club-scoped like creation: any coach in the owning
    club may manage it (there is no per-coach ownership anywhere else in the
    schema either). Cancelled sessions notify the same recipients as
    scheduling; attendance rows survive a cancellation (FK is SET_NULL), so
    recorded history is never destroyed."""

    def _session_for(self, request, pk):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can manage sessions.')
        session = get_object_or_404(TrainingSession, pk=pk)
        if not _session_in_user_scope(request.user, session):
            raise PermissionDenied('That session is not in your club.')
        return session

    def put(self, request, pk):
        with transaction.atomic():
            session = self._session_for(request, pk)
            session = TrainingSession.objects.select_for_update().get(pk=session.pk)
            if session.status != TrainingSessionStatus.SCHEDULED:
                raise WorkflowConflict(
                    'SESSION_LOCKED',
                    'Only scheduled training sessions can be changed.',
                )
            serializer = TrainingSessionSerializer(
                session, data=request.data, partial=True
            )
            serializer.is_valid(raise_exception=True)
            values = serializer.validated_data
            draft = TrainingSession(
                title=values.get('title', session.title),
                date=values.get('date', session.date),
                start_time=values.get('start_time', session.start_time),
                end_time=values.get('end_time', session.end_time),
                location=values.get('location', session.location),
                focus=values.get('focus', session.focus),
                age_tiers=values.get('age_tiers', session.age_tiers),
            )
            session_start, session_end = draft.interval()
            fixture = conflicting_fixture_for_training(
                club_id=request.user.club_id,
                tiers=draft.age_tiers,
                start=session_start,
                end=session_end,
            )
            if fixture is not None:
                conflict = fixture_conflict_payload(fixture)
                raise WorkflowConflict(
                    'TOURNAMENT_SCHEDULE_CONFLICT',
                    conflict['message'],
                    conflict=conflict,
                )
            session = serializer.save()
            AuditLog.record(
                request.user, 'session.updated',
                target=session.title, detail=str(session.date),
            )
            transaction.on_commit(lambda: notify_session_updated(session))
        return Response(TrainingSessionSerializer(session).data)

    def delete(self, request, pk):
        with transaction.atomic():
            scoped = self._session_for(request, pk)
            session = TrainingSession.objects.select_for_update().get(pk=scoped.pk)
            if session.status != TrainingSessionStatus.SCHEDULED:
                raise WorkflowConflict(
                    'SESSION_LOCKED',
                    'Only scheduled training sessions can be cancelled.',
                )
            session_start, _session_end = session.interval()
            if (
                session_start is not None
                and session_start <= timezone.now()
            ) or (
                session_start is None
                and session.date < timezone.localdate()
            ):
                raise WorkflowConflict(
                    'SESSION_ALREADY_STARTED',
                    'Past or currently running training cannot be cancelled.',
                )
            recipient_ids = _recipients_for_session(session)
            session.status = TrainingSessionStatus.CANCELLED
            session.cancellation_reason = 'Cancelled by the Coach.'
            session.cancelled_at = timezone.now()
            session.cancelled_by_action = 'coach.cancelled'
            session.save(update_fields=[
                'status', 'cancellation_reason', 'cancelled_at',
                'cancelled_by_action',
            ])
            AuditLog.record(
                request.user, 'session.cancelled',
                target=session.title, detail=str(session.date),
            )
            transaction.on_commit(
                lambda: notify_session_cancelled(
                    session,
                    user_ids=recipient_ids,
                    session_id=session.id,
                )
            )
        return Response(status=status.HTTP_204_NO_CONTENT)


class SessionConfirmationView(APIView):
    """GET/POST /api/session-confirmations/ — a player's RSVPs for sessions.

    GET ?player=<id>: that player's confirmations, most recent first. Same
    object-level authz as attendance — a guardian only reads a linked player, a
    player only themselves, coach/admin anyone (audit finding F3).

    POST {sessionId, status}: the signed-in player RSVPs. The player is taken
    from the request, never the client, and the row is upserted on
    (player, session) so re-confirming flips the same row rather than stacking.
    """

    def get(self, request):
        player_id = request.query_params.get('player')
        if not player_id:
            raise ValidationError('A player query parameter is required.')
        if not _guardian_may_read(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        records = SessionConfirmation.objects.select_related('session').filter(
            player_id=player_id
        )
        return Response(SessionConfirmationSerializer(records, many=True).data)

    def post(self, request):
        if request.user.role != Roles.PLAYER:
            raise PermissionDenied('Only players can confirm their own sessions.')
        session_id = request.data.get('sessionId')
        status_value = str(request.data.get('status', '')).upper()
        if not session_id:
            raise ValidationError('A sessionId is required.')
        if status_value not in set(ConfirmationStatus.values):
            raise ValidationError(f'Unknown status: {status_value or "(none)"}.')
        session = get_object_or_404(TrainingSession, pk=session_id)
        # Tenancy: a player may only RSVP to sessions in their own club.
        if not _session_in_user_scope(request.user, session):
            raise PermissionDenied('That session is not in your club.')
        if session.date > timezone.localdate():
            raise ValidationError(
                'Players can only confirm a session on its scheduled day.'
            )
        confirmation, _ = SessionConfirmation.objects.update_or_create(
            player=request.user,
            session=session,
            defaults={'status': status_value},
        )
        return Response(
            SessionConfirmationSerializer(confirmation).data,
            status=status.HTTP_201_CREATED,
        )


def _dispute_in_user_scope(user, dispute):
    """True if `user` may act on `dispute` under club tenancy.

    Admin sees every club; coach/staff only disputes raised within their own
    club (a dispute's club is its raiser's club).
    """
    if user.role == Roles.ADMIN:
        return True
    return (
        user.club_id is not None
        and dispute.raised_by_id is not None
        and dispute.raised_by.club_id == user.club_id
    )


class DisputeListCreateView(APIView):
    """GET/POST /api/disputes/.

    GET: disputes visible to the caller (own club for coach/staff, all for
    Admin). POST: coach only — the coach flags, staff/admin respond via the
    thread endpoint.
    """

    def get(self, request):
        if request.user.role not in DISPUTE_ROLES:
            raise PermissionDenied('You may not view disputes.')
        disputes = Dispute.objects.select_related(
            'raised_by', 'subject_player'
        ).prefetch_related('responses__author')
        # Tenancy: coach/staff see only their own club's disputes; Admin all.
        if request.user.role != Roles.ADMIN:
            if request.user.club_id is None:
                disputes = disputes.none()
            else:
                disputes = disputes.filter(
                    raised_by__club_id=request.user.club_id
                )
        return Response(DisputeSerializer(disputes, many=True).data)

    def post(self, request):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can raise disputes.')
        if request.user.club_id is None:
            raise PermissionDenied('Coach account must belong to a club.')
        serializer = DisputeCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        # Tenancy: the subject player, if any, must be in the coach's own club.
        subject_id = data.get('subjectPlayerId')
        if subject_id is not None and not User.objects.filter(
            pk=subject_id, club_id=request.user.club_id
        ).exists():
            raise PermissionDenied('That player is not in your club.')
        dispute = Dispute.objects.create(
            raised_by=request.user,
            subject_player_id=data.get('subjectPlayerId'),
            category=data['category'],
            summary=data['summary'],
            detail=data.get('detail') or '',
        )
        return Response(
            DisputeSerializer(dispute).data, status=status.HTTP_201_CREATED
        )


class DisputeDetailView(APIView):
    """GET /api/disputes/<pk>/ — one dispute with its full thread."""

    def get(self, request, pk):
        if request.user.role not in DISPUTE_ROLES:
            raise PermissionDenied('You may not view disputes.')
        dispute = get_object_or_404(
            Dispute.objects.select_related('raised_by', 'subject_player')
            .prefetch_related('responses__author'),
            pk=pk,
        )
        if not _dispute_in_user_scope(request.user, dispute):
            raise PermissionDenied('You may not view this dispute.')
        return Response(DisputeSerializer(dispute).data)


class DisputeResponseCreateView(APIView):
    """POST /api/disputes/<pk>/responses/ — append to the thread.

    Append-only by design: no update/delete endpoints exist, so the thread is
    the dispute's audit trail. A response may carry a status change, applied
    to the parent atomically with the entry that documents it.
    """

    def post(self, request, pk):
        if request.user.role not in DISPUTE_ROLES:
            raise PermissionDenied('You may not respond to disputes.')
        dispute = get_object_or_404(
            Dispute.objects.select_related('raised_by'), pk=pk
        )
        if not _dispute_in_user_scope(request.user, dispute):
            raise PermissionDenied('You may not respond to this dispute.')
        serializer = DisputeResponseCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        new_status = data.get('statusChangeTo')
        with transaction.atomic():
            DisputeResponse.objects.create(
                dispute=dispute,
                author=request.user,
                body=data['body'],
                status_change_to=new_status,
            )
            if new_status:
                dispute.status = new_status
            dispute.save()  # bumps updated_at even without a status change
        return Response(
            DisputeSerializer(dispute).data, status=status.HTTP_201_CREATED
        )


class EligibilityHistoryView(APIView):
    """GET /api/players/<id>/eligibility-history/ — a player's academic
    eligibility transitions, newest first.

    Object-scoped (audit finding F3): the player themselves, their linked
    guardian(s), School Staff, and Admin may read; nobody else — notably not
    the coach, since academic eligibility is not the coach's domain. The
    serializer hides the acting staff member's identity from families.
    """

    def get(self, request, player_id):
        if not _may_read_eligibility(request.user, player_id):
            # Authorized reviewers (Admin / School Staff) who named a player
            # that does not exist get a 404; a real player in another club still
            # falls through to the 403 below (multi-tenant scope). Families and
            # coaches get 403 without revealing whether the id exists.
            if request.user.role in (Roles.ADMIN, Roles.SCHOOL_STAFF):
                get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
            raise PermissionDenied(
                'You may not view this player\'s eligibility history.'
            )
        player = get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
        _require_unlock_when_pin_exists(request, player_id)
        if player.club_id is not None and not player.club.allows_academic_eligibility:
            return Response({'applicable': False, 'results': []})
        history = EligibilityHistory.objects.filter(
            player_id=player_id
        ).select_related('changed_by')
        return Response(
            EligibilityHistorySerializer(
                history, many=True, context={'request': request},
            ).data
        )


def _injury_records():
    return (
        InjuryRecord.objects.select_related(
            'player', 'reported_by', 'reviewed_by',
        )
        .prefetch_related(
            'status_update_requests__submitted_by',
            'status_update_requests__reviewed_by',
        )
    )


def _same_club_injury_coordinator(user, injury):
    return (
        user.role == Roles.COORDINATOR
        and user.club_id is not None
        and user.club_id == injury.player.club_id
    )


def _care_team_may_view(user, injury):
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.PLAYER:
        return user.id == injury.player_id
    if user.role in (Roles.COACH, Roles.COORDINATOR):
        return (
            user.club_id is not None
            and user.club_id == injury.player.club_id
        )
    if user.role == Roles.GUARDIAN:
        return GuardianLink.objects.filter(
            guardian=user,
            player_id=injury.player_id,
        ).exists()
    return False


def _injury_player_for_report(request):
    user = request.user
    if user.role == Roles.PLAYER:
        return user
    player_id = request.data.get('playerId')
    if not player_id:
        raise ValidationError({'playerId': 'Choose the injured player.'})
    player = get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
    if user.role == Roles.GUARDIAN:
        if not GuardianLink.objects.filter(
            guardian=user, player=player,
        ).exists():
            raise PermissionDenied('You may not report for this player.')
        _require_unlock_when_pin_exists(request, player.id)
        return player
    if user.role in (Roles.COACH, Roles.COORDINATOR):
        if (
            user.club_id is None
            or user.club_id != player.club_id
        ):
            raise PermissionDenied('You may not report for this player.')
        return player
    raise PermissionDenied('Your role cannot submit injury reports.')


def _scoped_injury_records(request):
    user = request.user
    records = _injury_records()
    player_id = request.query_params.get('player')
    if user.role == Roles.ADMIN:
        pass
    elif user.role == Roles.PLAYER:
        records = records.filter(player=user)
    elif user.role in (Roles.COACH, Roles.COORDINATOR):
        if user.club_id is None:
            records = records.none()
        else:
            records = records.filter(player__club_id=user.club_id)
    elif user.role == Roles.GUARDIAN:
        if not player_id or not GuardianLink.objects.filter(
            guardian=user, player_id=player_id,
        ).exists():
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        records = records.filter(player_id=player_id)
    else:
        raise PermissionDenied('You may not view injury records.')

    if player_id and user.role != Roles.GUARDIAN:
        records = records.filter(player_id=player_id)
    if user.role not in (Roles.ADMIN, Roles.COORDINATOR):
        records = records.filter(
            ~Q(review_status=InjuryReportStatus.REJECTED)
            | Q(reported_by=user)
        )
    include_archived = (
        request.query_params.get('includeArchived', '').lower() == 'true'
    )
    if not include_archived or user.role not in (Roles.ADMIN, Roles.COORDINATOR):
        records = records.exclude(review_status=InjuryReportStatus.ARCHIVED)
    return records


def _workflow_injury(request, pk):
    injury = get_object_or_404(_injury_records(), pk=pk)
    if not _care_team_may_view(request.user, injury):
        raise PermissionDenied('You may not access this injury report.')
    if (
        injury.review_status == InjuryReportStatus.REJECTED
        and request.user.role not in (Roles.ADMIN, Roles.COORDINATOR)
        and injury.reported_by_id != request.user.id
    ):
        raise PermissionDenied('You may not access this injury report.')
    if request.user.role == Roles.GUARDIAN:
        _require_unlock_when_pin_exists(request, injury.player_id)
    return injury


class InjuryWorkflowListCreateView(APIView):
    """List private care-team reports or submit one for confirmation."""

    def get(self, request):
        records = _scoped_injury_records(request)
        return Response(InjuryRecordSerializer(
            records,
            many=True,
            context={'request': request},
        ).data)

    def post(self, request):
        player = _injury_player_for_report(request)
        data = request.data.copy()
        data['status'] = InjuryStatus.ACTIVE
        data['resolvedOn'] = None
        serializer = InjuryRecordSerializer(
            data=data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        record = serializer.save(
            player=player,
            reported_by=request.user,
            review_status=InjuryReportStatus.PENDING,
        )
        AuditLog.record(
            request.user,
            'injury.reported',
            target=f'{player.id}:{record.id}',
        )
        return Response(
            InjuryRecordSerializer(
                record, context={'request': request},
            ).data,
            status=status.HTTP_201_CREATED,
        )


class InjuryReportablePlayersView(APIView):
    """Minimal same-club player selector for care-team injury reporting."""

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.COORDINATOR):
            raise PermissionDenied('Your role cannot list club players here.')
        if request.user.club_id is None:
            return Response([])
        profiles = PlayerProfile.objects.select_related('user').filter(
            user__club_id=request.user.club_id,
            user__role=Roles.PLAYER,
            user__is_active=True,
        ).order_by('user__last_name', 'user__first_name', 'user__id')
        return Response(PlayerSelectorSerializer(profiles, many=True).data)


class InjuryWorkflowDetailView(APIView):
    """Read a report; Pending reporter/Coordinator or confirmed Coordinator edit."""

    def get(self, request, pk):
        record = _workflow_injury(request, pk)
        return Response(InjuryRecordSerializer(
            record, context={'request': request},
        ).data)

    def put(self, request, pk):
        record = _workflow_injury(request, pk)
        coordinator = _same_club_injury_coordinator(request.user, record)
        pending_editor = (
            record.review_status == InjuryReportStatus.PENDING
            and (
                record.reported_by_id == request.user.id
                or coordinator
            )
        )
        confirmed_editor = (
            record.review_status == InjuryReportStatus.CONFIRMED
            and coordinator
        )
        if not (pending_editor or confirmed_editor):
            raise PermissionDenied('This injury report cannot be edited.')
        data = request.data.copy()
        if pending_editor:
            data['status'] = InjuryStatus.ACTIVE
            data['resolvedOn'] = None
        serializer = InjuryRecordSerializer(
            record,
            data=data,
            partial=True,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        record = serializer.save()
        AuditLog.record(
            request.user,
            'injury.updated',
            target=f'{record.player_id}:{record.id}',
        )
        return Response(InjuryRecordSerializer(
            record, context={'request': request},
        ).data)

    def delete(self, request, pk):
        record = _workflow_injury(request, pk)
        coordinator = _same_club_injury_coordinator(request.user, record)
        if not (
            record.review_status == InjuryReportStatus.PENDING
            and (
                record.reported_by_id == request.user.id
                or coordinator
            )
        ):
            raise PermissionDenied('Only a Pending report can be withdrawn.')
        target = f'{record.player_id}:{record.id}'
        record.delete()
        AuditLog.record(request.user, 'injury.withdrawn', target=target)
        return Response(status=status.HTTP_204_NO_CONTENT)


class InjuryReviewView(APIView):
    """Coordinator confirms or rejects a Pending injury report."""

    def post(self, request, pk):
        with transaction.atomic():
            record = get_object_or_404(
                _injury_records().select_for_update(), pk=pk,
            )
            if not _same_club_injury_coordinator(request.user, record):
                raise PermissionDenied('Only the club Coordinator can review this report.')
            if record.review_status != InjuryReportStatus.PENDING:
                raise ValidationError('Only a Pending report can be reviewed.')
            action = str(request.data.get('action', '')).upper()
            reason = str(request.data.get('rejectionReason', '')).strip()
            if action == 'CONFIRM':
                record.review_status = InjuryReportStatus.CONFIRMED
                record.rejection_reason = ''
                audit_action = 'injury.confirmed'
            elif action == 'REJECT':
                if not reason:
                    raise ValidationError({
                        'rejectionReason': 'Explain why the report was rejected.'
                    })
                record.review_status = InjuryReportStatus.REJECTED
                record.rejection_reason = reason
                audit_action = 'injury.rejected'
            else:
                raise ValidationError({'action': 'Choose CONFIRM or REJECT.'})
            record.reviewed_by = request.user
            record.reviewed_at = timezone.now()
            record.save(update_fields=[
                'review_status', 'rejection_reason', 'reviewed_by',
                'reviewed_at', 'updated_at',
            ])
        AuditLog.record(
            request.user,
            audit_action,
            target=f'{record.player_id}:{record.id}',
            detail=reason,
        )
        return Response(InjuryRecordSerializer(
            record, context={'request': request},
        ).data)


class InjuryArchiveView(APIView):
    def post(self, request, pk):
        record = _workflow_injury(request, pk)
        if not _same_club_injury_coordinator(request.user, record):
            raise PermissionDenied('Only the club Coordinator can archive reports.')
        if record.review_status != InjuryReportStatus.CONFIRMED:
            raise ValidationError('Only a Confirmed report can be archived.')
        if record.status != InjuryStatus.RECOVERED:
            raise ValidationError(
                'Only a Recovered injury report can be archived.'
            )
        record.review_status = InjuryReportStatus.ARCHIVED
        record.archived_at = timezone.now()
        record.save(update_fields=['review_status', 'archived_at', 'updated_at'])
        AuditLog.record(
            request.user,
            'injury.archived',
            target=f'{record.player_id}:{record.id}',
        )
        return Response(InjuryRecordSerializer(
            record, context={'request': request},
        ).data)


class InjuryStatusUpdateListCreateView(APIView):
    """Care team requests a recovery-state change for a Confirmed injury."""

    def post(self, request, pk):
        with transaction.atomic():
            record = get_object_or_404(
                _injury_records().select_for_update(), pk=pk,
            )
            if not _care_team_may_view(request.user, record):
                raise PermissionDenied('You may not update this injury.')
            if request.user.role not in (
                Roles.PLAYER, Roles.GUARDIAN, Roles.COACH,
            ):
                raise PermissionDenied(
                    'Players, Guardians, and Coaches submit recovery updates.'
                )
            if request.user.role == Roles.GUARDIAN:
                _require_unlock_when_pin_exists(request, record.player_id)
            if record.review_status != InjuryReportStatus.CONFIRMED:
                raise ValidationError(
                    'Recovery updates require a Confirmed injury report.'
                )
            if record.status == InjuryStatus.RECOVERED:
                raise ValidationError('This injury is already Recovered.')
            if record.status_update_requests.filter(
                review_status=InjuryUpdateReviewStatus.PENDING,
            ).exists():
                raise ValidationError(
                    'A recovery update is already awaiting Coordinator review.'
                )
            serializer = InjuryStatusUpdateRequestSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            proposed_resolved = serializer.validated_data.get(
                'proposed_resolved_on'
            )
            if proposed_resolved and proposed_resolved < record.occurred_on:
                raise ValidationError({
                    'proposedResolvedOn': (
                        'The recovery date cannot precede the injury.'
                    )
                })
            update_request = serializer.save(
                injury=record,
                submitted_by=request.user,
            )
        AuditLog.record(
            request.user,
            'injury.status_requested',
            target=f'{record.id}:{update_request.id}',
            detail=update_request.proposed_status,
        )
        return Response(
            InjuryStatusUpdateRequestSerializer(update_request).data,
            status=status.HTTP_201_CREATED,
        )


class InjuryStatusUpdateReviewView(APIView):
    """Coordinator approves or rejects one Pending recovery update."""

    def post(self, request, pk, update_id):
        with transaction.atomic():
            update_request = get_object_or_404(
                InjuryStatusUpdateRequest.objects.select_for_update()
                .select_related('injury__player', 'submitted_by'),
                pk=update_id,
                injury_id=pk,
            )
            record = update_request.injury
            if not _same_club_injury_coordinator(request.user, record):
                raise PermissionDenied('Only the club Coordinator can review updates.')
            if update_request.review_status != InjuryUpdateReviewStatus.PENDING:
                raise ValidationError('This recovery update is no longer Pending.')
            action = str(request.data.get('action', '')).upper()
            reason = str(request.data.get('rejectionReason', '')).strip()
            if action == 'APPROVE':
                update_request.review_status = InjuryUpdateReviewStatus.APPROVED
                update_request.rejection_reason = ''
                record.status = update_request.proposed_status
                record.resolved_on = update_request.proposed_resolved_on
                record.save(update_fields=['status', 'resolved_on', 'updated_at'])
                audit_action = 'injury.status_approved'
            elif action == 'REJECT':
                if not reason:
                    raise ValidationError({
                        'rejectionReason': 'Explain why the update was rejected.'
                    })
                update_request.review_status = InjuryUpdateReviewStatus.REJECTED
                update_request.rejection_reason = reason
                audit_action = 'injury.status_rejected'
            else:
                raise ValidationError({'action': 'Choose APPROVE or REJECT.'})
            update_request.reviewed_by = request.user
            update_request.reviewed_at = timezone.now()
            update_request.save(update_fields=[
                'review_status', 'rejection_reason', 'reviewed_by',
                'reviewed_at', 'updated_at',
            ])
        AuditLog.record(
            request.user,
            audit_action,
            target=f'{record.id}:{update_request.id}',
            detail=reason or update_request.proposed_status,
        )
        return Response(InjuryRecordSerializer(
            _injury_records().get(pk=record.pk),
            context={'request': request},
        ).data)


class DeviceRegisterView(APIView):
    """POST /api/devices/ {token, platform} — register/refresh an FCM token for
    the signed-in user. Idempotent (upsert by token)."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        token = (request.data.get('token') or '').strip()
        if not token:
            raise ValidationError('A device token is required.')
        DeviceToken.objects.update_or_create(
            token=token,
            defaults={
                'user': request.user,
                'platform': (request.data.get('platform') or '').strip(),
            },
        )
        return Response(status=status.HTTP_204_NO_CONTENT)

    def delete(self, request):
        """Forget this account's association with one device token."""
        token = (request.data.get('token') or '').strip()
        if not token:
            raise ValidationError('A device token is required.')
        DeviceToken.objects.filter(user=request.user, token=token).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class NotificationListView(APIView):
    """GET the authenticated user's newest persistent inbox entries."""

    def get(self, request):
        records = NotificationRecord.objects.filter(user=request.user)[:100]
        return Response(NotificationRecordSerializer(records, many=True).data)


class NotificationUnreadCountView(APIView):
    def get(self, request):
        count = NotificationRecord.objects.filter(
            user=request.user, read_at__isnull=True,
        ).count()
        return Response({'count': count})


class NotificationReadView(APIView):
    def patch(self, request, pk):
        record = get_object_or_404(
            NotificationRecord, pk=pk, user=request.user,
        )
        if record.read_at is None:
            record.read_at = timezone.now()
            record.save(update_fields=['read_at'])
        return Response(NotificationRecordSerializer(record).data)


class NotificationReadAllView(APIView):
    def post(self, request):
        updated = NotificationRecord.objects.filter(
            user=request.user, read_at__isnull=True,
        ).update(read_at=timezone.now())
        return Response({'updated': updated})


class PlayerPhotoUploadView(APIView):
    """Upload a player photo as self, Super Admin, or a same-Club Coach."""

    permission_classes = [IsAuthenticated]

    def post(self, request, player_id):
        profile = get_object_or_404(
            PlayerProfile.objects.select_related('user'), user_id=player_id,
        )
        if request.user.role == Roles.PLAYER:
            if request.user.pk != player_id:
                raise PermissionDenied('Players can update only their own photo.')
        elif request.user.role == Roles.COACH:
            if (
                request.user.club_id is None
                or profile.user.club_id != request.user.club_id
            ):
                raise PermissionDenied('That player is not in your club.')
        elif request.user.role != Roles.ADMIN:
            raise PermissionDenied(
                'Only the Player, a same-Club Coach, or the Super Admin can '
                'upload photos.'
            )
        upload = request.FILES.get('photo')
        if upload is None:
            raise ValidationError('A photo file is required (field "photo").')
        try:
            content_type = validate_photo_upload(upload)
            path = upload_photo(
                player_id,
                upload.read(),
                content_type=content_type,
            )
        except (RuntimeError, ValueError) as exc:
            raise ValidationError(str(exc))
        previous_path = profile.photo_path
        profile.photo_path = path
        profile.save(update_fields=['photo_path'])
        invalidate_signed_photo_url(previous_path)
        invalidate_signed_photo_url(path)
        if previous_path and previous_path != path:
            delete_photo(previous_path)
        AuditLog.record(
            request.user,
            'player.photo_updated',
            target=profile.user.email,
        )
        return Response(PlayerSerializer(profile).data)


class AgeTierSettingsView(APIView):
    """GET/PUT /api/age-tiers/ — the Admin-configurable age band per tier.

    Reads are open to every signed-in role (the bands are academy-wide facts,
    not sensitive). Writes are Admin-only and touch boundaries, never the set
    of tiers: the three tier names are a wire contract with the client.
    Changing a band only affects how FUTURE players are placed — existing
    players keep their stored tier (see PlayerProfile).
    """

    def get(self, request):
        return Response(
            AgeTierSettingSerializer(
                AgeTierSetting.objects.order_by('min_age'), many=True
            ).data
        )

    def put(self, request):
        if request.user.role != Roles.ADMIN:
            raise PermissionDenied('Only an Admin can configure age tiers.')
        serializer = AgeTierSettingSerializer(data=request.data, many=True)
        serializer.is_valid(raise_exception=True)
        bands = serializer.validated_data

        # Overlapping bands would make tier_for_age order-dependent — reject
        # them here rather than silently picking whichever band sorts first.
        by_min = sorted(bands, key=lambda b: b['min_age'])
        for prev, nxt in zip(by_min, by_min[1:]):
            if nxt['min_age'] <= prev['max_age']:
                raise ValidationError('Tier age ranges may not overlap.')

        with transaction.atomic():
            for band in bands:
                updated = AgeTierSetting.objects.filter(
                    tier=band['tier']
                ).update(min_age=band['min_age'], max_age=band['max_age'])
                if not updated:
                    raise ValidationError(f'Unknown tier: {band["tier"]}')
        return self.get(request)


class AdminCreatePlayerView(APIView):
    """POST /api/admin/players/ — the console's dedicated Add Player flow.

    Unlike the generic /api/admin/users/ endpoint, this creates the User AND
    its PlayerProfile (with the required identity fields) in one atomic call,
    and optionally links a guardian in the same step — this is now the only
    way a player account comes into existence (the admin-site "Player
    profiles" screen is hidden; see academy/admin.py).
    """

    permission_classes = [IsAdmin]

    def post(self, request):
        serializer = AdminCreatePlayerSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        guardian = data['guardian_id']
        if not guardian.is_active:
            raise ValidationError('The selected guardian must be active.')

        try:
            user, profile, temp_password, note = provision_player(
                email=data.get('email', ''),
                first_name=data['first_name'],
                last_name=data['last_name'],
                middle_initial=data['middle_initial'],
                date_of_birth=data['date_of_birth'],
                club=guardian.club,
                guardian=guardian,
            )
        except ProvisioningError as exc:
            raise ValidationError(str(exc))
        AuditLog.record(
            request.user, 'account.created',
            target=user.email or user.get_full_name() or user.username,
            detail='PLAYER',
        )

        return Response(
            {
                'user': UserSerializer(user).data,
                'player': PlayerSerializer(profile).data,
                'temporary_password': temp_password,
                'note': note,
            },
            status=status.HTTP_201_CREATED,
        )
