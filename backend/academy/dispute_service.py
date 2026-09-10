"""Shared, serialized dispute-response workflow for API and portal callers."""

from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction

from accounts.models import Roles

from .models import AuditLog, Dispute, DisputeResponse, DisputeStatus


@transaction.atomic
def append_dispute_response(*, actor, dispute_id, body, status_change_to=None):
    if not actor.is_active or actor.role not in (
        Roles.ADMIN,
        Roles.COACH,
        Roles.SCHOOL_STAFF,
    ):
        raise PermissionDenied('You may not respond to disputes.')
    dispute = (
        Dispute.objects.select_for_update(of=('self',))
        .select_related(
            'raised_by',
        )
        .get(pk=dispute_id)
    )
    if actor.role != Roles.ADMIN and (
        actor.club_id is None
        or dispute.raised_by_id is None
        or dispute.raised_by.club_id != actor.club_id
    ):
        raise PermissionDenied('You may not respond to this dispute.')
    new_status = status_change_to or None
    if new_status is not None and new_status not in DisputeStatus.values:
        raise ValidationError('Unknown dispute status.')
    if not isinstance(body, str) or not body.strip() or len(body) > 2000:
        raise ValidationError('A response must contain 1 to 2000 characters.')
    response = DisputeResponse.objects.create(
        dispute=dispute,
        author=actor,
        body=body,
        status_change_to=new_status,
    )
    if new_status is not None:
        dispute.status = new_status
    dispute.save(update_fields=['status', 'updated_at'])
    AuditLog.record(
        actor,
        'dispute.responded',
        target=f'Dispute #{dispute.pk}: {dispute.summary}',
        detail=(
            f'Status changed to {new_status}.'
            if new_status
            else 'Response added; status unchanged.'
        ),
    )
    return response
