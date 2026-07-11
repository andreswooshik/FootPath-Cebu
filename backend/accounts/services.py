from django.db import transaction
from django.utils.crypto import get_random_string
from firebase_admin import auth as firebase_auth

from .firebase import ensure_initialized
from .models import User

# Excludes visually-ambiguous characters (0/O, 1/l/I) for readability when an
# admin has to relay this password to someone by hand.
_PASSWORD_CHARS = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'


class ProvisioningError(Exception):
    """Raised when a user cannot be provisioned (bad input, conflicts)."""


def link_or_create_firebase_user(user, *, password=None):
    """Ensure `user.email` has a Firebase account and link `user.firebase_uid`.

    Adopts an existing Firebase account for that email if one exists (its
    password is left untouched); otherwise creates a new one. Also marks the
    local password unusable, since API/app users authenticate via Firebase
    only. The caller is responsible for saving `user`.

    Returns the temporary password when a NEW Firebase account was created
    (the given `password`, or a generated one), or None when an existing
    account was adopted.
    """
    if not user.email:
        raise ProvisioningError(
            'A user needs an email before it can be synced to Firebase.'
        )

    ensure_initialized()

    temp_password = None
    try:
        fb_user = firebase_auth.get_user_by_email(user.email)
    except firebase_auth.UserNotFoundError:
        temp_password = password or get_random_string(
            12, allowed_chars=_PASSWORD_CHARS
        )
        fb_user = firebase_auth.create_user(
            email=user.email, password=temp_password
        )

    user.firebase_uid = fb_user.uid
    user.set_unusable_password()
    return temp_password


def provision_user(*, email, first_name, last_name, role):
    """Create a Firebase account (if needed) and a linked local User.

    Returns (user, temporary_password_or_None, note). The temporary password
    is only returned when a brand-new Firebase account was created; if an
    existing, unlinked Firebase account is adopted instead, its password is
    left untouched and `note` explains that.
    """
    if User.objects.filter(email__iexact=email).exists():
        raise ProvisioningError(f'{email} is already provisioned.')

    user = User(
        username=email,
        email=email,
        first_name=first_name,
        last_name=last_name,
        role=role,
    )
    temp_password = link_or_create_firebase_user(user)

    try:
        with transaction.atomic():
            user.save()
    except Exception:
        # Compensation: if we just CREATED the Firebase account, delete it so a
        # DB failure never leaves an orphaned identity (audit checklist item 5).
        # An adopted, pre-existing account (temp_password is None) is left alone.
        if temp_password is not None and user.firebase_uid:
            try:
                firebase_auth.delete_user(user.firebase_uid)
            except Exception:
                pass  # best-effort cleanup; surface the original DB error
        raise

    note = (
        'New Firebase account created.'
        if temp_password
        else 'Existing Firebase account linked; its current password was left unchanged.'
    )
    return user, temp_password, note
