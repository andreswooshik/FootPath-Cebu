from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .serializers import UserSerializer


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
