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

from accounts.models import GuardianLink, Roles
from accounts.permissions import IsAdmin

from .models import Attendance, DeviceToken, PlayerProfile, TrainingSession
from .notifications import notify_session_scheduled
from .serializers import (
    AssessmentSerializer,
    AttendanceSerializer,
    PlayerSerializer,
    TrainingSessionSerializer,
)
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
