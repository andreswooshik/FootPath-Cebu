"""Pure aggregation helpers for historical player match performances."""

from decimal import ROUND_HALF_UP, Decimal

from django.db.models import Avg, Count, Q, Sum


def build_performance_summary(performances):
    """Return stable, JSON-ready totals for an already-authorized collection.

    Keeping aggregation free of request and serializer concerns makes the
    calculation independently testable and reusable by future reporting views.
    """
    rows = list(performances)
    attempted = sum(row.passes_attempted for row in rows)
    completed = sum(row.passes_completed for row in rows)
    ratings = [row.coach_rating for row in rows if row.coach_rating is not None]

    pass_completion = None
    if attempted:
        pass_completion = round(completed * 100 / attempted, 1)

    average_rating = None
    if ratings:
        average_rating = float(
            (sum(ratings, Decimal('0')) / len(ratings)).quantize(
                Decimal('0.1'), rounding=ROUND_HALF_UP
            )
        )

    return {
        'matchesPlayed': len(rows),
        'starts': sum(1 for row in rows if row.starter),
        'minutesPlayed': sum(row.minutes_played for row in rows),
        'goals': sum(row.goals for row in rows),
        'assists': sum(row.assists for row in rows),
        'shots': sum(row.shots for row in rows),
        'shotsOnTarget': sum(row.shots_on_target for row in rows),
        'passesAttempted': attempted,
        'passesCompleted': completed,
        'passCompletionRate': pass_completion,
        'tackles': sum(row.tackles for row in rows),
        'interceptions': sum(row.interceptions for row in rows),
        'yellowCards': sum(row.yellow_cards for row in rows),
        'redCards': sum(row.red_cards for row in rows),
        'saves': sum(row.saves for row in rows),
        'goalsConceded': sum(row.goals_conceded for row in rows),
        'cleanSheets': sum(1 for row in rows if row.clean_sheet),
        'averageRating': average_rating,
    }


def aggregate_performance_summary(queryset):
    """Build the same summary in SQL without materializing an unbounded history."""
    totals = queryset.aggregate(
        matches_played=Count('id'),
        starts=Count('id', filter=Q(starter=True)),
        minutes_played=Sum('minutes_played'),
        goals=Sum('goals'),
        assists=Sum('assists'),
        shots=Sum('shots'),
        shots_on_target=Sum('shots_on_target'),
        passes_attempted=Sum('passes_attempted'),
        passes_completed=Sum('passes_completed'),
        tackles=Sum('tackles'),
        interceptions=Sum('interceptions'),
        yellow_cards=Sum('yellow_cards'),
        red_cards=Sum('red_cards'),
        saves=Sum('saves'),
        goals_conceded=Sum('goals_conceded'),
        clean_sheets=Count('id', filter=Q(clean_sheet=True)),
        average_rating=Avg('coach_rating'),
    )
    attempted = totals['passes_attempted'] or 0
    completed = totals['passes_completed'] or 0
    average_rating = totals['average_rating']
    return {
        'matchesPlayed': totals['matches_played'],
        'starts': totals['starts'],
        'minutesPlayed': totals['minutes_played'] or 0,
        'goals': totals['goals'] or 0,
        'assists': totals['assists'] or 0,
        'shots': totals['shots'] or 0,
        'shotsOnTarget': totals['shots_on_target'] or 0,
        'passesAttempted': attempted,
        'passesCompleted': completed,
        'passCompletionRate': round(completed * 100 / attempted, 1) if attempted else None,
        'tackles': totals['tackles'] or 0,
        'interceptions': totals['interceptions'] or 0,
        'yellowCards': totals['yellow_cards'] or 0,
        'redCards': totals['red_cards'] or 0,
        'saves': totals['saves'] or 0,
        'goalsConceded': totals['goals_conceded'] or 0,
        'cleanSheets': totals['clean_sheets'],
        'averageRating': (
            float(
                Decimal(average_rating).quantize(
                    Decimal('0.1'),
                    rounding=ROUND_HALF_UP,
                )
            )
            if average_rating is not None
            else None
        ),
    }
