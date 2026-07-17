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


def _player_and_guardian_ids(player_id):
    """The player plus every guardian linked to them."""
    guardian_ids = set(
        GuardianLink.objects.filter(player_id=player_id)
        .values_list('guardian_id', flat=True)
    )
    return {player_id} | guardian_ids


def _player_display_name(profile):
    user = profile.user
    full = f'{user.first_name} {user.last_name}'.strip()
    return full or user.email.split('@')[0]


def _send_to_users(user_ids, *, title, body, data):
    """Fan one notification out to every device of `user_ids`.

    Best-effort: logs and swallows all errors, prunes dead tokens. Returns
    the number of successful sends.
    """
    try:
        ensure_initialized()
    except Exception as exc:  # SDK not configured (e.g. local dev)
        logger.info('Skipping push (Firebase unavailable): %s', exc)
        return 0

    tokens = list(
        DeviceToken.objects.filter(user_id__in=user_ids)
        .values_list('token', flat=True)
    )
    if not tokens:
        return 0

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data=data,
    )

    try:
        response = messaging.send_each_for_multicast(message)
    except Exception as exc:
        logger.warning('FCM send failed: %s', exc)
        return 0

    _prune_dead_tokens(tokens, response)
    return response.success_count


def notify_session_scheduled(session):
    """Push a 'new training session' notification to everyone concerned."""
    tier_label = ', '.join(session.age_tiers or []) or 'all tiers'
    return _send_to_users(
        _recipients_for_session(session),
        title='New training session',
        body=f'{session.title} on {session.date} · {tier_label}',
        data={'type': 'session_scheduled', 'sessionId': str(session.id)},
    )


def notify_assessment_saved(profile):
    """Push to the assessed player + linked guardians after a coach saves the
    six-attribute assessment. Fires on the assessment save, not per-session
    attendance — a 20-player roll call must not send 20 pushes."""
    return _send_to_users(
        _player_and_guardian_ids(profile.user_id),
        title='Performance assessment updated',
        body=f'New ratings were saved for {_player_display_name(profile)}.',
        data={'type': 'assessment_saved', 'playerId': str(profile.user_id)},
    )


def notify_eligibility_changed(profile, previous):
    """Push to the player + linked guardians when eligibility actually
    changes (wired via signals, so every write path fires it)."""
    return _send_to_users(
        _player_and_guardian_ids(profile.user_id),
        title='Eligibility updated',
        body=(
            f'{_player_display_name(profile)} is now '
            f'{profile.get_eligibility_display()}.'
        ),
        data={
            'type': 'eligibility_changed',
            'playerId': str(profile.user_id),
            'eligibility': profile.eligibility,
            'previous': previous or '',
        },
    )


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
