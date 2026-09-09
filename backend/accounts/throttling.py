"""DRF throttles that key authenticated traffic by stable local user ID."""

from rest_framework.throttling import UserRateThrottle


class AuthenticatedUserRateThrottle(UserRateThrottle):
    """Apply the global API budget only after authentication succeeds."""

    scope = 'user'

    def get_cache_key(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return None
        return self.cache_format % {
            'scope': self.scope,
            'ident': request.user.pk,
        }
