"""Atomic injury transitions and their audit trail."""

from django.db import transaction
from django.utils import timezone

from accounts.guardian_access import guardian_can_access_player
from accounts.models import Roles
from config.application_errors import ForbiddenOperation, InvalidOperation, MissingResource

from .model_operations import (
    AuditLog,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    InjuryStatusUpdateRequest,
    InjuryUpdateReviewStatus,
)


def same_club_coordinator(user, injury):
    return (
        user.role == Roles.COORDINATOR
        and user.club_id is not None
        and user.club_id == injury.player.club_id
    )


def care_team_may_view(user, injury):
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.PLAYER:
        return user.id == injury.player_id
    if user.role in (Roles.COACH, Roles.COORDINATOR):
        return user.club_id is not None and user.club_id == injury.player.club_id
    return user.role == Roles.GUARDIAN and guardian_can_access_player(user, injury.player_id)


def _locked_record(pk):
    try:
        return (
            InjuryRecord.objects.select_related('player').select_for_update(of=('self',)).get(pk=pk)
        )
    except InjuryRecord.DoesNotExist as exc:
        raise MissingResource() from exc


@transaction.atomic
def review_injury(*, actor, pk, action, reason):
    record = _locked_record(pk)
    if not same_club_coordinator(actor, record):
        raise ForbiddenOperation('Only the club Coordinator can review this report.')
    if record.review_status != InjuryReportStatus.PENDING:
        raise InvalidOperation('Only a Pending report can be reviewed.')
    if action == 'CONFIRM':
        record.review_status = InjuryReportStatus.CONFIRMED
        record.rejection_reason = ''
        audit_action = 'injury.confirmed'
    elif action == 'REJECT':
        if not reason:
            raise InvalidOperation({'rejectionReason': 'Explain why the report was rejected.'})
        record.review_status = InjuryReportStatus.REJECTED
        record.rejection_reason = reason
        audit_action = 'injury.rejected'
    else:
        raise InvalidOperation({'action': 'Choose CONFIRM or REJECT.'})
    record.reviewed_by = actor
    record.reviewed_at = timezone.now()
    record.save(
        update_fields=[
            'review_status',
            'rejection_reason',
            'reviewed_by',
            'reviewed_at',
            'updated_at',
        ]
    )
    AuditLog.record(
        actor,
        audit_action,
        target=f'{record.player_id}:{record.id}',
        detail=reason,
    )
    return record


@transaction.atomic
def archive_injury(*, actor, pk):
    record = _locked_record(pk)
    if not same_club_coordinator(actor, record):
        raise ForbiddenOperation('Only the club Coordinator can archive reports.')
    if record.review_status != InjuryReportStatus.CONFIRMED:
        raise InvalidOperation('Only a Confirmed report can be archived.')
    if record.status != InjuryStatus.RECOVERED:
        raise InvalidOperation('Only a Recovered injury report can be archived.')
    record.review_status = InjuryReportStatus.ARCHIVED
    record.archived_at = timezone.now()
    record.save(update_fields=['review_status', 'archived_at', 'updated_at'])
    AuditLog.record(
        actor,
        'injury.archived',
        target=f'{record.player_id}:{record.id}',
    )
    return record


@transaction.atomic
def review_status_update(*, actor, pk, update_id, action, reason):
    record = _locked_record(pk)
    try:
        update_request = InjuryStatusUpdateRequest.objects.select_for_update().get(
            pk=update_id, injury_id=pk
        )
    except InjuryStatusUpdateRequest.DoesNotExist as exc:
        raise MissingResource() from exc
    if not same_club_coordinator(actor, record):
        raise ForbiddenOperation('Only the club Coordinator can review updates.')
    if update_request.review_status != InjuryUpdateReviewStatus.PENDING:
        raise InvalidOperation('This recovery update is no longer Pending.')
    if action == 'APPROVE':
        update_request.review_status = InjuryUpdateReviewStatus.APPROVED
        update_request.rejection_reason = ''
        record.status = update_request.proposed_status
        record.resolved_on = update_request.proposed_resolved_on
        record.save(update_fields=['status', 'resolved_on', 'updated_at'])
        audit_action = 'injury.status_approved'
    elif action == 'REJECT':
        if not reason:
            raise InvalidOperation({'rejectionReason': 'Explain why the update was rejected.'})
        update_request.review_status = InjuryUpdateReviewStatus.REJECTED
        update_request.rejection_reason = reason
        audit_action = 'injury.status_rejected'
    else:
        raise InvalidOperation({'action': 'Choose APPROVE or REJECT.'})
    update_request.reviewed_by = actor
    update_request.reviewed_at = timezone.now()
    update_request.save(
        update_fields=[
            'review_status',
            'rejection_reason',
            'reviewed_by',
            'reviewed_at',
            'updated_at',
        ]
    )
    AuditLog.record(
        actor,
        audit_action,
        target=f'{record.id}:{update_request.id}',
        detail=reason or update_request.proposed_status,
    )
    return record


@transaction.atomic
def request_status_update(*, actor, pk, data):
    record = _locked_record(pk)
    if not care_team_may_view(actor, record):
        raise ForbiddenOperation('You may not update this injury.')
    if actor.role not in (
        Roles.PLAYER,
        Roles.GUARDIAN,
        Roles.COACH,
    ):
        raise ForbiddenOperation('Players, Guardians, and Coaches submit recovery updates.')
    if record.review_status != InjuryReportStatus.CONFIRMED:
        raise InvalidOperation('Recovery updates require a Confirmed injury report.')
    if record.status == InjuryStatus.RECOVERED:
        raise InvalidOperation('This injury is already Recovered.')
    if record.status_update_requests.filter(
        review_status=InjuryUpdateReviewStatus.PENDING,
    ).exists():
        raise InvalidOperation('A recovery update is already awaiting Coordinator review.')
    proposed_resolved = data.get('proposed_resolved_on')
    if proposed_resolved and proposed_resolved < record.occurred_on:
        raise InvalidOperation(
            {'proposedResolvedOn': ('The recovery date cannot precede the injury.')}
        )
    update_request = InjuryStatusUpdateRequest.objects.create(
        **data,
        injury=record,
        submitted_by=actor,
    )

    AuditLog.record(
        actor,
        'injury.status_requested',
        target=f'{record.id}:{update_request.id}',
        detail=update_request.proposed_status,
    )
    return update_request
