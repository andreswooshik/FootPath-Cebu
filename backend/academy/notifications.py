"""FCM push fan-out via the Firebase Admin SDK.

The Admin SDK is initialized once by accounts.firebase.ensure_initialized (also
called eagerly in AccountsConfig.ready). These helpers collect recipients and
send; they never raise into the request path — a push failure must not fail the
write that triggered it.
"""
import logging

from firebase_admin import messaging

from accounts.firebase import ensure_initialized
from accounts.models import GuardianLink

from .models import DeviceToken, PlayerProfile

logger = logging.getLogger(__name__)


def _recipients_for_session(session):
    """User ids to notify about `session`: players whose tier is targeted, plus
    the guardians linked to those players."""
    tiers = session.age_tiers or []
    player_ids = set(
        PlayerProfile.objects.filter(age_tier__in=tiers)
        .values_list('user_id', flat=True)
    )
    guardian_ids = set(
        GuardianLink.objects.filter(player_id__in=player_ids)
        .values_list('guardian_id', flat=True)
    )
    return player_ids | guardian_ids


def notify_session_scheduled(session):
    """Push a 'new training session' notification to everyone concerned.

    Best-effort: logs and swallows all errors, prunes dead tokens.
    """
    try:
        ensure_initialized()
    except Exception as exc:  # SDK not configured (e.g. local dev)
        logger.info('Skipping push (Firebase unavailable): %s', exc)
        return 0

    user_ids = _recipients_for_session(session)
    tokens = list(
        DeviceToken.objects.filter(user_id__in=user_ids)
        .values_list('token', flat=True)
    )
    if not tokens:
        return 0

    tier_label = ', '.join(session.age_tiers or []) or 'all tiers'
    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(
            title='New training session',
            body=f'{session.title} on {session.date} · {tier_label}',
        ),
        data={'type': 'session_scheduled', 'sessionId': str(session.id)},
    )

    try:
        response = messaging.send_each_for_multicast(message)
    except Exception as exc:
        logger.warning('FCM send failed: %s', exc)
        return 0

    _prune_dead_tokens(tokens, response)
    return response.success_count


def _prune_dead_tokens(tokens, response):
    """Delete tokens Firebase reports as unregistered/invalid."""
    dead = []
    for token, result in zip(tokens, response.responses):
        if result.success:
            continue
        exc = result.exception
        code = getattr(exc, 'code', '') or ''
        if 'registration-token-not-registered' in str(code) or 'not-registered' in str(code):
            dead.append(token)
    if dead:
        DeviceToken.objects.filter(token__in=dead).delete()
