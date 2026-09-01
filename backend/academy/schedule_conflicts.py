"""Timezone-aware tournament priority rules shared by every write surface."""

from django.db import transaction
from django.utils import timezone

from .models import (
    AuditLog,
    FixtureStatus,
    TournamentFixture,
    TrainingSession,
    TrainingSessionStatus,
)
from .notifications import (
    _recipients_for_session,
    notify_tournament_training_cancelled,
)


CANCELLATION_REASON = (
    'Automatically cancelled due to a tournament schedule conflict.'
)


def intervals_overlap(start_a, end_a, start_b, end_b):
    return start_a < end_b and end_a > start_b


def fixture_conflict_payload(fixture):
    local_start = timezone.localtime(fixture.kickoff_at)
    local_end = timezone.localtime(fixture.effective_ends_at)
    start_label = local_start.strftime('%I:%M').lstrip('0')
    end_label = local_end.strftime('%I:%M %p').lstrip('0')
    return {
        'tournamentId': str(fixture.schedule_id),
        'tournament': fixture.schedule.title,
        'fixtureId': str(fixture.id),
        'bracket': fixture.age_bracket.label,
        'academyTiers': list(fixture.age_bracket.academy_tiers),
        'stage': fixture.stage,
        'opponent': fixture.opponent,
        'startsAt': local_start.isoformat(),
        'endsAt': local_end.isoformat(),
        'message': (
            f'This session conflicts with {fixture.schedule.title} — '
            f'{fixture.age_bracket.label} {fixture.stage} on '
            f'{local_start:%B %d}, {start_label}–{end_label}. '
            'Choose another time or remove the affected tier.'
        ),
    }


def conflicting_fixture_for_training(*, club_id, tiers, start, end):
    # Legacy sessions may not have clock times. They remain editable and are
    # outside interval-based enforcement until the Coach supplies both times.
    if start is None or end is None:
        return None
    fixtures = TournamentFixture.objects.select_related(
        'schedule', 'age_bracket',
    ).filter(
        schedule__club_id=club_id,
        schedule__is_published=True,
        status__in=(FixtureStatus.SCHEDULED, FixtureStatus.POSTPONED),
        kickoff_at__lt=end,
        ends_at__gt=start,
    ).order_by('kickoff_at', 'id')
    tier_set = set(tiers)
    return next(
        (
            fixture for fixture in fixtures
            if tier_set.intersection(fixture.age_bracket.academy_tiers)
        ),
        None,
    )


def training_conflicts_for_training(*, club_id, tiers, location, start, end, exclude_id=None):
    """Return all non-tournament booking conflicts for a proposed session."""
    if start is None or end is None:
        return []
    sessions = TrainingSession.objects.filter(
        club_id=club_id, status=TrainingSessionStatus.SCHEDULED, date=start.date(),
    )
    if exclude_id:
        sessions = sessions.exclude(pk=exclude_id)
    conflicts = []
    for session in sessions.select_for_update():
        other_start, other_end = session.interval()
        if other_start is None or not intervals_overlap(start, end, other_start, other_end):
            continue
        same_tier = bool(set(tiers).intersection(session.age_tiers))
        same_location = bool(location.strip()) and location.strip().casefold() == session.location.strip().casefold()
        if same_tier or same_location:
            conflicts.append({
                'type': 'SAME_AGE_TIERS' if same_tier else 'LOCATION',
                'title': session.title, 'ageTiers': session.age_tiers,
                'date': session.date.isoformat(), 'startTime': session.start_time,
                'endTime': session.end_time, 'location': session.location,
            })
    return conflicts


def conflicting_training_for_fixtures(fixtures, *, lock=False):
    """Return one authoritative fixture conflict per cancellable session."""
    fixtures = [
        fixture for fixture in fixtures
        if fixture.status in (FixtureStatus.SCHEDULED, FixtureStatus.POSTPONED)
        and fixture.age_bracket_id
        and fixture.age_bracket.academy_tiers
    ]
    if not fixtures:
        return []
    now = timezone.now()
    sessions = TrainingSession.objects.filter(
        club_id=fixtures[0].schedule.club_id,
        status=TrainingSessionStatus.SCHEDULED,
        date__gte=timezone.localdate(),
    )
    if lock:
        sessions = sessions.select_for_update()
    conflicts = []
    for session in sessions:
        session_start, session_end = session.interval()
        if session_start is None or session_start <= now:
            continue
        for fixture in fixtures:
            if not set(session.age_tiers).intersection(
                fixture.age_bracket.academy_tiers
            ):
                continue
            if intervals_overlap(
                session_start,
                session_end,
                fixture.kickoff_at,
                fixture.effective_ends_at,
            ):
                conflicts.append((session, fixture))
                break
    return conflicts


def cancellation_preview(fixtures):
    conflicts = conflicting_training_for_fixtures(fixtures)
    return {
        'count': len(conflicts),
        'sessions': [
            {
                'id': str(session.id),
                'title': session.title,
                'date': session.date.isoformat(),
                'startTime': session.start_time,
                'endTime': session.end_time,
                'ageTiers': session.age_tiers,
                'fixture': fixture_conflict_payload(fixture),
            }
            for session, fixture in conflicts
        ],
    }


def cancel_conflicting_training(fixtures, *, actor, action):
    """Lock and cancel conflicts once. Call inside the tournament transaction."""
    conflicts = conflicting_training_for_fixtures(fixtures, lock=True)
    cancelled = []
    for session, fixture in conflicts:
        recipients = _recipients_for_session(session)
        session.status = TrainingSessionStatus.CANCELLED
        session.cancellation_reason = CANCELLATION_REASON
        session.conflicting_tournament_id = fixture.schedule_id
        session.conflicting_fixture_id = fixture.id
        session.cancelled_at = timezone.now()
        session.cancelled_by_action = action
        session.save(update_fields=[
            'status', 'cancellation_reason', 'conflicting_tournament_id',
            'conflicting_fixture_id', 'cancelled_at',
            'cancelled_by_action',
        ])
        AuditLog.record(
            actor,
            'session.tournament_conflict_cancelled',
            target=session.title,
            detail=(
                f'tournament={fixture.schedule_id}; fixture={fixture.id}; '
                f'action={action}'
            ),
        )
        transaction.on_commit(
            lambda session=session, fixture=fixture, recipients=recipients:
            notify_tournament_training_cancelled(
                session,
                fixture,
                user_ids=recipients,
            )
        )
        cancelled.append((session, fixture))
    return cancelled
