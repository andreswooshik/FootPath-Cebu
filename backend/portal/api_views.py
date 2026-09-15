"""Public API surfaces backed by the portal's existing application workflow."""

from django.db import IntegrityError
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import ProvisioningError
from accounts.validators import MOBILE_COACH_LICENSE_MAX_BYTES

from .forms import CoordinatorSignupForm
from .services import register_coordinator, split_coordinator_name


class MobileClubRegistrationView(APIView):
    """Submit the same pending club application used by the web portal."""

    authentication_classes = []
    permission_classes = [AllowAny]
    parser_classes = [MultiPartParser, FormParser]
    throttle_scope = 'club_registration'

    def post(self, request):
        form = CoordinatorSignupForm(
            data=request.data,
            files=request.FILES,
            coach_license_max_bytes=MOBILE_COACH_LICENSE_MAX_BYTES,
        )
        if not form.is_valid():
            errors = {
                field: [item['message'] for item in messages]
                for field, messages in form.errors.get_json_data().items()
            }
            return Response({'errors': errors}, status=status.HTTP_400_BAD_REQUEST)

        data = form.cleaned_data
        first_name, last_name = split_coordinator_name(data['coordinator_name'])
        try:
            coordinator, club = register_coordinator(
                first_name=first_name,
                last_name=last_name,
                email=data['email'],
                club_name=data['club_name'],
                password=data['password1'],
                is_school_affiliated=data['is_school_affiliated'],
                school_name=data.get('school_name', ''),
                head_coach_name=data['head_coach_name'],
                coach_license=data['coach_license'],
                cvfa_membership=data['cvfa_membership'],
            )
        except (IntegrityError, ProvisioningError):
            return Response(
                {'errors': {'__all__': ['This application could not be submitted.']}},
                status=status.HTTP_409_CONFLICT,
            )
        except OSError:
            return Response(
                {'errors': {'coach_license': ['Coach-license storage is temporarily unavailable.']}},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

        return Response(
            {
                'status': 'PENDING',
                'club_id': club.pk,
                'coordinator_email': coordinator.email,
                'message': 'Your club registration application was submitted for review.',
            },
            status=status.HTTP_201_CREATED,
        )
