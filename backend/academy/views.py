"""Academy REST endpoints.

Authentication is the project-wide FirebaseAuthentication (settings.py).
Authorization is enforced two ways, both server-side (never trust the client):
  - endpoint-level RBAC via accounts.permissions.role_required(...);
  - object-level scoping in each queryset/handler (a guardian only ever reaches
    a player they are linked to — audit finding F3).
"""
from django.db import transaction
from django.db.models import Avg, Count, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import GuardianLink, Roles, User
from accounts.permissions import IsAdmin
from accounts.serializers import UserSerializer
from accounts.services import ProvisioningError, provision_user

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
    InjuryRecord,
    PlayerProfile,
    PlayerPrivacyPin,
    SessionConfirmation,
    TrainingSession,
)
from .notifications import (
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
    InjuryRecordSerializer,
    PlayerPositionSerializer,
    PlayerSerializer,
    SessionAttendanceRecordSerializer,
    SessionConfirmationSerializer,
    TrainingSessionSerializer,
)

# Roles that participate in the dispute process: the coach flags, School
# Staff and Admin review/respond. Players and guardians have no access.
DISPUTE_ROLES = (Roles.COACH, Roles.SCHOOL_STAFF, Roles.ADMIN)
from .storage import upload_photo


def _in_same_club(user, player_id):
    """True if `player_id` names a user in `user`'s club (multi-tenant scope).

    Matches on club_id including NULL==NULL, so legacy club-less accounts still
    interoperate; returns False when no such user exists. ADMIN is club-less by
    design and is always handled by an explicit branch before this is called.
    """
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
    qs = TrainingSession.objects.all()
    if user.role == Roles.ADMIN:
        return qs
    return qs.filter(club=user.club)


def _session_in_user_scope(user, session):
    """True if `user` may see/act on `session` under club tenancy (Admin: any
    club; everyone else: only their own club's sessions)."""
    if user.role == Roles.ADMIN:
        return True
    return session.club_id == user.club_id


class SquadListView(APIView):
    """GET /api/players/ — the roster. Coach (own club only) and Admin (all)."""

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view the squad.')
        profiles = PlayerProfile.objects.select_related('user')
        # Coaches see only their own club's roster; Admin sees every club.
        if request.user.role == Roles.COACH:
            profiles = profiles.filter(user__club=request.user.club)
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
        return Response(PlayerSerializer(profiles, many=True).data)


def _pin_profile(player_id):
    return get_object_or_404(
        PlayerProfile.objects.select_related('user'), user_id=player_id
    )


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


class PlayerPrivacyPinView(APIView):
    """GET status; PUT lets the player create or change their own PIN."""

    def get(self, request, player_id):
        if not _may_manage_pin(request.user, player_id):
            raise PermissionDenied('You cannot access that player PIN.')
        return Response(pin_status(_pin_profile(player_id).user))

    def put(self, request, player_id):
        if request.user.role != Roles.PLAYER or str(request.user.id) != str(player_id):
            raise PermissionDenied('Only the player can set their own PIN.')
        pin = request.data.get('pin')
        try:
            set_pin(
                _pin_profile(player_id).user,
                pin,
                current_pin=request.data.get('currentPin'),
            )
        except InvalidCurrentPin as exc:
            raise ValidationError(str(exc))
        except ValueError as exc:
            raise ValidationError(str(exc))
        AuditLog.record(request.user, 'player_pin.changed', target=request.user.email)
        return Response(pin_status(request.user))


class PlayerPrivacyPinVerifyView(APIView):
    """POST verifies the player's PIN without returning any secret material."""

    def post(self, request, player_id):
        if request.user.role != Roles.PLAYER or str(request.user.id) != str(player_id):
            raise PermissionDenied('Only the player can verify their own PIN.')
        try:
            verify_pin(_pin_profile(player_id).user, request.data.get('pin'))
        except PinLocked as exc:
            return Response(
                {'detail': str(exc), 'lockedUntil': exc.locked_until.isoformat()},
                status=status.HTTP_423_LOCKED,
            )
        except PinNotSet as exc:
            raise ValidationError(str(exc))
        except InvalidPin as exc:
            raise ValidationError(str(exc))
        return Response({'verified': True})


