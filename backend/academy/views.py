"""Academy REST endpoints.

Authentication is the project-wide FirebaseAuthentication (settings.py).
Authorization is enforced two ways, both server-side (never trust the client):
  - endpoint-level RBAC via accounts.permissions.role_required(...);
  - object-level scoping in each queryset/handler (a guardian only ever reaches
    a player they are linked to — audit finding F3).
"""
from django.db import transaction
from django.db.models import Avg, Count, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, ValidationError
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

from .models import (
    AgeTierSetting,
    Attendance,
    AttendanceStatus,
    AuditLog,
    ConfirmationStatus,
    DeviceToken,
    Dispute,
    DisputeResponse,
    EligibilityHistory,
    FootballMatch,
    InjuryRecord,
    NotificationRecord,
    PlayerMatchPerformance,
    PlayerProfile,
    PlayerPrivacyPin,
    SessionConfirmation,
    TrainingSession,
)
from .notifications import (
    _recipients_for_session,
    notify_assessment_saved,
    notify_session_cancelled,
    notify_session_scheduled,
    notify_session_updated,
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
    AttendanceSerializer,
    DisputeCreateSerializer,
    DisputeResponseCreateSerializer,
    DisputeSerializer,
    EligibilityHistorySerializer,
    FootballMatchSerializer,
    InjuryRecordSerializer,
    NotificationRecordSerializer,
    PlayerMatchPerformanceSerializer,
    PlayerMatchPerformanceWriteSerializer,
    PlayerPositionSerializer,
    PlayerSerializer,
    PlayerSelectorSerializer,
    SessionAttendanceRecordSerializer,
    SessionConfirmationSerializer,
    TrainingSessionSerializer,
)
from .match_statistics import build_performance_summary
from .player_unlock import issue_player_unlock, require_player_unlock
from .storage import (
    delete_photo,
    invalidate_signed_photo_url,
    upload_photo,
    validate_photo_upload,
)

# Roles that participate in the dispute process: the coach flags, School
# Staff and Admin review/respond. Players and guardians have no access.
DISPUTE_ROLES = (Roles.COACH, Roles.SCHOOL_STAFF, Roles.ADMIN)


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
    qs = FootballMatch.objects.select_related('club', 'created_by')
    if user.role == Roles.ADMIN:
        return qs
    if user.club_id is None:
        return qs.none()
    return qs.filter(club_id=user.club_id)


def _coach_match(request, match_id):
    """Return a coach-owned match, failing closed across tenant boundaries."""
    if request.user.role != Roles.COACH:
        raise PermissionDenied('Only coaches can manage match data.')
    if request.user.club_id is None:
        raise PermissionDenied('Coach account must belong to a club.')
    return get_object_or_404(
        FootballMatch.objects.select_related('club'),
        pk=match_id,
        club_id=request.user.club_id,
    )


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
        serializer = AssessmentSerializer(profile, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        AuditLog.record(
            request.user, 'assessment.saved', target=profile.user.email
        )
        # Notify the player + guardians only after the ratings are durably
        # committed (same pattern as session scheduling).
        transaction.on_commit(lambda: notify_assessment_saved(profile))
        return Response(PlayerSerializer(profile).data)


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
                        'note': record.get('note') or '',
                        'recorded_by': request.user,
                    },
                )
                kept_player_ids.append(record['playerId'])
            Attendance.objects.filter(session=session).exclude(
                player_id__in=kept_player_ids
            ).delete()
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


class FootballMatchListCreateView(APIView):
    """List completed matches or let a coach create one for their own club."""

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view club match records.')
        return Response(
            FootballMatchSerializer(_matches_for(request.user), many=True).data
        )

    def post(self, request):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can create match records.')
        if request.user.club_id is None:
            raise PermissionDenied('Coach account must belong to a club.')
        serializer = FootballMatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        match = serializer.save(
            club=request.user.club,
            created_by=request.user,
        )
        AuditLog.record(
            request.user,
            'match.created',
            target=str(match.pk),
            detail=f'{match.opponent} | {match.played_on}',
        )
        return Response(
            FootballMatchSerializer(match).data,
            status=status.HTTP_201_CREATED,
        )


