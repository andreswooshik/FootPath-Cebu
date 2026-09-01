"""Shared tournament-result transaction used by the API and web portal."""

from django.core.exceptions import ValidationError
from django.utils import timezone

from accounts.models import Roles, User

from .models import (
    AuditLog,
    FixtureStatus,
    FootballMatch,
    MatchCategory,
    PlayerMatchPerformance,
    TournamentSquad,
    TournamentSquadStatus,
)
from .tournament_rosters import roster_eligibility


def complete_tournament_fixture(*, fixture, actor, payload):
    """Complete a locked, tenant-scoped fixture and return its match."""
    if fixture.completed_match_id or fixture.status == FixtureStatus.COMPLETED:
        raise ValidationError({
            'fixture': 'This fixture already has a recorded result.'
        })
    if fixture.status != FixtureStatus.SCHEDULED:
        raise ValidationError({
            'fixture': 'Only a scheduled fixture can record a result.'
        })
    if not fixture.schedule.is_published:
        raise ValidationError({
            'fixture': 'Publish the tournament before recording a result.'
        })
    if fixture.age_bracket_id is None:
        raise ValidationError({
            'fixture': 'The fixture needs an age bracket before recording.'
        })
    if fixture.opponent.strip().upper() == 'TBD':
        raise ValidationError({
            'fixture': 'Set the opponent before recording a result.'
        })
    kickoff = fixture.kickoff_at
    played_on = (
        timezone.localtime(kickoff).date()
        if timezone.is_aware(kickoff)
        else kickoff.date()
    )
    if played_on > timezone.localdate():
        raise ValidationError({
            'fixture': 'A result can be recorded only after match day.'
        })

    squad = TournamentSquad.objects.select_for_update().filter(
        bracket_id=fixture.age_bracket_id,
        status=TournamentSquadStatus.PUBLISHED,
    ).first()
    if squad is None:
        raise ValidationError({
            'participants': (
                'The Coach must publish this age bracket\'s squad first.'
            )
        })
    participant_rows = payload['participants']
    player_ids = [row['playerId'] for row in participant_rows]
    squad_player_ids = set(
        squad.entries.filter(player_id__in=player_ids)
        .values_list('player_id', flat=True)
    )
    if set(player_ids) - squad_player_ids:
        raise ValidationError({
            'participants': (
                'Every participant must belong to the published squad.'
            )
        })
    players = {
        player.id: player
        for player in User.objects.filter(
            id__in=player_ids,
            role=Roles.PLAYER,
            club_id=actor.club_id,
            is_active=True,
        ).select_related('player_profile')
    }
    if len(players) != len(set(player_ids)):
        raise ValidationError({
            'participants': 'A participant is not an active club player.'
        })
    if any(
        roster_eligibility(player, fixture.age_bracket).blocked
        for player in players.values()
    ):
        raise ValidationError({
            'participants': 'One or more selected players are unavailable.'
        })

    match = FootballMatch.objects.create(
        club=actor.club,
        opponent=fixture.opponent,
        competition=fixture.schedule.title,
        played_on=played_on,
        venue=fixture.venue,
        category=MatchCategory.TOURNAMENT,
        our_score=payload['ourScore'],
        opponent_score=payload['opponentScore'],
        created_by=actor,
    )
    for row in participant_rows:
        PlayerMatchPerformance.objects.create(
            match=match,
            player=players[row['playerId']],
            recorded_by=actor,
            **row['statistics'],
        )
    fixture.completed_match = match
    fixture.status = FixtureStatus.COMPLETED
    fixture.save(update_fields=['completed_match', 'status', 'updated_at'])
    AuditLog.record(
        actor,
        'tournament.fixture_result_recorded',
        target=f'{fixture.schedule.title} vs {fixture.opponent}',
        detail=(
            f'{match.our_score}-{match.opponent_score} | '
            f'{len(participant_rows)} participants'
        ),
    )
    return match
