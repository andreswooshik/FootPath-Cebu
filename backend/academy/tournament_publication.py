"""One publication workflow for REST and portal adapters."""

from django.db import transaction
from django.utils import timezone

from accounts.models import Club, Roles
from config.application_errors import ForbiddenOperation, InvalidOperation, MissingResource

from .errors import WorkflowConflict
from .models import AuditLog, TournamentFixture, TournamentSchedule
from .schedule_conflicts import (
    cancel_conflicting_training,
    conflicting_training_for_fixtures,
    fixture_conflict_payload,
)


def training_cancellation_details(conflicts):
    """Builds the conflict response listing training sessions affected by a fixture."""
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


@transaction.atomic
def publish_tournament(*, actor, schedule_id, confirm_cancellations=False):
    if actor.role != Roles.COORDINATOR or actor.club_id is None:
        raise ForbiddenOperation('Only club Coordinators may publish tournaments.')
    Club.objects.select_for_update().get(pk=actor.club_id)
    try:
        schedule = (
            TournamentSchedule.objects.select_related('club', 'uploaded_by')
            .select_for_update(of=('self',))
            .get(pk=schedule_id, club_id=actor.club_id)
        )
    except TournamentSchedule.DoesNotExist as exc:
        raise MissingResource() from exc
    errors = schedule.publication_errors()
    if errors:
        raise InvalidOperation(errors)
    if schedule.is_published:
        return schedule
    fixtures = list(
        TournamentFixture.objects.select_for_update(of=('self',))
        .select_related(
            'schedule',
            'age_bracket',
        )
        .filter(schedule=schedule)
    )
    conflicts = conflicting_training_for_fixtures(fixtures, lock=True)
    if conflicts and not confirm_cancellations:
        raise WorkflowConflict(
            'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
            'Publishing this tournament will cancel conflicting future '
            'training sessions. Confirm to continue.',
            cancellation=training_cancellation_details(conflicts),
        )
    schedule.is_published = True
    schedule.published_at = timezone.now()
    schedule.save(
        update_fields=[
            'is_published',
            'published_at',
            'updated_at',
        ]
    )
    cancel_conflicting_training(
        fixtures,
        actor=actor,
        action='tournament.published',
    )
    AuditLog.record(
        actor,
        'tournament.published',
        target=schedule.title,
        detail=str(schedule.starts_on),
    )
    return schedule
