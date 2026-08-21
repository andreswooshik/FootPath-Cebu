from django.shortcuts import get_object_or_404
from django.core.cache import cache
from django.db import connection
from rest_framework import generics
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from academy.models import AuditLog

from .models import Club, GuardianLink, Roles, User
from .permissions import IsAdmin
from .serializers import (
    AdminClubSerializer,
    AdminCoordinatorCreateSerializer,
    AdminCreateUserSerializer,
    AdminUpdateUserSerializer,
    GuardianLinkSerializer,
    UserSerializer,
)
from .services import (
    ProvisioningError,
    change_role,
    provision_club_coordinator,
    provision_user,
    provision_web_user,
)


class MeView(APIView):
    """Return the authenticated user's profile and role.

    Reaching this endpoint at all proves the Firebase ID token was verified
    and mapped to a provisioned account — this is the login verification.
    """

    def get(self, request):
        return Response(UserSerializer(request.user).data)


@api_view(['GET'])
@permission_classes([AllowAny])
def health(request):
    return Response({'status': 'ok'})


@api_view(['GET'])
@permission_classes([AllowAny])
def readiness(request):
    """Dependency-aware probe for deployment health checks.

    Liveness stays cheap at ``/api/health/``. Readiness proves that both the
    relational database and the shared cache required by production can be
    reached; it returns 503 without leaking connection details.
    """
    checks = {'database': False, 'cache': False}
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
            checks['database'] = cursor.fetchone()[0] == 1
    except Exception:
        pass
    try:
        probe_key = 'footpath-readiness-probe'
        cache.set(probe_key, 'ok', timeout=10)
        checks['cache'] = cache.get(probe_key) == 'ok'
    except Exception:
        pass
    ready = all(checks.values())
    return Response(
        {'status': 'ready' if ready else 'unavailable', 'checks': checks},
        status=200 if ready else 503,
    )


class AdminUserListCreateView(generics.ListCreateAPIView):
    """Super Admin registry and exceptional non-player member creation.

    Club Coordinators are the normal creator of club members. Players are
    excluded because their User and PlayerProfile must be created together.
    """

    permission_classes = [IsAdmin]
    queryset = User.objects.exclude(role=Roles.ADMIN).order_by('email')

    def get_serializer_class(self):
        if self.request.method == 'POST':
            return AdminCreateUserSerializer
        return UserSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            data = serializer.validated_data
            if data['role'] == Roles.SCHOOL_STAFF:
                user, temp_password = provision_web_user(**data)
                note = 'School Staff portal account created.'
            else:
                user, temp_password, note = provision_user(**data)
        except ProvisioningError as exc:
            raise ValidationError(str(exc))
        AuditLog.record(
            request.user, 'account.created', target=user.email, detail=user.role,
        )
        return Response(
            {
                'user': UserSerializer(user).data,
                'temporary_password': temp_password,
                'note': note,
            },
            status=201,
        )


class AdminClubListCreateView(generics.ListCreateAPIView):
    """Super Admin creates and lists the platform's tenant clubs."""

    permission_classes = [IsAdmin]
    queryset = Club.objects.order_by('name')
    serializer_class = AdminClubSerializer

    def perform_create(self, serializer):
        club = serializer.save()
        AuditLog.record(
            self.request.user,
            'club.created',
            target=club.name,
            detail=club.club_type,
        )


class AdminClubDetailView(generics.RetrieveUpdateAPIView):
    """Super Admin edits club details/type and its active state."""

    permission_classes = [IsAdmin]
    queryset = Club.objects.all()
    serializer_class = AdminClubSerializer

    def perform_update(self, serializer):
        club = serializer.save()
        if not club.is_active:
            club.members.filter(role=Roles.COORDINATOR).update(is_active=False)
        if not club.allows_school_staff:
            club.members.filter(role=Roles.SCHOOL_STAFF).update(is_active=False)
        AuditLog.record(
            self.request.user,
            'club.updated',
            target=club.name,
            detail=f'{club.club_type}; active={club.is_active}',
        )


class AdminCoordinatorCreateView(APIView):
    """Super Admin assigns the single coordinator for a selected club."""

    permission_classes = [IsAdmin]

    def post(self, request):
        serializer = AdminCoordinatorCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            coordinator, password = provision_club_coordinator(
                **serializer.validated_data
            )
        except ProvisioningError as exc:
            raise ValidationError(str(exc))
        AuditLog.record(
            request.user,
            'coordinator.created',
            target=coordinator.email,
            detail=coordinator.club.name,
        )
        return Response({
            'user': UserSerializer(coordinator).data,
            'temporary_password': password,
            'note': 'Club Coordinator portal account created.',
        }, status=201)


class AdminUserDetailView(APIView):
    """PATCH /api/admin/users/<pk>/ — post-creation account lifecycle.

    Accepts `role` (between Coach / School Staff / Guardian; the switch rules
    and auth-mode handling live in services.change_role) and/or `is_active`
    (deactivation locks the account out everywhere at once: the API rejects
    inactive users at authentication, and Django's ModelBackend refuses their
    portal login). Admin accounts are out of reach entirely.
    """

    permission_classes = [IsAdmin]

    def patch(self, request, pk):
        user = get_object_or_404(
            User.objects.exclude(role=Roles.ADMIN).exclude(is_superuser=True),
            pk=pk,
        )
        serializer = AdminUpdateUserSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        temp_password = None
        note = None
        if 'role' in data and data['role'] != user.role:
            previous_role = user.role
            try:
                temp_password, note = change_role(user, data['role'])
            except ProvisioningError as exc:
                raise ValidationError(str(exc))
            AuditLog.record(
                request.user, 'account.role_changed', target=user.email,
                detail=f'{previous_role} → {user.role}',
            )
        if 'is_active' in data and data['is_active'] != user.is_active:
            if data['is_active'] and user.club_id and not user.club.is_active:
                raise ValidationError(
                    'A member cannot be activated while their club is inactive.'
                )
            user.is_active = data['is_active']
            user.save(update_fields=['is_active'])
            AuditLog.record(
                request.user,
                'account.reactivated' if user.is_active
                else 'account.deactivated',
                target=user.email,
            )

        return Response(
            {
                'user': UserSerializer(user).data,
                'temporary_password': temp_password,
                'note': note,
            }
        )


class AdminGuardianLinkListCreateView(generics.ListCreateAPIView):
    permission_classes = [IsAdmin]
    queryset = GuardianLink.objects.select_related('guardian', 'player').order_by(
        '-created_at'
    )
    serializer_class = GuardianLinkSerializer

    def perform_create(self, serializer):
        link = serializer.save()
        AuditLog.record(
            self.request.user, 'guardian_link.created',
            target=f'{link.guardian.email} → {link.player.email}',
        )


class AdminGuardianLinkDestroyView(generics.DestroyAPIView):
    permission_classes = [IsAdmin]
    queryset = GuardianLink.objects.all()

    def perform_destroy(self, instance):
        AuditLog.record(
            self.request.user, 'guardian_link.removed',
            target=f'{instance.guardian.email} → {instance.player.email}',
        )
        instance.delete()
