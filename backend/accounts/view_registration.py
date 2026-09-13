import logging

from rest_framework.exceptions import APIException
from rest_framework.response import Response
from rest_framework.views import APIView

from .registration_serializers import GuardianRegistrationSerializer, RegistrationCommandSerializer
from .registration_service import check_guardian_duplicate, coordinator_club, register_player
from .services import ProvisioningError

logger = logging.getLogger(__name__)


class CoordinatorGuardianCheckView(APIView):
    throttle_scope = 'account_admin'

    def post(self, request):
        club = coordinator_club(request.user)
        serializer = GuardianRegistrationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        check_guardian_duplicate(club=club, data=serializer.validated_data)
        return Response({'available': True})


class CoordinatorPlayerRegistrationView(APIView):
    throttle_scope = 'account_admin'

    def post(self, request):
        coordinator_club(request.user)
        serializer = RegistrationCommandSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            result = register_player(actor=request.user, data=serializer.validated_data)
        except APIException:
            raise
        except ProvisioningError as error:
            return Response({'detail': str(error)}, status=400)
        except Exception:
            logger.error('Player registration failed; no request data logged.')
            return Response({'detail': 'Registration could not be completed. Please retry.'}, status=503)
        response = Response(result, status=200 if result['replayed'] else 201)
        response['Cache-Control'] = 'no-store'
        return response
