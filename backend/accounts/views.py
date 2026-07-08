from rest_framework import generics
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import GuardianLink, Roles, User
from .permissions import IsAdmin
from .serializers import (
    AdminCreateUserSerializer,
    GuardianLinkSerializer,
    UserSerializer,
)
from .services import ProvisioningError, provision_user


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
        return Response(
            {
                'user': UserSerializer(user).data,
                'temporary_password': temp_password,
                'note': note,
            },
            status=201,
        )


class AdminGuardianLinkListCreateView(generics.ListCreateAPIView):
    permission_classes = [IsAdmin]
    queryset = GuardianLink.objects.select_related('guardian', 'player').order_by(
        '-created_at'
    )
    serializer_class = GuardianLinkSerializer


class AdminGuardianLinkDestroyView(generics.DestroyAPIView):
    permission_classes = [IsAdmin]
    queryset = GuardianLink.objects.all()
