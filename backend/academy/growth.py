"""Transparent, independently testable Player Growth calculations."""
from collections import defaultdict
from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP

from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework.exceptions import ValidationError

from .match_statistics import build_performance_summary


IMPROVING = 'IMPROVING'
STABLE = 'STABLE'
NEEDS_ATTENTION = 'NEEDS_ATTENTION'
INSUFFICIENT_DATA = 'INSUFFICIENT_DATA'


def resolve_growth_filter(params, *, today=None):
    """Validate one shared range/date/category contract for every section."""
    today = today or timezone.localdate()
    range_name = str(params.get('range', 'last10')).lower()
    aliases = {'last_5': 'last5', 'last_10': 'last10'}
    range_name = aliases.get(range_name, range_name)
    allowed = {'last5', 'last10', 'last30days', 'last90days', 'all'}
    if range_name not in allowed:
        raise ValidationError({'range': 'Use last5, last10, last30days, last90days, or all.'})

    from_date = None
    to_date = None
    if params.get('from'):
        from_date = parse_date(params['from'])
        if from_date is None:
            raise ValidationError({'from': 'Use YYYY-MM-DD.'})
    if params.get('to'):
        to_date = parse_date(params['to'])
        if to_date is None:
            raise ValidationError({'to': 'Use YYYY-MM-DD.'})
    if from_date and to_date and from_date > to_date:
        raise ValidationError({'to': 'End date must not precede start date.'})

    if not from_date and range_name == 'last30days':
        from_date = today - timedelta(days=29)
    if not from_date and range_name == 'last90days':
        from_date = today - timedelta(days=89)
    if not to_date and (from_date or range_name in ('last30days', 'last90days')):
        to_date = today

    row_limit = {'last5': 5, 'last10': 10}.get(range_name)
    category = str(params.get('category', 'all')).lower().replace('-', '_')
    allowed_categories = {
        'all', 'assessment', 'training', 'regular_match', 'tournament'
    }
    if category not in allowed_categories:
        raise ValidationError({
            'category': (
                'Use assessment, training, regular_match, tournament, or all.'
            )
        })
    return {
        'range': range_name,
        'from': from_date,
        'to': to_date,
        'limit': row_limit,
        'category': category,
    }


def limited(rows, limit):
    values = list(rows)
    return values if limit is None else values[:limit]


def rounded_average(values, digits=1):
    clean = [Decimal(str(value)) for value in values if value is not None]
    if not clean:
        return None
    quantum = Decimal('1').scaleb(-digits)
    return float(
        (sum(clean, Decimal('0')) / len(clean)).quantize(
            quantum, rounding=ROUND_HALF_UP
        )
    )


def classify_delta(
    delta,
    *,
    recent_count,
    previous_count,
    threshold,
    lower_is_better=False,
    minimum_per_window=2,
):
    if (
        delta is None
        or recent_count < minimum_per_window
        or previous_count < minimum_per_window
    ):
        return INSUFFICIENT_DATA
    directed = -delta if lower_is_better else delta
    if directed >= threshold:
        return IMPROVING
    if directed <= -threshold:
        return NEEDS_ATTENTION
    return STABLE


def equal_windows(rows, value_getter):
    """Newest-first rows split into equal recent/previous comparison windows."""
    size = len(rows) // 2
    if size == 0:
        return [], []
    recent = [value_getter(row) for row in rows[:size]]
    previous = [value_getter(row) for row in rows[size:size * 2]]
    return recent, previous


def build_assessment_growth(snapshots):
    rows = list(snapshots)
    latest = rows[0] if rows else None
    previous = rows[1] if len(rows) > 1 else None
    attribute_names = (
        'pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical',
        'diving', 'handling', 'kicking', 'reflexes', 'speed', 'positioning',
    )
    deltas = {
        name: getattr(latest, name) - getattr(previous, name)
        for name in attribute_names
    } if previous else {}

    def overall(row):
        if row is None:
            return None
        names = attribute_names[6:] if row.position == 'GK' else attribute_names[:6]
        return round(sum(getattr(row, name) for name in names) / len(names))

    latest_overall = overall(latest)
    previous_overall = overall(previous)
    delta = (
        latest_overall - previous_overall
        if latest_overall is not None and previous_overall is not None
        else None
    )
    return {
        'sampleSize': len(rows),
        'latestOverall': latest_overall,
        'previousOverall': previous_overall,
        'overallDelta': delta,
        'attributeDeltas': deltas,
        'classification': classify_delta(
            delta,
            recent_count=1 if latest else 0,
            previous_count=1 if previous else 0,
            threshold=2,
            minimum_per_window=1,
        ),
    }


