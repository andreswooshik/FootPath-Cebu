from rest_framework.permissions import BasePermission

from .models import Roles


def role_required(*roles):
    """Build a DRF permission class allowing only the given roles."""

    class _RolePermission(BasePermission):
        message = 'You do not have permission to perform this action.'

        def has_permission(self, request, view):
            user = request.user
            if not user or not user.is_authenticated or user.role not in roles:
                return False
            return True

    _RolePermission.__name__ = f'RoleRequired[{", ".join(roles)}]'
    return _RolePermission


IsAdmin = role_required(Roles.ADMIN)
IsCoach = role_required(Roles.COACH)
IsPlayer = role_required(Roles.PLAYER)
IsSchoolStaff = role_required(Roles.SCHOOL_STAFF)
IsGuardian = role_required(Roles.GUARDIAN)
