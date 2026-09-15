from uuid import uuid4

from django.db import transaction
from django.utils.crypto import get_random_string
from firebase_admin import auth as firebase_auth

from .firebase import ensure_initialized
from .models import Club, FirebaseProvisioningCleanup, GuardianLink, Roles, User

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
    return club


def link_or_create_firebase_user(user, *, password=None):
    """Ensure `user.email` has a Firebase account and link `user.firebase_uid`.

    Creates a new Firebase account, or accepts the identity only when the
    local user is already linked to the exact same UID. An unlinked Firebase
    account with the requested email is rejected: silently adopting it would
    let its existing owner take over the newly provisioned local role.

    Returns the temporary password when a new Firebase account was created,
    or None for an idempotent re-sync of an already linked local account.
    """
    if not user.email:
        raise ProvisioningError('A user needs an email before it can be synced to Firebase.')

    ensure_initialized()

    temp_password = None
    try:
        fb_user = firebase_auth.get_user_by_email(user.email)
    except firebase_auth.UserNotFoundError:
        temp_password = password or get_random_string(12, allowed_chars=_PASSWORD_CHARS)
        fb_user = firebase_auth.create_user(email=user.email, password=temp_password)
    else:
        if not user.firebase_uid or user.firebase_uid != fb_user.uid:
            raise ProvisioningError(
                'A Firebase identity already exists for this email. Have the '
                'account owner sign in or resolve the identity conflict before '
                'assigning an application role.'
            )

    user.firebase_uid = fb_user.uid
    user.set_unusable_password()
    return temp_password


def set_firebase_password(user, *, password):
    """Set a Firebase-only user's credential from the Django admin.

    App users must never acquire an independent Django password: their local
    row is an authorization/profile record keyed by ``firebase_uid`` and the
    Firebase credential is the only login credential.  Keeping the local
    password unusable also removes any accidental legacy Django password.
    """
    if not user.firebase_uid:
        raise ProvisioningError('This account is not linked to Firebase.')

    ensure_initialized()
    firebase_auth.update_user(user.firebase_uid, password=password)
    user.set_unusable_password()
    user.save(update_fields=['password'])


def provision_coordinator_firebase_identity(user, *, password, disabled):
    """Create and link the Firebase identity used by a Coordinator in mobile.

    A public application provisions this identity disabled. Approval enables
    the exact stored UID, so authentication never falls back to matching an
    untrusted Firebase account by email.
    """
    if user.role != Roles.COORDINATOR or not user.email:
        raise ProvisioningError('A Coordinator with an email is required.')

    ensure_initialized()
    created = False
    try:
        firebase_user = firebase_auth.get_user_by_email(user.email)
    except firebase_auth.UserNotFoundError:
        firebase_user = firebase_auth.create_user(
            email=user.email,
            password=password,
            disabled=disabled,
        )
        created = True
    else:
        if not user.firebase_uid or user.firebase_uid != firebase_user.uid:
            raise ProvisioningError(
                'A Firebase identity already exists for this email and is not '
                'linked to this Coordinator.'
            )
        firebase_user = firebase_auth.update_user(
            firebase_user.uid,
            password=password,
            disabled=disabled,
        )

    if User.objects.exclude(pk=user.pk).filter(firebase_uid=firebase_user.uid).exists():
        if created:
            firebase_auth.delete_user(firebase_user.uid)
        raise ProvisioningError('That Firebase identity is linked to another account.')

    user.firebase_uid = firebase_user.uid
    try:
        user.save(update_fields=['firebase_uid'])
    except Exception:
        if created:
            try:
                firebase_auth.delete_user(firebase_user.uid)
            except Exception:
                FirebaseProvisioningCleanup.objects.get_or_create(firebase_uid=firebase_user.uid)
        raise
    return created


def sync_coordinator_firebase_password(user, *, password):
    """Keep a Coordinator's portal and Firebase passwords in sync."""
    if user.role != Roles.COORDINATOR or not user.firebase_uid:
        return False
    ensure_initialized()
    firebase_auth.update_user(user.firebase_uid, password=password)
    return True


def set_coordinator_firebase_disabled(user, *, disabled):
    """Disable or enable a Coordinator identity with the club lifecycle."""
    if user.role != Roles.COORDINATOR:
        return False
    if not user.firebase_uid:
        if disabled:
            return False
        raise ProvisioningError(
            'This Coordinator has no Firebase identity. Keep the application pending.'
        )
    ensure_initialized()
    firebase_auth.update_user(user.firebase_uid, disabled=disabled)
    if disabled:
        firebase_auth.revoke_refresh_tokens(user.firebase_uid)
    return True


