from django.contrib.auth import get_user_model
from firebase_admin import auth as firebase_auth
from rest_framework import authentication, exceptions

from .firebase import ensure_initialized

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

        try:
            # check_revoked is deliberately off: it adds a network round trip
            # per request. Enable it for sensitive endpoints when needed.
            decoded = firebase_auth.verify_id_token(
                token, clock_skew_seconds=10
            )
        except firebase_auth.ExpiredIdTokenError:
            raise exceptions.AuthenticationFailed('Token expired.')
        except (
            firebase_auth.RevokedIdTokenError,
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
        return (user, decoded)

    def authenticate_header(self, request):
        # Present a WWW-Authenticate challenge so unauthenticated requests
        # get 401 rather than 403.
        return 'Bearer realm="api"'
