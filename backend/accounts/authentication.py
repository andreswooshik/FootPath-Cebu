from django.contrib.auth import get_user_model
from firebase_admin import auth as firebase_auth
from rest_framework import authentication, exceptions

from .firebase import ensure_initialized
from .models import Roles

User = get_user_model()


class FirebaseAuthentication(authentication.BaseAuthentication):
    """Authenticate requests bearing a Firebase ID token.

    Expects `Authorization: Bearer <ID token>`. The token is verified with
    the Firebase Admin SDK, then mapped to a local provisioned user. A valid
    Firebase account with no local row is rejected — account creation is
    Admin-only, so an unknown UID means the user was never provisioned.
    """

    def authenticate(self, request):
        header = request.META.get('HTTP_AUTHORIZATION', '')
        if not header.startswith('Bearer '):
            # No bearer token: fall through so session auth (Django admin)
            # and anonymous handling still work.
            return None
        token = header.split(' ', 1)[1].strip()

        try:
            ensure_initialized()
        except Exception as exc:
            raise exceptions.AuthenticationFailed(
                'Authentication service is not configured.'
            ) from exc

        # Check token revocation on state-changing requests (writes, admin
        # actions) so a signed-out or disabled account loses write access
        # immediately, without paying the extra network round trip on every
        # cheap read (audit finding F4).
        # Read endpoints can expose household, medical, and academic data, so
        # revoked tokens must lose read access immediately as well as write
        # access.
        check_revoked = True
        try:
            decoded = firebase_auth.verify_id_token(
                token, clock_skew_seconds=10, check_revoked=check_revoked
            )
        except firebase_auth.ExpiredIdTokenError:
            raise exceptions.AuthenticationFailed('Token expired.')
        except firebase_auth.RevokedIdTokenError:
            raise exceptions.AuthenticationFailed('Session revoked. Sign in again.')
        except (
            firebase_auth.InvalidIdTokenError,
            ValueError,
        ):
            raise exceptions.AuthenticationFailed('Invalid Firebase ID token.')

        try:
            user = User.objects.get(
                firebase_uid=decoded['uid'], is_active=True
            )
        except User.DoesNotExist:
            raise exceptions.AuthenticationFailed(
                'No account for this login. Contact an administrator.'
            )
        if user.role != Roles.ADMIN and user.club_id is None:
            raise exceptions.AuthenticationFailed(
                'This account is not assigned to an academy club.'
            )
        if user.role != Roles.ADMIN and not user.club.is_active:
            raise exceptions.AuthenticationFailed(
                'This club is inactive. Contact the platform administrator.'
            )
        if (
            user.role == Roles.SCHOOL_STAFF
            and not user.club.allows_school_staff
        ):
            raise exceptions.AuthenticationFailed(
                'School Staff access is unavailable for an Independent club.'
            )
        return (user, decoded)

    def authenticate_header(self, request):
        # Present a WWW-Authenticate challenge so unauthenticated requests
        # get 401 rather than 403.
        return 'Bearer realm="api"'