class PlayerPrivacyPinResetView(APIView):
    """POST clears a PIN for a linked guardian or same-club coordinator."""

    def post(self, request, player_id):
        if not _may_manage_pin(request.user, player_id):
            raise PermissionDenied('You cannot reset that player PIN.')
        if request.user.role not in (Roles.ADMIN, Roles.COORDINATOR, Roles.GUARDIAN):
            raise PermissionDenied('Only a guardian or coordinator can reset a PIN.')
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
        if profile.user.club_id != request.user.club_id:
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
        if profile.user.club_id != request.user.club_id:
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
        records = Attendance.objects.select_related('session', 'recorded_by').filter(
            player_id=player_id
        )
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


class SquadProgressView(APIView):
    """GET /api/progress/squad/ — per-player attendance and effort aggregates
    for the requester's club: the data behind the coach's Progress tab.

    Coach (own club) and Admin (legacy club-less rows match NULL==NULL, same
    convention as everywhere else). One aggregate query, not one per player.
    """

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view squad progress.')

        profiles = (
            PlayerProfile.objects.select_related('user')
            .filter(user__club_id=request.user.club_id)
            .order_by('user__first_name', 'user__last_name')
        )
        stats = {
            row['player_id']: row
            for row in Attendance.objects.filter(
                player__club_id=request.user.club_id
            )
            .values('player_id')
            .annotate(
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
        if session.club_id != request.user.club_id:
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
        # Sent before the delete: the recipient query needs the row, and the
        # notify helpers never raise into the request path.
        notify_session_cancelled(session)
        AuditLog.record(
            request.user, 'session.cancelled',
            target=session.title, detail=str(session.date),
        )
        session.delete()
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
        dispute.raised_by_id is not None
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
            disputes = disputes.filter(raised_by__club=request.user.club)
        return Response(DisputeSerializer(disputes, many=True).data)

    def post(self, request):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can raise disputes.')
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
        get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
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
            records = InjuryRecord.objects.filter(player=request.user)
        elif request.user.role in (Roles.COACH, Roles.ADMIN):
            records = InjuryRecord.objects.select_related('player')
            # Coaches are club-scoped; Admin sees every club.
            if request.user.role == Roles.COACH:
                records = records.filter(player__club=request.user.club)
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
            records = InjuryRecord.objects.filter(player_id=player_id)
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


class PlayerPhotoUploadView(APIView):
    """POST /api/admin/players/<id>/photo/ (multipart) — Admin uploads a player
    photo to Supabase Storage and stores its object path on the profile."""

    permission_classes = [IsAdmin]

    def post(self, request, player_id):
        upload = request.FILES.get('photo')
        if upload is None:
            raise ValidationError('A photo file is required (field "photo").')
        profile = get_object_or_404(PlayerProfile, user_id=player_id)
        try:
            path = upload_photo(
                player_id,
                upload.read(),
                content_type=upload.content_type or 'image/jpeg',
            )
        except RuntimeError as exc:
            raise ValidationError(str(exc))
        profile.photo_path = path
        profile.save(update_fields=['photo_path'])
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
        guardian = data.get('guardian_id')

        # Place the new player by the configured tier bands (previously both
        # fields silently kept their model defaults: age 0, tier DEVELOPMENT).
        age, tier = AgeTierSetting.profile_defaults_for(data['date_of_birth'])

        try:
            with transaction.atomic():
                user, temp_password, note = provision_user(
                    email=data['email'],
                    first_name=data['first_name'],
                    last_name=data['last_name'],
                    role=Roles.PLAYER,
                )
                profile = PlayerProfile.objects.create(
                    user=user,
                    middle_initial=data['middle_initial'],
                    date_of_birth=data['date_of_birth'],
                    age=age,
                    age_tier=tier,
                )
                if guardian is not None:
                    GuardianLink.objects.create(guardian=guardian, player=user)
        except ProvisioningError as exc:
            raise ValidationError(str(exc))
        AuditLog.record(
            request.user, 'account.created', target=user.email, detail='PLAYER',
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
