"""Portal use-cases (application layer).

All tenancy rules, provisioning orchestration and transactions live here so the
views stay thin and the logic is testable without HTTP. Every account is
stamped with the caller's club server-side; cross-club links are rejected as
defence in depth (the forms already scope their pickers).
"""
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.utils.text import slugify

from academy.models import AgeTierSetting, PlayerProfile
from accounts.models import Club, GuardianLink, Roles
from accounts.services import provision_user, provision_web_user


def _unique_club_slug(name):
    base = slugify(name) or 'club'
    slug = base
    counter = 2
    while Club.objects.filter(slug=slug).exists():
        slug = f'{base}-{counter}'
        counter += 1
    return slug


@transaction.atomic
def register_coordinator(
    *, first_name, last_name, email, club_name, password,
    is_school_affiliated=False, school_name='', head_coach_name='',
    coach_license=None, cvfa_membership='',
):
    """Create a club (with its registration details) and its pending
    coordinator (is_active=False until a superadmin approves). Returns
    (user, club)."""
    club = Club.objects.create(
        name=club_name,
        slug=_unique_club_slug(club_name),
        is_school_affiliated=is_school_affiliated,
        school_name=school_name,
        head_coach_name=head_coach_name,
        coach_license=coach_license,
        cvfa_membership=cvfa_membership,
    )
    user, _password = provision_web_user(
        email=email,
        first_name=first_name,
        last_name=last_name,
        role=Roles.COORDINATOR,
        club=club,
        password=password,
        is_active=False,
    )
    return user, club


@transaction.atomic
def create_club_account(*, account_type, club, data):
    """Provision one club-scoped account.

    Returns (user, credential) where credential is the one-time password to
    relay: a Firebase temp password for app users (player/coach/guardian) or a
    Django password for web users (school staff).
    """
    if account_type == 'coach':
        user, temp_password, _ = provision_user(
            email=data['email'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            role=Roles.COACH,
            club=club,
        )
        return user, temp_password

    if account_type == 'staff':
        # School staff exist only for school-affiliated clubs (defence in depth
        # — the view also hides the tab and drops the form).
        if not club.is_school_affiliated:
            raise PermissionDenied('This club is not affiliated with a school.')
        return provision_web_user(
            email=data['email'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            role=Roles.SCHOOL_STAFF,
            club=club,
        )

    if account_type == 'player':
        user, temp_password, _ = provision_user(
            email=data['email'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            role=Roles.PLAYER,
            club=club,
        )
        # Place the player by the Admin-configured tier bands — same
        # derivation as the console's Add Player flow.
        age, tier = AgeTierSetting.profile_defaults_for(data['date_of_birth'])
        PlayerProfile.objects.create(
            user=user,
            middle_initial=data.get('middle_initial', ''),
            date_of_birth=data['date_of_birth'],
            age=age,
            age_tier=tier,
        )
        guardian = data.get('guardian')
        if guardian is not None:
            _assert_same_club(guardian, club)
            GuardianLink.objects.create(guardian=guardian, player=user)
        return user, temp_password

    if account_type == 'guardian':
        user, temp_password, _ = provision_user(
            email=data['email'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            role=Roles.GUARDIAN,
            club=club,
        )
        player = data.get('player')
        if player is not None:
            _assert_same_club(player, club)
            GuardianLink.objects.create(guardian=user, player=player)
        return user, temp_password

    raise ValueError(f'Unknown account type: {account_type!r}')


def set_player_eligibility(*, staff, player_profile, new_status):
    """Apply a school-staff eligibility change.

    The PlayerProfile save-cycle signal (academy.signals) records the append-only
    EligibilityHistory row and fires the push; we only enforce the club boundary,
    stash the acting user, and save.
    """
    if player_profile.user.club_id != staff.club_id:
        raise PermissionDenied('That player is not in your club.')
    player_profile.eligibility = new_status
    player_profile._changed_by = staff
    player_profile.save(update_fields=['eligibility'])
    return player_profile


def _assert_same_club(user, club):
    if user.club_id != club.id:
        raise PermissionDenied('That account is not in your club.')
