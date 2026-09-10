"""Persist an eligibility transition together with its signal-driven history."""

from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction

from accounts.models import Roles

from .models import Eligibility, PlayerProfile


@transaction.atomic
def change_eligibility(*, actor, player_id, new_status):
    if not actor.is_active or actor.role not in (Roles.ADMIN, Roles.SCHOOL_STAFF):
        raise PermissionDenied('Only reviewers can update eligibility.')
    profile = (
        PlayerProfile.objects.select_for_update(of=('self',))
        .select_related(
            'user__club',
        )
        .get(user_id=player_id)
    )
    club = profile.user.club
    if club is None or not club.is_active or not club.allows_academic_eligibility:
        raise PermissionDenied('Academic eligibility is unavailable for this club.')
    if actor.role != Roles.ADMIN and actor.club_id != club.pk:
        raise PermissionDenied('That player is not in your club.')
    if new_status not in Eligibility.values:
        raise ValidationError('Unknown eligibility status.')
    profile.eligibility = new_status
    profile._changed_by = actor
    profile.save(update_fields=['eligibility'])
    return profile
