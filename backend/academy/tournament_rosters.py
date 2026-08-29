"""Server-authoritative tournament roster eligibility policy."""

from dataclasses import dataclass

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


def roster_eligibility(player, bracket):
    """Return eligibility without exposing DOB or injury descriptions."""
    try:
        profile = player.player_profile
    except PlayerProfile.DoesNotExist:
        return RosterEligibility(
            'BLOCKED', 'PROFILE_REQUIRED', 'Player profile is incomplete.'
        )
    if profile.date_of_birth is None:
        return RosterEligibility(
            'BLOCKED', 'DOB_REQUIRED', 'Date of birth is required.'
        )
    oldest_birth_year = bracket.schedule.starts_on.year - bracket.max_age
    if profile.date_of_birth.year < oldest_birth_year:
        return RosterEligibility(
            'BLOCKED',
            'OVERAGE',
            f'Overage for {bracket.label} in {bracket.schedule.starts_on.year}.',
        )
    injuries = InjuryRecord.objects.filter(player=player)
    if injuries.filter(
        review_status=InjuryReportStatus.CONFIRMED,
        status__in=(InjuryStatus.ACTIVE, InjuryStatus.RECOVERING),
    ).exists():
        return RosterEligibility(
            'BLOCKED',
            'CONFIRMED_INJURY',
            'Unavailable because of a confirmed active or recovering injury.',
        )
    if injuries.filter(review_status=InjuryReportStatus.PENDING).exists():
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
    return [
        (entry, result)
        for entry in squad.entries.select_related('player__player_profile')
        if (result := roster_eligibility(entry.player, bracket)).blocked
    ]