class FootballMatchDetailView(APIView):
    """Read or correct match metadata without changing tenant ownership."""

    def get(self, request, match_id):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view club match records.')
        match = get_object_or_404(_matches_for(request.user), pk=match_id)
        return Response(FootballMatchSerializer(match).data)

    def put(self, request, match_id):
        match = _coach_match(request, match_id)
        serializer = FootballMatchSerializer(
            match, data=request.data, partial=True,
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
    """Coach/Admin read view for all recorded players in one match."""

    def get(self, request, match_id):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view match performances.')
        match = get_object_or_404(_matches_for(request.user), pk=match_id)
        rows = PlayerMatchPerformance.objects.select_related(
            'match', 'player', 'match__club',
        ).filter(match=match)
        return Response(PlayerMatchPerformanceSerializer(rows, many=True).data)


class MatchPerformanceDetailView(APIView):
    """Upsert or remove one club player's statistics for one match."""

    def put(self, request, match_id, player_id):
        match = _coach_match(request, match_id)
        player = get_object_or_404(
            User.objects.select_related('player_profile'),
            pk=player_id,
            role=Roles.PLAYER,
            club_id=request.user.club_id,
        )
        with transaction.atomic():
            # Lock the parent to serialize two submissions for the same match;
            # the unique DB constraint is the final duplicate-write guard.
            FootballMatch.objects.select_for_update().get(pk=match.pk)
            existing = PlayerMatchPerformance.objects.select_for_update().filter(
                match=match, player=player,
            ).first()
            serializer = PlayerMatchPerformanceWriteSerializer(
                existing, data=request.data,
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
            )
        AuditLog.record(
            request.user,
            'match.performance_saved',
            target=f'{match.pk}:{player.pk}',
        )
        return Response(
            PlayerMatchPerformanceSerializer(performance).data,
            status=status.HTTP_200_OK if existing else status.HTTP_201_CREATED,
        )

    def delete(self, request, match_id, player_id):
        match = _coach_match(request, match_id)
        performance = get_object_or_404(
            PlayerMatchPerformance,
            match=match,
            player_id=player_id,
        )
        performance.delete()
        AuditLog.record(
            request.user,
            'match.performance_deleted',
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

        try:
            limit = int(request.query_params.get('limit', self._MAX_ROWS))
        except (TypeError, ValueError) as exc:
            raise ValidationError({'limit': 'Use a whole number.'}) from exc
        if not 1 <= limit <= self._MAX_ROWS:
            raise ValidationError({
                'limit': f'Choose a value from 1 to {self._MAX_ROWS}.'
            })

        records = list(rows[:limit])
        name = f'{player.first_name} {player.last_name}'.strip()
        return Response({
            'playerId': str(player.id),
            'playerName': name or player.email.split('@')[0],
            'summary': build_performance_summary(records),
            'performances': PlayerMatchPerformanceSerializer(
                records, many=True,
            ).data,
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
        session = self._session_for(request, pk)
        serializer = TrainingSessionSerializer(
            session, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        session = serializer.save()
        AuditLog.record(
            request.user, 'session.updated',
            target=session.title, detail=str(session.date),
        )
        transaction.on_commit(lambda: notify_session_updated(session))
        return Response(TrainingSessionSerializer(session).data)

    def delete(self, request, pk):
        session = self._session_for(request, pk)
        # Snapshot recipients before deletion, but create/send the alert only
        # after deletion commits. A failed delete must never produce a false
        # cancellation notification.
        recipient_ids = _recipients_for_session(session)
        session_id = session.pk
        AuditLog.record(
            request.user, 'session.cancelled',
            target=session.title, detail=str(session.date),
        )
        session.delete()
        transaction.on_commit(
            lambda: notify_session_cancelled(
                session, recipient_ids, session_id=session_id,
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


class InjuryRecordListCreateView(APIView):
    """GET/POST /api/injuries/ — a player's injury history.

    Medical data gets least-privilege. Reads: a player sees their own records;
    a guardian sees a linked child's (read-only, ?player=<id> required); coach
    and admin see everyone (?player=<id> narrows). Writes: the player only —
    guardians and staff never create/edit/delete injuries.
    """

    def get(self, request):
        if request.user.role == Roles.PLAYER:
            records = InjuryRecord.objects.select_related('player').filter(
                player=request.user
            )
        elif request.user.role in (Roles.COACH, Roles.ADMIN):
            records = InjuryRecord.objects.select_related('player')
            # Coaches are club-scoped; Admin sees every club.
            if request.user.role == Roles.COACH:
                if request.user.club_id is None:
                    records = records.none()
                else:
                    records = records.filter(
                        player__club_id=request.user.club_id
                    )
            player_id = request.query_params.get('player')
            if player_id:
                records = records.filter(player_id=player_id)
        elif request.user.role == Roles.GUARDIAN:
            # A guardian may read only a child they are linked to, and must name
            # which one — never the whole table.
            player_id = request.query_params.get('player')
            if not player_id or not GuardianLink.objects.filter(
                guardian=request.user, player_id=player_id
            ).exists():
                raise PermissionDenied('You may not view this player.')
            _require_unlock_when_pin_exists(request, player_id)
            records = InjuryRecord.objects.select_related('player').filter(
                player_id=player_id
            )
        else:
            raise PermissionDenied('You may not view injury records.')
        return Response(InjuryRecordSerializer(records, many=True).data)

    def post(self, request):
        if request.user.role != Roles.PLAYER:
            raise PermissionDenied('Only players can log their own injuries.')
        serializer = InjuryRecordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        record = serializer.save(player=request.user)
        return Response(
            InjuryRecordSerializer(record).data, status=status.HTTP_201_CREATED
        )


class InjuryRecordDetailView(APIView):
    """GET/PUT/DELETE /api/injuries/<pk>/ — one injury record.

    Reads: the owning player, their linked guardian(s), coach, admin.
    Writes: the owning player only.
    """

    def _get_record(self, request, pk, write):
        record = get_object_or_404(InjuryRecord, pk=pk)
        if write:
            allowed = (
                request.user.role == Roles.PLAYER
                and record.player_id == request.user.id
            )
        else:
            allowed = (
                request.user.role == Roles.ADMIN
                or (
                    request.user.role == Roles.COACH
                    and request.user.club_id is not None
                    and record.player.club_id == request.user.club_id
                )
                or (
                    request.user.role == Roles.PLAYER
                    and record.player_id == request.user.id
                )
                or (
                    request.user.role == Roles.GUARDIAN
                    and GuardianLink.objects.filter(
                        guardian=request.user, player_id=record.player_id
                    ).exists()
                )
            )
        if not allowed:
            raise PermissionDenied('You may not access this injury record.')
        if not write:
            _require_unlock_when_pin_exists(request, record.player_id)
        return record

    def get(self, request, pk):
        record = self._get_record(request, pk, write=False)
        return Response(InjuryRecordSerializer(record).data)

    def put(self, request, pk):
        record = self._get_record(request, pk, write=True)
        serializer = InjuryRecordSerializer(
            record, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(InjuryRecordSerializer(record).data)

    def delete(self, request, pk):
        record = self._get_record(request, pk, write=True)
        record.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


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
