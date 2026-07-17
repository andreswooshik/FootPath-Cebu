"""Academy REST endpoints.

Authentication is the project-wide FirebaseAuthentication (settings.py).
Authorization is enforced two ways, both server-side (never trust the client):
  - endpoint-level RBAC via accounts.permissions.role_required(...);
  - object-level scoping in each queryset/handler (a guardian only ever reaches
    a player they are linked to — audit finding F3).
"""
from django.db import transaction
from django.shortcuts import get_object_or_404
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
    Attendance,
    DeviceToken,
    Dispute,
    DisputeResponse,
    InjuryRecord,
    PlayerProfile,
    TrainingSession,
)
from .notifications import notify_assessment_saved, notify_session_scheduled
from .serializers import (
    AdminCreatePlayerSerializer,
    AssessmentSerializer,
    AttendanceSerializer,
    DisputeCreateSerializer,
    DisputeResponseCreateSerializer,
    DisputeSerializer,
    InjuryRecordSerializer,
    PlayerSerializer,
    SessionAttendanceRecordSerializer,
    TrainingSessionSerializer,
)

# Roles that participate in the dispute process: the coach flags, School
# Staff and Admin review/respond. Players and guardians have no access.
DISPUTE_ROLES = (Roles.COACH, Roles.SCHOOL_STAFF, Roles.ADMIN)
from .storage import upload_photo


def _guardian_may_read(user, player_id):
    """True if `user` is allowed to read the given player's data."""
    if user.role in (Roles.COACH, Roles.ADMIN):
        return True
    if user.role == Roles.PLAYER:
        return str(user.id) == str(player_id)
    if user.role == Roles.GUARDIAN:
        return GuardianLink.objects.filter(
            guardian=user, player_id=player_id
        ).exists()
    return False


class SquadListView(APIView):
    """GET /api/players/ — the full roster. Coach and Admin only."""

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view the squad.')
        profiles = PlayerProfile.objects.select_related('user').all()
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


class PlayerAssessmentView(APIView):
    """PUT /api/players/<id>/assessment/ — coach updates the six ratings."""

    def put(self, request, player_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can assess players.')
        profile = get_object_or_404(
            PlayerProfile.objects.select_related('user'), user_id=player_id
        )
        serializer = AssessmentSerializer(profile, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        # Notify the player + guardians only after the ratings are durably
        # committed (same pattern as session scheduling).
        transaction.on_commit(lambda: notify_assessment_saved(profile))
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
        get_object_or_404(TrainingSession, pk=session_id)
        records = Attendance.objects.select_related('session', 'recorded_by').filter(
            session_id=session_id
        )
        return Response(AttendanceSerializer(records, many=True).data)

    def post(self, request, session_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can record attendance.')
        session = get_object_or_404(TrainingSession, pk=session_id)
        serializer = SessionAttendanceRecordSerializer(
            data=request.data.get('records', []), many=True
        )
        serializer.is_valid(raise_exception=True)
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
    """GET (any authenticated) / POST (coach only) /api/training-sessions/."""

    def get(self, request):
        sessions = TrainingSession.objects.all()
        return Response(TrainingSessionSerializer(sessions, many=True).data)

    def post(self, request):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can schedule sessions.')
        serializer = TrainingSessionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        session = serializer.save(created_by=request.user)
        # Fan out the push only after the row is durably committed.
        transaction.on_commit(lambda: notify_session_scheduled(session))
        return Response(
            TrainingSessionSerializer(session).data, status=status.HTTP_201_CREATED
        )


class DisputeListCreateView(APIView):
    """GET/POST /api/disputes/.

    GET: every dispute, for all three dispute roles. POST: coach only — the
    coach flags, staff/admin respond via the thread endpoint.
    """

    def get(self, request):
        if request.user.role not in DISPUTE_ROLES:
            raise PermissionDenied('You may not view disputes.')
        disputes = Dispute.objects.select_related(
            'raised_by', 'subject_player'
        ).prefetch_related('responses__author')
        return Response(DisputeSerializer(disputes, many=True).data)

    def post(self, request):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can raise disputes.')
        serializer = DisputeCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
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
        dispute = get_object_or_404(Dispute, pk=pk)
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


class InjuryRecordListCreateView(APIView):
    """GET/POST /api/injuries/ — a player's injury history.

    Medical data gets least-privilege: the player CRUDs their own records
    only, coach/admin read everything (read-only — ?player=<id> narrows to
    one player), and guardians are denied entirely.
    """

    def get(self, request):
        if request.user.role == Roles.PLAYER:
            records = InjuryRecord.objects.filter(player=request.user)
        elif request.user.role in (Roles.COACH, Roles.ADMIN):
            records = InjuryRecord.objects.select_related('player').all()
            player_id = request.query_params.get('player')
            if player_id:
                records = records.filter(player_id=player_id)
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

    Reads: the owning player, coach, admin. Writes: the owning player only.
    """

    def _get_record(self, request, pk, write):
        record = get_object_or_404(InjuryRecord, pk=pk)
        if write:
            allowed = (
                request.user.role == Roles.PLAYER
                and record.player_id == request.user.id
            )
        else:
            allowed = request.user.role in (Roles.COACH, Roles.ADMIN) or (
                request.user.role == Roles.PLAYER
                and record.player_id == request.user.id
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
                )
                if guardian is not None:
                    GuardianLink.objects.create(guardian=guardian, player=user)
        except ProvisioningError as exc:
            raise ValidationError(str(exc))

        return Response(
            {
                'user': UserSerializer(user).data,
                'player': PlayerSerializer(profile).data,
                'temporary_password': temp_password,
                'note': note,
            },
            status=status.HTTP_201_CREATED,
        )
