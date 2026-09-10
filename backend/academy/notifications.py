"""Persist notification inbox entries and outbox jobs in the caller transaction.

Network delivery belongs to academy.push_delivery and its worker command.
"""

import logging
from uuid import uuid4

from django.db import transaction

from accounts.guardian_access import valid_guardian_links
from accounts.models import Roles, User

from .models import NotificationRecord, PlayerProfile, PushOutbox

logger = logging.getLogger(__name__)


def _recipients_for_session(session):
    """User ids to notify about `session`: players in the session's club whose
    tier is targeted, plus the guardians linked to those players.

    Scoped to `session.club` so a club's new session never pushes to another
    club's players (multi-tenancy)."""
    tiers = session.age_tiers or []
    player_ids = set(
        PlayerProfile.objects.filter(age_tier__in=tiers, user__club_id=session.club_id).values_list(
            'user_id', flat=True
        )
    )
    guardian_ids = set(
        valid_guardian_links()
        .filter(player_id__in=player_ids)
        .values_list('guardian_id', flat=True)
    )
    return player_ids | guardian_ids


def _player_and_guardian_ids(player_id):
    """The player plus every guardian linked to them."""
    guardian_ids = set(
        valid_guardian_links(player_id=player_id).values_list('guardian_id', flat=True)
    )
    return {player_id} | guardian_ids


@transaction.atomic
def _send_to_users(user_ids, *, title, body, data):
    """Persist inbox records and delivery intent; never perform network I/O."""
    recipients = list(
        User.objects.filter(
            pk__in=set(user_ids),
            is_active=True,
        ).values_list('pk', flat=True)
    )
    if not recipients:
        return 0
    event_id = uuid4()
    payload = {**data, 'eventId': str(event_id)}
    NotificationRecord.objects.bulk_create(
        [
            NotificationRecord(
                user_id=user_id,
                event_type=str(data.get('type') or 'general')[:40],
                title=title[:120],
                body=body[:300],
                data=payload,
            )
            for user_id in recipients
        ]
    )
    PushOutbox.objects.create(
        event_id=event_id,
        user_ids=recipients,
        title=title[:120],
        body=body[:300],
        data=payload,
    )
    return 0


def notify_session_scheduled(session):
    """Push a 'new training session' notification to everyone concerned."""
    return _send_to_users(
        _recipients_for_session(session),
        title='New training session',
        body='Open FootPath Cebu to view the latest schedule.',
        data={'type': 'session_scheduled', 'sessionId': str(session.id)},
    )


def notify_session_updated(session):
    """Push after a coach edits a scheduled session (new time/place/etc.)."""
    return _send_to_users(
        _recipients_for_session(session),
        title='Training session updated',
        body='A training schedule was updated. Sign in to view the details.',
        data={'type': 'session_updated', 'sessionId': str(session.id)},
    )


def notify_session_cancelled(session, user_ids=None, session_id=None):
    """Push after a coach soft-cancels a retained training session."""
    return _send_to_users(
        user_ids if user_ids is not None else _recipients_for_session(session),
        title='Training session cancelled',
        body='A training session was cancelled. Sign in to view the schedule.',
        data={
            'type': 'session_cancelled',
            'sessionId': str(session_id if session_id is not None else session.id),
        },
    )


def notify_tournament_training_cancelled(session, fixture, user_ids=None):
    recipients = set(user_ids if user_ids is not None else _recipients_for_session(session))
    recipients.update(
        User.objects.filter(
            club_id=session.club_id,
            role=Roles.COACH,
            is_active=True,
        ).values_list('id', flat=True)
    )
    body = (
        f'{session.title} on {session.date:%B %d} at {session.start_time} was '
        f'cancelled because it conflicts with {fixture.schedule.title} '
        f'{fixture.stage}.'
    )
    return _send_to_users(
        recipients,
        title='Training Cancelled',
        body=body,
        data={
            'type': 'session_cancelled',
            'sessionId': str(session.id),
            'tournamentId': str(fixture.schedule_id),
            'fixtureId': str(fixture.id),
        },
    )


def notify_tournament_roster_published(squad):
    player_ids = set(squad.entries.values_list('player_id', flat=True))
    guardian_ids = set(
        valid_guardian_links()
        .filter(player_id__in=player_ids)
        .values_list('guardian_id', flat=True)
    )
    return _send_to_users(
        player_ids | guardian_ids,
        title='Tournament roster published',
        body=(
            f'The {squad.bracket.label} roster for {squad.bracket.schedule.title} is now available.'
        ),
        data={
            'type': 'tournament_roster_published',
            'tournamentId': str(squad.bracket.schedule_id),
            'bracketId': str(squad.bracket_id),
        },
    )


def notify_assessment_saved(profile):
    """Push to the assessed player + linked guardians after a coach saves the
    six-attribute assessment. Fires on the assessment save, not per-session
    attendance — a 20-player roll call must not send 20 pushes."""
    return _send_to_users(
        _player_and_guardian_ids(profile.user_id),
        title='Performance assessment updated',
        body='A performance assessment was updated. Sign in to view it.',
        data={'type': 'assessment_saved', 'playerId': str(profile.user_id)},
    )


def notify_eligibility_changed(profile, previous):
    """Push to the player + linked guardians when eligibility actually
    changes (wired via signals, so every write path fires it)."""
    return _send_to_users(
        _player_and_guardian_ids(profile.user_id),
        title='Eligibility updated',
        body='Academic eligibility status was updated. Sign in to view it.',
        data={
            'type': 'eligibility_changed',
            'playerId': str(profile.user_id),
        },
    )