def provision_user(
    *,
    email,
    first_name,
    last_name,
    role,
    club=None,
    middle_initial='',
    mobile_number='',
    created_identities=None,
):
    """Create a Firebase account (if needed) and a linked local User.

    For Coach and Guardian app users who authenticate via Firebase.
    `club` scopes the account to a tenant (None for cross-club ADMIN accounts).

    Returns (user, temporary_password_or_None, note). Unlinked pre-existing
    Firebase identities are rejected to prevent account pre-hijacking.
    """
    if role not in (Roles.COACH, Roles.GUARDIAN):
        raise ProvisioningError(
            'This provisioning path supports Coach and Guardian app accounts only.'
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
        middle_initial=(middle_initial or '').strip().rstrip('.').upper(),
        last_name=last_name,
        mobile_number=mobile_number,
        role=role,
        club=club,
    )
    temp_password = link_or_create_firebase_user(user)
    if temp_password is not None and created_identities is not None:
        created_identities.append(user.firebase_uid)

    try:
        with transaction.atomic():
            user.save()
    except Exception:
        # Compensation: if we just CREATED the Firebase account, delete it so a
        # DB failure never leaves an orphaned identity (audit checklist item 5).
        # An idempotently re-linked account (temp_password is None) is left alone.
        if created_identities is None and temp_password is not None and user.firebase_uid:
            try:
                firebase_auth.delete_user(user.firebase_uid)
            except Exception:
                pass  # best-effort cleanup; surface the original DB error
        raise

    note = (
        'New Firebase account created.'
        if temp_password
        else 'Existing linked Firebase account verified.'
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
    *,
    first_name,
    last_name,
    middle_initial,
    date_of_birth,
    club,
    guardian,
):
    """Create one valid PLAYER aggregate in a single transaction.

    Every player creation path calls this service. It derives the age/tier,
    creates exactly one managed User and PlayerProfile, and creates the
    same-club GuardianLink. Players deliberately receive no Firebase identity,
    email credential, or usable Django password.
    """
    from academy.models import AgeTierSetting, PlayerProfile

    club = _require_active_club(club, role=Roles.PLAYER)
    if guardian is None or guardian.role != Roles.GUARDIAN or not guardian.is_active:
        raise ProvisioningError('The selected guardian must be active and have the Guardian role.')
    if guardian.club_id != club.id:
        raise ProvisioningError('Guardian and player must belong to the same club.')

    note = 'Managed player profile created without an independent login.'
    with transaction.atomic():
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
        GuardianLink.objects.create(guardian=guardian, player=user)

    return user, profile, None, note


# Roles an account may be switched between after creation. PLAYER is excluded
# (a player is created together with their profile by a dedicated flow, and
# the profile depends on the role) and COORDINATOR is excluded (a coordinator
# owns their club).
SWITCHABLE_ROLES = (Roles.COACH, Roles.GUARDIAN)


def change_role(user, new_role):
    """Switch an existing Firebase account between Coach and Guardian."""
    if user.is_superuser or user.role == Roles.ADMIN:
        raise ProvisioningError('Admin accounts cannot be changed here.')
    if user.role == Roles.PLAYER or hasattr(user, 'player_profile'):
        raise ProvisioningError(
            'Player accounts keep the PLAYER role — their profile depends on it.'
        )
    if user.role == Roles.COORDINATOR:
        raise ProvisioningError('A coordinator owns their club and cannot change role.')
    if new_role not in SWITCHABLE_ROLES:
        raise ProvisioningError(f'Accounts cannot be switched to {new_role}.')
    _require_active_club(user.club, role=new_role)
    if user.role == Roles.GUARDIAN and new_role != Roles.GUARDIAN and user.guardian_links.exists():
        raise ProvisioningError("Remove this guardian's player links before changing their role.")

    user.role = new_role
    user.save()
    return None, 'Their existing app password is unchanged.'


def provision_web_user(*, email, first_name, last_name, role, club, password=None, is_active=True):
    """Create a Coordinator with a usable Django portal password.

    Returns (user, password) — the caller relays `password` to the person
    (the one supplied, or a generated temporary one).
    """
    if role != Roles.COORDINATOR:
        raise ProvisioningError('This provisioning path supports Club Coordinators only.')
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
    """Create a dual-login Coordinator, disabled everywhere while pending."""
    club = _require_active_club(club, role=Roles.COORDINATOR)
    if User.objects.filter(club=club, role=Roles.COORDINATOR).exists():
        raise ProvisioningError('This club already has a coordinator.')
    user, generated = provision_web_user(
        email=email,
        first_name=first_name,
        last_name=last_name,
        role=Roles.COORDINATOR,
        club=club,
        password=password,
        is_active=is_active,
    )
    provision_coordinator_firebase_identity(
        user,
        password=generated,
        disabled=not is_active,
    )
    return user, generated
