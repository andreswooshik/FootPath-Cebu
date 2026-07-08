from django.utils.crypto import get_random_string
from firebase_admin import auth as firebase_auth

from .firebase import ensure_initialized
from .models import User

# Excludes visually-ambiguous characters (0/O, 1/l/I) for readability when an
# admin has to relay this password to someone by hand.
_PASSWORD_CHARS = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'


class ProvisioningError(Exception):
    """Raised when a user cannot be provisioned (bad input, conflicts)."""


def provision_user(*, email, first_name, last_name, role):
    """Create a Firebase account (if needed) and a linked local User.

    Returns (user, temporary_password_or_None, note). The temporary password
    is only returned when a brand-new Firebase account was created; if an
    existing, unlinked Firebase account is adopted instead, its password is
    left untouched and `note` explains that.
    """
    if User.objects.filter(email__iexact=email).exists():
        raise ProvisioningError(f'{email} is already provisioned.')

    ensure_initialized()

    temp_password = None
    note = ''
    try:
        fb_user = firebase_auth.get_user_by_email(email)
        note = 'Existing Firebase account linked; its current password was left unchanged.'
    except firebase_auth.UserNotFoundError:
        temp_password = get_random_string(12, allowed_chars=_PASSWORD_CHARS)
        fb_user = firebase_auth.create_user(email=email, password=temp_password)

    user = User.objects.create(
        firebase_uid=fb_user.uid,
        username=email,
        email=email,
        first_name=first_name,
        last_name=last_name,
        role=role,
    )
    user.set_unusable_password()
    user.save()

    return user, temp_password, note
