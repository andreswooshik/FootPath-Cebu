"""Access control for the server-rendered portal (session-authenticated).

Mirrors the DRF-side `accounts.permissions.role_required` but for classic
Django views: deny by default, redirect anonymous users to login, 403 the
wrong role (OWASP A01 — Broken Access Control).
"""
from functools import wraps

from django.contrib.auth.views import redirect_to_login
from django.core.exceptions import PermissionDenied


def portal_role_required(*roles):
    """Restrict a portal view to the given `User.role` values."""

    def decorator(view):
        @wraps(view)
        def _wrapped(request, *args, **kwargs):
            if not request.user.is_authenticated:
                return redirect_to_login(request.get_full_path())
            if request.user.role not in roles:
                raise PermissionDenied('Your role cannot access this page.')
            if request.user.club_id is None:
                raise PermissionDenied('Your account is not assigned to a club.')
            if not request.user.club.is_active:
                raise PermissionDenied('Your club is inactive.')
            if (
                request.user.role == 'SCHOOL_STAFF'
                and not request.user.club.allows_school_staff
            ):
                raise PermissionDenied(
                    'School Staff access is unavailable for an Independent club.'
                )
            return view(request, *args, **kwargs)

        return _wrapped

    return decorator