def build_training_groups(attendance_rows):
    groups = []
    by_focus = defaultdict(list)
    for row in attendance_rows:
        if row.session_id:
            by_focus[row.session.focus].append(row)
    for focus in ('TECHNICAL', 'PHYSICAL', 'MENTAL'):
        rows = by_focus[focus]
        present = [row for row in rows if row.status == 'PRESENT']
        recent_perf, previous_perf = equal_windows(
            [row for row in present if row.performance_score is not None],
            lambda row: row.performance_score,
        )
        recent_effort, previous_effort = equal_windows(
            [row for row in present if row.effort is not None],
            lambda row: row.effort,
        )
        recent_perf_avg = rounded_average(recent_perf)
        previous_perf_avg = rounded_average(previous_perf)
        perf_delta = (
            round(recent_perf_avg - previous_perf_avg, 1)
            if recent_perf_avg is not None and previous_perf_avg is not None
            else None
        )
        effort_recent_avg = rounded_average(recent_effort)
        effort_previous_avg = rounded_average(previous_effort)
        effort_delta = (
            round(effort_recent_avg - effort_previous_avg, 1)
            if effort_recent_avg is not None and effort_previous_avg is not None
            else None
        )
        # Prefer execution quality when it has two observations per window.
        # Legacy histories often have only effort, so fall back to that
        # independent scale instead of discarding an otherwise valid trend.
        performance_ready = (
            perf_delta is not None
            and len(recent_perf) >= 2
            and len(previous_perf) >= 2
        )
        effort_ready = (
            effort_delta is not None
            and len(recent_effort) >= 2
            and len(previous_effort) >= 2
        )
        if performance_ready or not effort_ready:
            comparison_metric = 'PERFORMANCE_SCORE'
            comparison_delta = perf_delta
            recent_count = len(recent_perf)
            previous_count = len(previous_perf)
            threshold = 0.3
        else:
            comparison_metric = 'EFFORT'
            comparison_delta = effort_delta
            recent_count = len(recent_effort)
            previous_count = len(previous_effort)
            threshold = 3.0
        groups.append({
            'focus': focus,
            'sampleSize': len(rows),
            'presentCount': len(present),
            'attendanceRate': round(len(present) * 100 / len(rows), 1) if rows else None,
            'averageEffort': rounded_average([row.effort for row in present]),
            'averagePerformanceScore': rounded_average([
                row.performance_score for row in present
            ]),
            'comparison': {
                'metric': comparison_metric,
                'recentSampleSize': recent_count,
                'previousSampleSize': previous_count,
                'performanceDelta': perf_delta,
                'effortDelta': effort_delta,
                'classification': classify_delta(
                    comparison_delta,
                    recent_count=recent_count,
                    previous_count=previous_count,
                    threshold=threshold,
                ),
            },
        })
    return groups


def per_90(total, minutes):
    return None if not minutes else round(total * 90 / minutes, 2)


def percentage(numerator, denominator):
    return None if not denominator else round(numerator * 100 / denominator, 1)


def match_metrics(rows):
    rows = list(rows)
    summary = build_performance_summary(rows)
    minutes = summary['minutesPlayed']
    return {
        **summary,
        'goalsPer90': per_90(summary['goals'], minutes),
        'assistsPer90': per_90(summary['assists'], minutes),
        'tacklesInterceptionsPer90': per_90(
            summary['tackles'] + summary['interceptions'], minutes
        ),
        'savesPer90': per_90(summary['saves'], minutes),
        'goalsConcededPer90': per_90(summary['goalsConceded'], minutes),
        'cardsPer90': per_90(
            summary['yellowCards'] + summary['redCards'], minutes
        ),
        'shotsOnTargetRate': percentage(
            summary['shotsOnTarget'], summary['shots']
        ),
    }


def build_match_growth(rows):
    rows = list(rows)
    size = len(rows) // 2
    recent = rows[:size]
    previous = rows[size:size * 2]
    recent_metrics = match_metrics(recent)
    previous_metrics = match_metrics(previous)
    rules = {
        'averageRating': (0.3, False),
        'goalsPer90': (0.1, False),
        'assistsPer90': (0.1, False),
        'passCompletionRate': (2.0, False),
        'shotsOnTargetRate': (2.0, False),
        'tacklesInterceptionsPer90': (0.2, False),
        'savesPer90': (0.2, False),
        'goalsConcededPer90': (0.2, True),
        'cardsPer90': (0.1, True),
    }
    comparisons = {}
    for name, (threshold, lower_is_better) in rules.items():
        recent_value = recent_metrics.get(name)
        previous_value = previous_metrics.get(name)
        delta = (
            round(recent_value - previous_value, 2)
            if recent_value is not None and previous_value is not None
            else None
        )
        comparisons[name] = {
            'recent': recent_value,
            'previous': previous_value,
            'delta': delta,
            'classification': classify_delta(
                delta,
                recent_count=len(recent),
                previous_count=len(previous),
                threshold=threshold,
                lower_is_better=lower_is_better,
            ),
        }
    return {
        'sampleSize': len(rows),
        'summary': match_metrics(rows),
        'comparisonPeriod': {
            'recentSampleSize': len(recent),
            'previousSampleSize': len(previous),
        },
        'metrics': comparisons,
    }


def build_tournament_groups(rows):
    grouped = defaultdict(list)
    for row in rows:
        fixture = row.match.source_fixture
        bracket = fixture.age_bracket
        key = (fixture.schedule_id, fixture.age_bracket_id)
        grouped[key].append(row)

    result = []
    for rows in grouped.values():
        first = rows[0]
        fixture = first.match.source_fixture
        wins = sum(row.match.our_score > row.match.opponent_score for row in rows)
        draws = sum(row.match.our_score == row.match.opponent_score for row in rows)
        losses = len(rows) - wins - draws
        result.append({
            'tournamentId': str(fixture.schedule_id),
            'tournament': fixture.schedule.title,
            'ageBracketId': (
                str(fixture.age_bracket_id) if fixture.age_bracket_id else None
            ),
            'ageBracketLabel': (
                fixture.age_bracket.label if fixture.age_bracket_id else None
            ),
            'sampleSize': len(rows),
            'summary': match_metrics(rows),
            'teamRecord': {
                'wins': wins,
                'draws': draws,
                'losses': losses,
                'scope': 'PLAYER_FIXTURES',
            },
        })
    return sorted(result, key=lambda row: row['tournament'], reverse=True)
