"""Versioned, game-style Player Stats catalogs (kept separate from development)."""

from django.core.exceptions import ValidationError


CATALOG_VERSION = 1
CATALOGS = {
    'GOALKEEPER': ('Diving', 'Handling', 'Kicking', 'Reflexes', 'Speed', 'Positioning'),
    'DEFENDER': ('Pace', 'Tackling', 'Marking', 'Positioning', 'Passing', 'Physical'),
    'MIDFIELDER': ('Pace', 'Passing', 'Dribbling', 'Vision', 'Defending', 'Physical'),
    'ATTACKER': ('Pace', 'Shooting', 'Dribbling', 'Off-ball Movement', 'Passing', 'Physical'),
}
POSITION_GROUPS = {
    'GK': 'GOALKEEPER', 'CB': 'DEFENDER', 'LB': 'DEFENDER', 'RB': 'DEFENDER',
    'CDM': 'MIDFIELDER', 'CM': 'MIDFIELDER', 'CAM': 'MIDFIELDER',
    'LW': 'ATTACKER', 'RW': 'ATTACKER', 'ST': 'ATTACKER',
}


def role_group_for(position):
    try:
        return POSITION_GROUPS[str(position or '').upper()]
    except KeyError as exc:
        raise ValidationError({'position': 'Choose a supported player position first.'}) from exc


def catalog_for(position, version=CATALOG_VERSION):
    if int(version) != CATALOG_VERSION:
        raise ValidationError({'catalogVersion': 'This Player Stats catalog version is not supported.'})
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
            raise ValidationError({
                'scores': f'{key}: enter a whole number from 0 to 99.'
            })
        cleaned[key] = value
    return cleaned


def overall(scores):
    # Ratings are non-negative integers; add half a six-point unit so .5
    # always rounds upward (Python's built-in round uses bankers' rounding).
    return (sum(scores.values()) + 3) // 6
