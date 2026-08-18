from django.db import transaction
from django.utils.crypto import get_random_string
from uuid import uuid4
from firebase_admin import auth as firebase_auth

from .firebase import ensure_initialized
from .models import Club, GuardianLink, Roles, User

# Excludes visually-ambiguous characters (0/O, 1/l/I) for readability when an
# admin has to relay this password to someone by hand.
_PASSWORD_CHARS = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789'


class ProvisioningError(Exception):
    """Raised when a user cannot be provisioned (bad input, conflicts)."""


def _require_active_club(club, *, role):
    """Return a validated tenant for every club-member account."""
    if not isinstance(club, Club) or club.pk is None:
        raise ProvisioningError(f'{role} accounts must be assigned to a club.')
    if not club.is_active:
        raise ProvisioningError('Accounts cannot be created for an inactive club.')
    if role == Roles.SCHOOL_STAFF and not club.allows_school_staff:
        raise ProvisioningError(
            'School Staff accounts are available only to School clubs.'
        )
    return club


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


def provision_user(
    *, email, first_name, last_name, role, club=None, _allow_player=False
):
    """Create a Firebase account (if needed) and a linked local User.

    For app users (player / coach / guardian) who authenticate via Firebase.
    `club` scopes the account to a tenant (None for cross-club ADMIN accounts).

    Returns (user, temporary_password_or_None, note). The temporary password
    is only returned when a brand-new Firebase account was created; if an
    existing, unlinked Firebase account is adopted instead, its password is
    left untouched and `note` explains that.
    """
    if role == Roles.PLAYER and not _allow_player:
        raise ProvisioningError(
            'Players must be created through the player provisioning service.'
        )
    if role not in (Roles.COACH, Roles.GUARDIAN, Roles.PLAYER):
        raise ProvisioningError(
            'This provisioning path supports Coach, Guardian, and Player app accounts only.'
        )
    club = _require_active_club(club, role=role)
    email = email.strip().lower()
    if not email:
        raise ProvisioningError('An email address is required for an app account.')
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


def provision_managed_player(*, first_name, last_name, club):
    """Create a player profile with no independent login identity."""
    club = _require_active_club(club, role=Roles.PLAYER)
    user = User(
        username=f'managed-player-{uuid4().hex}',
        email='',
        first_name=first_name,
        last_name=last_name,
        role=Roles.PLAYER,
        club=club,
        is_active=True,
    )
    user.set_unusable_password()
    user.save()
    return user


def provision_player(
    *, email, first_name, last_name, middle_initial, date_of_birth, club,
    guardian=None,
):
    """Create one valid PLAYER aggregate in a single transaction.

    Every player creation path calls this service. It derives the age/tier,
    creates exactly one User and PlayerProfile, and optionally creates a
    same-club GuardianLink. A failed profile/link write rolls back the database
    and compensates a newly-created Firebase identity.
    """
    from academy.models import AgeTierSetting, PlayerProfile

    club = _require_active_club(club, role=Roles.PLAYER)
    if guardian is not None:
        if guardian.role != Roles.GUARDIAN or not guardian.is_active:
            raise ProvisioningError(
                'The selected guardian must be active and have the Guardian role.'
            )
        if guardian.club_id != club.id:
            raise ProvisioningError(
                'Guardian and player must belong to the same club.'
            )

    user = None
    temp_password = None
    note = 'Managed player profile created without an independent login.'
    try:
        with transaction.atomic():
            normalized_email = (email or '').strip().lower()
            if normalized_email:
                user, temp_password, note = provision_user(
                    email=normalized_email,
                    first_name=first_name,
                    last_name=last_name,
                    role=Roles.PLAYER,
                    club=club,
                    _allow_player=True,
                )
            else:
                user = provision_managed_player(
                    first_name=first_name,
                    last_name=last_name,
                    club=club,
                )

            age, tier = AgeTierSetting.profile_defaults_for(date_of_birth)
            profile = PlayerProfile.objects.create(
                user=user,
                middle_initial=middle_initial or '',
                date_of_birth=date_of_birth,
                age=age,
                age_tier=tier,
            )
            if guardian is not None:
                GuardianLink.objects.create(guardian=guardian, player=user)
    except Exception:
        if temp_password is not None and user and user.firebase_uid:
            try:
                firebase_auth.delete_user(user.firebase_uid)
            except Exception:
                pass
        raise

    return user, profile, temp_password, note


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
    _require_active_club(user.club, role=new_role)
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
    if role not in (Roles.COORDINATOR, Roles.SCHOOL_STAFF):
        raise ProvisioningError(
            'This provisioning path supports Club Coordinator and School Staff only.'
        )
    club = _require_active_club(club, role=role)
    email = email.strip().lower()
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


@transaction.atomic
def provision_club_coordinator(
    *, email, first_name, last_name, club, password=None, is_active=True
):
    """Super Admin flow for a club's single coordinator account."""
    club = _require_active_club(club, role=Roles.COORDINATOR)
    if User.objects.filter(club=club, role=Roles.COORDINATOR).exists():
        raise ProvisioningError('This club already has a coordinator.')
    return provision_web_user(
        email=email,
        first_name=first_name,
        last_name=last_name,
        role=Roles.COORDINATOR,
        club=club,
        password=password,
        is_active=is_active,
    )
