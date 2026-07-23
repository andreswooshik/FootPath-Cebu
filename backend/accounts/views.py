from django.shortcuts import get_object_or_404
from rest_framework import generics
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from academy.models import AuditLog

from .models import GuardianLink, Roles, User
from .permissions import IsAdmin
from .serializers import (
    AdminCreateUserSerializer,
    AdminUpdateUserSerializer,
    GuardianLinkSerializer,
    UserSerializer,
)
from .services import ProvisioningError, change_role, provision_user


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


class AdminUserListCreateView(generics.ListCreateAPIView):
    """Admin-only: list provisioned accounts, or create one.

    Account creation is restricted to Admin — this is the only way (besides
    the seed_users dev command) that a Coach/Player/School Staff/Guardian
    account comes into existence.
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
            user, temp_password, note = provision_user(**serializer.validated_data)
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
