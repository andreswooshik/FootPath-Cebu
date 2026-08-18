"""Club-portal application services.

Every tenant decision starts from the authenticated coordinator/staff account.
No caller may supply an arbitrary club identifier.
"""
from django.core.exceptions import PermissionDenied
from django.db import transaction

from academy.models import Eligibility
from accounts.models import GuardianLink, Roles
from accounts.services import (
    ProvisioningError,
    provision_player,
    provision_user,
    provision_web_user,
)


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
