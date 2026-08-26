"""Club-portal application services.

Every tenant decision starts from the authenticated coordinator/staff account.
No caller may supply an arbitrary club identifier.
"""
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.utils.text import slugify

from academy.models import (
    AuditLog,
    Dispute,
    DisputeResponse,
    DisputeStatus,
    Eligibility,
)
from accounts.models import Club, GuardianLink, Roles
from accounts.services import (
    ProvisioningError,
    provision_club_coordinator,
    provision_player,
    provision_user,
    provision_web_user,
)


def _unique_club_slug(name):
    """Return a stable URL slug without colliding with an existing club."""
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
    """Create a club application and an inactive coordinator login.

    A Super Admin must approve the application before Django permits the
    coordinator to sign in. No Firebase/mobile identity is created here.
    """
    club = Club.objects.create(
        name=club_name,
        slug=_unique_club_slug(club_name),
        is_school_affiliated=is_school_affiliated,
        school_name=school_name,
        head_coach_name=head_coach_name,
        coach_license=coach_license,
        cvfa_membership=cvfa_membership,
    )
    user, _password = provision_club_coordinator(
        email=email,
        first_name=first_name,
        last_name=last_name,
        club=club,
        password=password,
        is_active=False,
    )
    return user, club


@transaction.atomic
def create_club_account(*, account_type, coordinator, data):
    """Provision an account inside the authenticated coordinator's club."""
    if coordinator.role != Roles.COORDINATOR or not coordinator.is_active:
        raise PermissionDenied('Only an active Club Coordinator can create accounts.')
    club = coordinator.club
    if club is None or not club.is_active:
        raise PermissionDenied('The coordinator must belong to an active club.')

    if account_type == 'coach':
        user, temporary_password, _note = provision_user(
            email=data['email'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            role=Roles.COACH,
            club=club,
        )
        return user, temporary_password

    if account_type == 'staff':
        if not club.allows_school_staff:
            raise PermissionDenied(
                'School Staff accounts are unavailable for an Independent club.'
            )
        return provision_web_user(
            email=data['email'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            role=Roles.SCHOOL_STAFF,
            club=club,
        )

    if account_type == 'player':
        user, _profile, temporary_password, _note = provision_player(
            email=data.get('email', ''),
            first_name=data['first_name'],
            last_name=data['last_name'],
            middle_initial=data.get('middle_initial', ''),
            date_of_birth=data['date_of_birth'],
            club=club,
            guardian=data.get('guardian'),
        )
        return user, temporary_password

    if account_type == 'guardian':
        player = data.get('player')
        if player is not None:
            _assert_same_club(player, club)
            if player.role != Roles.PLAYER or not player.is_active:
                raise ProvisioningError('The selected account must be an active Player.')
        user, temporary_password, _note = provision_user(
            email=data['email'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            role=Roles.GUARDIAN,
            club=club,
        )
        if player is not None:
            GuardianLink.objects.create(guardian=user, player=player)
        return user, temporary_password

    raise ProvisioningError(f'Unknown or unavailable account type: {account_type!r}')


def set_player_eligibility(*, staff, player_profile, new_status):
    """Apply one of the four approved status flags; never accept grades."""
    if staff.role != Roles.SCHOOL_STAFF or not staff.is_active:
        raise PermissionDenied('Only active School Staff can update eligibility.')
    if staff.club_id is None or not staff.club.allows_academic_eligibility:
        raise PermissionDenied(
            'Academic eligibility is not applicable to an Independent club.'
        )
    if player_profile.user.club_id != staff.club_id:
        raise PermissionDenied('That player is not in your club.')
    if new_status not in Eligibility.values:
        raise ProvisioningError('Unknown eligibility status.')
    player_profile.eligibility = new_status
    player_profile._changed_by = staff
    player_profile.save(update_fields=['eligibility'])
    return player_profile


def staff_dispute_queryset(*, staff):
    """Return only disputes raised inside the School Staff user's Club."""
    _assert_school_staff_access(staff)
    return (
        Dispute.objects.select_related('raised_by', 'subject_player')
        .prefetch_related('responses__author')
        .filter(raised_by__club_id=staff.club_id)
    )


@transaction.atomic
def respond_to_dispute(
    *, staff, dispute_id, body, status_change_to=None,
):
    """Append a response to one same-Club dispute and optionally change it.

    The parent row is locked so simultaneous responses cannot lose a status
    update. The response thread remains append-only.
    """
    _assert_school_staff_access(staff)
    dispute = (
        Dispute.objects.select_for_update()
        .filter(raised_by__club_id=staff.club_id)
        .get(pk=dispute_id)
    )
    new_status = status_change_to or None
    if new_status is not None and new_status not in DisputeStatus.values:
        raise ProvisioningError('Unknown dispute status.')

    response = DisputeResponse.objects.create(
        dispute=dispute,
        author=staff,
        body=body,
        status_change_to=new_status,
    )
    if new_status is not None:
        dispute.status = new_status
    # A thread response is activity even when its status stays the same.
    dispute.save(update_fields=['status', 'updated_at'])

    AuditLog.record(
        staff,
        'dispute.responded',
        target=f'Dispute #{dispute.pk}: {dispute.summary}',
        detail=(
            f'Status changed to {new_status}.'
            if new_status is not None else 'Response added; status unchanged.'
        ),
    )
    return response


def _assert_school_staff_access(staff):
    if staff.role != Roles.SCHOOL_STAFF or not staff.is_active:
        raise PermissionDenied('Only active School Staff can manage disputes.')
    if staff.club_id is None or not staff.club.is_active:
        raise PermissionDenied('School Staff must belong to an active club.')
    if not staff.club.allows_school_staff:
        raise PermissionDenied(
            'School Staff access is unavailable for an Independent club.'
        )


def link_guardian(*, coordinator, guardian, player):
    """Create a same-club Guardian-to-Player link."""
    if coordinator.role != Roles.COORDINATOR or not coordinator.is_active:
        raise PermissionDenied('Only an active Club Coordinator can manage links.')
    if coordinator.club_id is None or not coordinator.club.is_active:
        raise PermissionDenied('The coordinator must belong to an active club.')
    _assert_same_club(guardian, coordinator.club)
    _assert_same_club(player, coordinator.club)
    if guardian.role != Roles.GUARDIAN or player.role != Roles.PLAYER:
        raise PermissionDenied('A link requires a Guardian and a Player.')
    if not guardian.is_active or not player.is_active:
        raise PermissionDenied('Both accounts must be active.')
    return GuardianLink.objects.get_or_create(guardian=guardian, player=player)


def unlink_guardian(*, coordinator, link):
    """Remove a Guardian-to-Player link in the coordinator's own club."""
    if (
        coordinator.role != Roles.COORDINATOR
        or coordinator.club_id is None
        or link.guardian.club_id != coordinator.club_id
        or link.player.club_id != coordinator.club_id
    ):
        raise PermissionDenied('That link is not in your club.')
    link.delete()


def _assert_same_club(user, club):
    if club is None or user.club_id != club.id:
        raise PermissionDenied('That account is not in your club.')
