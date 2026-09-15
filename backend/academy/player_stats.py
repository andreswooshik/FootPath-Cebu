"""Versioned, game-style Player Stats catalogs (kept separate from development)."""

from django.core.exceptions import ValidationError
from django.db.models import Case, CharField, OuterRef, Subquery, Value, When

CATALOG_VERSION = 1
CATALOGS = {
    'GOALKEEPER': ('Diving', 'Handling', 'Kicking', 'Reflexes', 'Speed', 'Positioning'),
    'DEFENDER': ('Pace', 'Tackling', 'Marking', 'Positioning', 'Passing', 'Physical'),
    'MIDFIELDER': ('Pace', 'Passing', 'Dribbling', 'Vision', 'Defending', 'Physical'),
    'ATTACKER': ('Pace', 'Shooting', 'Dribbling', 'Off-ball Movement', 'Passing', 'Physical'),
}
POSITION_GROUPS = {
    'GK': 'GOALKEEPER',
    'CB': 'DEFENDER',
    'LB': 'DEFENDER',
    'RB': 'DEFENDER',
    'CDM': 'MIDFIELDER',
    'CM': 'MIDFIELDER',
    'CAM': 'MIDFIELDER',
    'LW': 'ATTACKER',
    'RW': 'ATTACKER',
    'ST': 'ATTACKER',
}


def with_latest_player_stats(queryset):
    """Annotate profiles with their latest current-catalog compatible stats.

    The correlated subqueries keep roster serialization bounded to one query
    without loading every historical assessment for every player.
    """
    from .model_players import PlayerStatsAssessment

    group_positions = {
        group: [
            position for position, mapped_group in POSITION_GROUPS.items() if mapped_group == group
        ]
        for group in CATALOGS
    }
    role_group = Case(
        *[
            When(position__in=positions, then=Value(group))
            for group, positions in group_positions.items()
        ],
        default=Value(''),
        output_field=CharField(),
    )
    latest = PlayerStatsAssessment.objects.filter(
        player_id=OuterRef('user_id'),
        role_group=OuterRef('_latest_player_stats_role_group'),
        catalog_version=CATALOG_VERSION,
    ).order_by('-created_at', '-id')
    return queryset.annotate(
        _latest_player_stats_role_group=role_group,
        _latest_player_stats_id=Subquery(latest.values('id')[:1]),
        _latest_player_stats_position=Subquery(latest.values('position')[:1]),
        _latest_player_stats_catalog_version=Subquery(latest.values('catalog_version')[:1]),
        _latest_player_stats_scores=Subquery(latest.values('scores')[:1]),
        _latest_player_stats_overall=Subquery(latest.values('overall')[:1]),
        _latest_player_stats_reason=Subquery(latest.values('reason')[:1]),
        _latest_player_stats_coach_notes=Subquery(latest.values('coach_notes')[:1]),
        _latest_player_stats_created_at=Subquery(latest.values('created_at')[:1]),
    )


def role_group_for(position):
    try:
        return POSITION_GROUPS[str(position or '').upper()]
    except KeyError as exc:
        raise ValidationError({'position': 'Choose a supported player position first.'}) from exc


def catalog_for(position, version=CATALOG_VERSION):
    if int(version) != CATALOG_VERSION:
        raise ValidationError(
            {'catalogVersion': 'This Player Stats catalog version is not supported.'}
        )
    group = role_group_for(position)
    return group, list(CATALOGS[group])


def score_keys(position, version=CATALOG_VERSION):
    _group, attributes = catalog_for(position, version)
    return [attribute.lower().replace(' ', '_').replace('-', '_') for attribute in attributes]


def normalized_scores(position, scores, version=CATALOG_VERSION):
    if not isinstance(scores, dict):
        raise ValidationError({'scores': 'Provide all six Player Stats scores.'})
    keys = score_keys(position, version)
    missing = [key for key in keys if key not in scores]
    extras = [key for key in scores if key not in keys]
    if missing or extras:
        detail = []
        if missing:
            detail.append(f'Missing: {", ".join(missing)}.')
        if extras:
            detail.append(f'Unknown: {", ".join(extras)}.')
        raise ValidationError({'scores': ' '.join(detail)})
    cleaned = {}
    for key in keys:
        value = scores[key]
        if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 99:
            raise ValidationError({'scores': f'{key}: enter a whole number from 0 to 99.'})
        cleaned[key] = value
    return cleaned


def overall(scores):
    # Ratings are non-negative integers; add half a six-point unit so .5
    # always rounds upward (Python's built-in round uses bankers' rounding).
    return (sum(scores.values()) + 3) // 6
