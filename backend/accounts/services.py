from django.db import transaction
from django.utils.crypto import get_random_string
from firebase_admin import auth as firebase_auth

from .firebase import ensure_initialized
from .models import Roles, User

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


def provision_user(*, email, first_name, last_name, role, club=None):
    """Create a Firebase account (if needed) and a linked local User.

    For app users (player / coach / guardian) who authenticate via Firebase.
    `club` scopes the account to a tenant (None for cross-club ADMIN accounts).

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
        club=club,
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


# Roles an account may be switched between after creation. PLAYER is excluded
# (a player is created together with their profile by a dedicated flow, and
# the profile depends on the role) and COORDINATOR is excluded (a coordinator
# owns their club).
SWITCHABLE_ROLES = (Roles.COACH, Roles.SCHOOL_STAFF, Roles.GUARDIAN)


def change_role(user, new_role):
    """Switch `user` to `new_role`, handling the auth-mode change.

    School Staff sign in with a Django password on the web portal; coaches and
    guardians with Firebase in the app. Crossing that line issues the
    credential the new surface needs. Returns (temp_password_or_None, note) —
    the temp password, when present, is relayed once by the admin.
    """
    if user.is_superuser or user.role == Roles.ADMIN:
        raise ProvisioningError('Admin accounts cannot be changed here.')
    if user.role == Roles.PLAYER or hasattr(user, 'player_profile'):
        raise ProvisioningError(
            'Player accounts keep the PLAYER role — their profile depends on it.'
        )
    if user.role == Roles.COORDINATOR:
        raise ProvisioningError(
            'A coordinator owns their club and cannot change role.'
        )
    if new_role not in SWITCHABLE_ROLES:
        raise ProvisioningError(f'Accounts cannot be switched to {new_role}.')
    if (
        user.role == Roles.GUARDIAN
        and new_role != Roles.GUARDIAN
        and user.guardian_links.exists()
    ):
        raise ProvisioningError(
            "Remove this guardian's player links before changing their role."
        )

    temp_password = None
    note = ''
    if new_role == Roles.SCHOOL_STAFF and user.role != Roles.SCHOOL_STAFF:
        # Firebase app user → web user: issue a Django session password.
        temp_password = get_random_string(12, allowed_chars=_PASSWORD_CHARS)
        user.set_password(temp_password)
        note = 'School Staff sign in on the web portal with this password.'
    elif user.role == Roles.SCHOOL_STAFF and new_role != Roles.SCHOOL_STAFF:
        # Web user → Firebase app user: ensure a Firebase identity exists
        # (marks the Django password unusable).
        temp_password = link_or_create_firebase_user(user)
        note = (
            'They sign in to the app with this new password.'
            if temp_password
            else 'Their existing app (Firebase) password still works.'
        )

    user.role = new_role
    user.save()
    return temp_password, note


def provision_web_user(
    *, email, first_name, last_name, role, club, password=None, is_active=True
):
    """Create a web-portal user (Coordinator / School Staff) with a usable
    Django session password and NO Firebase identity.

    These accounts authenticate against the Django session on the web portal
    only — they never use the Firebase-authenticated mobile app, so no Firebase
    account is created and no `firebase_uid` is stamped. `is_active=False` holds
    a coordinator signup pending superadmin approval (Django's ModelBackend
    refuses inactive logins).

    Returns (user, password) — the caller relays `password` to the person
    (the one supplied, or a generated temporary one).
    """
    if User.objects.filter(email__iexact=email).exists():
        raise ProvisioningError(f'{email} is already provisioned.')

    generated = password or get_random_string(12, allowed_chars=_PASSWORD_CHARS)
    user = User(
        username=email,
        email=email,
        first_name=first_name,
        last_name=last_name,
        role=role,
        club=club,
        is_active=is_active,
    )
    user.set_password(generated)
    user.save()
    return user, generated
