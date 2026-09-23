"""Server-authoritative tournament roster eligibility policy."""

from dataclasses import dataclass

from django.db.models import Prefetch, Q

from .models import (
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    PlayerProfile,
    TournamentSquad,
)


@dataclass(frozen=True)
class RosterEligibility:
    state: str
    code: str
    reason: str

    @property
    def blocked(self):
        return self.state == 'BLOCKED'


ELIGIBLE = RosterEligibility('ELIGIBLE', 'ELIGIBLE', 'Eligible for this bracket.')
ROSTER_ELIGIBILITY_INJURIES_ATTR = 'roster_eligibility_injuries'


def roster_eligibility_injury_prefetch(lookup='injury_records'):
    """Return a filtered prefetch for injuries relevant to roster eligibility.

    ``to_attr`` keeps this filtered collection separate from the model's normal
    ``injury_records`` manager, so other callers never mistake it for the full
    injury history.
    """
    relevant_injuries = InjuryRecord.objects.filter(
        Q(review_status=InjuryReportStatus.PENDING)
        | Q(
            review_status=InjuryReportStatus.CONFIRMED,
            status__in=(InjuryStatus.ACTIVE, InjuryStatus.RECOVERING),
        )
    ).only('id', 'player_id', 'review_status', 'status')
    return Prefetch(
        lookup,
        queryset=relevant_injuries,
        to_attr=ROSTER_ELIGIBILITY_INJURIES_ATTR,
    )


def _eligibility_injuries(player):
    """Use batch-loaded injury data, with one-query fallback for single reads."""
    prefetched = getattr(player, ROSTER_ELIGIBILITY_INJURIES_ATTR, None)
    if prefetched is not None:
        return prefetched
    return list(
        InjuryRecord.objects.filter(player=player)
        .filter(
            Q(review_status=InjuryReportStatus.PENDING)
            | Q(
                review_status=InjuryReportStatus.CONFIRMED,
                status__in=(InjuryStatus.ACTIVE, InjuryStatus.RECOVERING),
            )
        )
        .only('id', 'player_id', 'review_status', 'status')
    )


def roster_eligibility(player, bracket):
    """Return privacy-safe eligibility, preferring batch-loaded injury data."""
    try:
        profile = player.player_profile
    except PlayerProfile.DoesNotExist:
        return RosterEligibility('BLOCKED', 'PROFILE_REQUIRED', 'Player profile is incomplete.')
    if profile.date_of_birth is None:
        return RosterEligibility('BLOCKED', 'DOB_REQUIRED', 'Date of birth is required.')
    oldest_birth_year = bracket.schedule.starts_on.year - bracket.max_age
    if profile.date_of_birth.year < oldest_birth_year:
        return RosterEligibility(
            'BLOCKED',
            'OVERAGE',
            f'Overage for {bracket.label} in {bracket.schedule.starts_on.year}.',
        )
    injuries = _eligibility_injuries(player)
    if any(
        injury.review_status == InjuryReportStatus.CONFIRMED
        and injury.status in (InjuryStatus.ACTIVE, InjuryStatus.RECOVERING)
        for injury in injuries
    ):
        return RosterEligibility(
            'BLOCKED',
            'CONFIRMED_INJURY',
            'Unavailable because of a confirmed active or recovering injury.',
        )
    if any(injury.review_status == InjuryReportStatus.PENDING for injury in injuries):
        return RosterEligibility(
            'WARNING',
            'PENDING_INJURY',
            'Pending injury report - review before selection.',
        )
    return ELIGIBLE


def invalid_squad_entries(bracket):
    """Return stored entries that currently fail hard eligibility rules."""
    try:
        squad = bracket.squad
    except TournamentSquad.DoesNotExist:
        return []
    entries = getattr(squad, '_prefetched_objects_cache', {}).get('entries')
    if entries is None:
        entries = squad.entries.select_related('player__player_profile').prefetch_related(
            roster_eligibility_injury_prefetch('player__injury_records')
        )
    return [
        (entry, result)
        for entry in entries
        if (result := roster_eligibility(entry.player, bracket)).blocked
    ]
