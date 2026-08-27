"""Pure aggregation helpers for historical player match performances."""
from decimal import Decimal, ROUND_HALF_UP


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
