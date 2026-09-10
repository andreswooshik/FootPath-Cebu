"""Leased, retryable outbox delivery with bounded Firebase batches.

The worker never holds a database transaction during network I/O. Delivery
is at least once: a crash after FCM accepts a batch can repeat that batch.
The stable eventId allows clients to deduplicate; inbox rows are never recreated.
"""

import logging
from datetime import timedelta
from uuid import uuid4

from django.db import connection, transaction
from django.db.models import Q
from django.utils import timezone
from firebase_admin import messaging

from accounts.firebase import ensure_initialized

from .models import DeviceToken, PushOutbox

logger = logging.getLogger(__name__)
BATCH_SIZE = 500


class FirebasePushGateway:
    def send(self, *, tokens, title, body, data):
        ensure_initialized()
        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data=data,
        )
        return messaging.send_each_for_multicast(message)


@transaction.atomic
def _claim():
    now = timezone.now()
    jobs = (
        PushOutbox.objects.filter(
            completed_at__isnull=True,
            available_at__lte=now,
        )
        .filter(Q(lease_until__isnull=True) | Q(lease_until__lte=now))
        .order_by('id')
    )
    jobs = jobs.select_for_update(skip_locked=connection.features.has_select_for_update_skip_locked)
    job = jobs.first()
    if job is None:
        return None
    job.lease_id = uuid4()
    job.lease_until = now + timedelta(minutes=15)
    job.attempts += 1
    if job.pending_tokens is None:
        job.pending_tokens = dict(
            DeviceToken.objects.filter(
                user_id__in=job.user_ids,
                user__is_active=True,
            ).values_list('token', 'user_id')
        )
    job.save(update_fields=['lease_id', 'lease_until', 'attempts', 'pending_tokens'])
    return job


def _dead_token(error):
    code = str(getattr(error, 'code', '')).lower()
    return code in ('unregistered', 'registration-token-not-registered') or 'not-registered' in code


def deliver_pending(*, limit=100, gateway=None):
    """Process at most limit events and return the number of device successes."""
    gateway = gateway or FirebasePushGateway()
    sent = 0
    for _ in range(limit):
        job = _claim()
        if job is None:
            break
        owned_job = PushOutbox.objects.filter(pk=job.pk, lease_id=job.lease_id)
        pending = dict(job.pending_tokens)
        error_name = ''
        try:
            # A token reassigned to another account must not receive an old
            # account's notification. Recheck ownership on every retry.
            current = dict(
                DeviceToken.objects.filter(
                    token__in=pending,
                    user__is_active=True,
                ).values_list('token', 'user_id')
            )
            pending = {
                token: owner for token, owner in pending.items() if current.get(token) == owner
            }
            # Iterate a stable snapshot; successful tokens are removed below.
            tokens = list(pending)
            for start in range(0, len(tokens), BATCH_SIZE):
                batch = tokens[start : start + BATCH_SIZE]
                response = gateway.send(tokens=batch, title=job.title, body=job.body, data=job.data)
                if len(response.responses) != len(batch):
                    raise ValueError('Incomplete push delivery response')
                for token, result in zip(batch, response.responses, strict=True):
                    if result.success:
                        sent += 1
                        pending.pop(token, None)
                    elif _dead_token(result.exception):
                        DeviceToken.objects.filter(token=token, user_id=pending[token]).delete()
                        pending.pop(token, None)
                    else:
                        error_name = type(result.exception).__name__
                if not owned_job.update(
                    pending_tokens=pending, lease_until=timezone.now() + timedelta(minutes=15)
                ):
                    break
        except Exception as exc:
            # Store the exception type, not SDK messages that can include tokens.
            error_name = type(exc).__name__
            logger.warning('Push delivery event %s failed (%s)', job.event_id, error_name)
        delay = min(3600, 30 * 2 ** min(job.attempts - 1, 7))
        owned_job.update(
            pending_tokens=pending,
            completed_at=timezone.now() if not pending else None,
            available_at=timezone.now() + timedelta(seconds=delay),
            lease_until=None,
            lease_id=None,
            last_error=error_name,
        )
    return sent
