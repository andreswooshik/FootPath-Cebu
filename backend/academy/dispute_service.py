"""Shared, serialized dispute-response workflow for API and portal callers."""

from django.db import transaction

from accounts.models import Roles, User
from config.application_errors import ForbiddenOperation, InvalidOperation

from .models import AuditLog, Dispute, DisputeResponse, DisputeStatus

DISPUTE_RESPONDER_ROLES = frozenset(
    {
        Roles.ADMIN,
        Roles.COACH,
        Roles.COORDINATOR,
    }
)
DISPUTE_STATUS_MANAGER_ROLES = frozenset(
    {
        Roles.ADMIN,
        Roles.COORDINATOR,
    }
)


def can_change_dispute_status(user: User | None) -> bool:
    """Return whether an active user may transition a dispute's lifecycle."""
    return bool(user and user.is_active and user.role in DISPUTE_STATUS_MANAGER_ROLES)


@transaction.atomic
def append_dispute_response(
    *,
    actor: User,
    dispute_id: int,
    body: str,
    status_change_to: str | None = None,
) -> DisputeResponse:
    """Append a reply and optionally perform an authorized status transition.

    Coaches may participate in the discussion but cannot modify lifecycle
    state. This check belongs in the service so non-HTTP callers cannot bypass
    the API view's authorization.
    """
    if not actor.is_active or actor.role not in DISPUTE_RESPONDER_ROLES:
        raise ForbiddenOperation('You may not respond to disputes.')
    new_status = status_change_to or None
    if new_status is not None and not can_change_dispute_status(actor):
        raise ForbiddenOperation('Only Coordinators and Admins may change dispute status.')
    if new_status is not None and new_status not in DisputeStatus.values:
        raise InvalidOperation('Unknown dispute status.')
    if not isinstance(body, str) or not body.strip() or len(body) > 2000:
        raise InvalidOperation('A response must contain 1 to 2000 characters.')

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
        raise ForbiddenOperation('You may not respond to this dispute.')
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
