"""Atomic replacement of a complete session roll call."""

import hashlib
import json
from dataclasses import dataclass

from django.core.serializers.json import DjangoJSONEncoder
from django.db import transaction
from django.utils import timezone

from accounts.models import Club, Roles, User
from config.application_errors import ForbiddenOperation, InvalidOperation, MissingResource

from .errors import WorkflowConflict
from .models import (
    Attendance,
    AttendanceSubmission,
    AuditLog,
    TrainingSession,
    TrainingSessionStatus,
)


@dataclass(frozen=True)
class AttendanceReplacement:
    session: TrainingSession
    submission: AttendanceSubmission | None = None
    duplicate: bool = False


def _payload_hash(records):
    """Hashes a canonical attendance payload so retries can detect reused request keys."""
    canonical = json.dumps(
        records,
        cls=DjangoJSONEncoder,
        sort_keys=True,
        separators=(',', ':'),
    )
    return hashlib.sha256(canonical.encode('utf-8')).hexdigest()


@transaction.atomic
def replace_attendance(*, coach, session_id, records, request_key=None, expected_revision=None):
    """Atomically replaces a session roll call, enforcing access, edit windows, and revision

    checks. Repeated request keys return the original submission when the payload matches.
    """
    if coach.role != Roles.COACH or coach.club_id is None:
        raise ForbiddenOperation('Only club coaches can record attendance.')
    Club.objects.select_for_update().get(pk=coach.club_id)
    try:
        session = TrainingSession.objects.select_for_update().get(pk=session_id)
    except TrainingSession.DoesNotExist as exc:
        raise MissingResource() from exc
    if session.club_id != coach.club_id:
        raise ForbiddenOperation('That session is not in your club.')
    payload_hash = _payload_hash(records)
    if request_key:
        previous = AttendanceSubmission.objects.filter(
            coach=coach,
            request_key=request_key,
        ).first()
        if previous is not None:
            if previous.session_id != session.pk or previous.payload_hash != payload_hash:
                raise WorkflowConflict(
                    'ATTENDANCE_REQUEST_KEY_REUSED',
                    'This attendance request key was already used for different marks.',
                )
            return AttendanceReplacement(session, previous, duplicate=True)
    if expected_revision is not None and expected_revision != session.attendance_revision:
        raise WorkflowConflict(
            'ATTENDANCE_REVISION_CONFLICT',
            'Attendance changed on another device. Reload it before saving again.',
            expectedRevision=expected_revision,
            currentRevision=session.attendance_revision,
        )
    if session.status == TrainingSessionStatus.CANCELLED:
        raise WorkflowConflict(
            'SESSION_CANCELLED',
            'Attendance is unavailable for a cancelled training session.',
        )
    if session.attendance_is_locked():
        raise WorkflowConflict(
            'ATTENDANCE_LOCKED_48H',
            'Attendance is read-only 48 hours after the training session ends.',
        )
    if timezone.localdate() < session.date:
        raise InvalidOperation('Attendance cannot be logged before the session day.')
    submitted_ids = [row['playerId'] for row in records]
    if len(submitted_ids) != len(set(submitted_ids)):
        raise InvalidOperation({'records': 'Each player may appear only once.'})
    in_club = set(
        User.objects.filter(
            pk__in=submitted_ids,
            club_id=coach.club_id,
            role=Roles.PLAYER,
        ).values_list('id', flat=True)
    )
    if in_club != set(submitted_ids):
        raise InvalidOperation({'records': 'One or more player IDs are unknown or unavailable.'})
    for record in sorted(records, key=lambda row: row['playerId']):
        Attendance.objects.update_or_create(
            player_id=record['playerId'],
            session=session,
            defaults={
                'status': record['status'],
                'effort': record.get('effort'),
                'performance_score': record.get('performanceScore'),
                'note': record.get('note') or '',
                'recorded_by': coach,
            },
        )
    Attendance.objects.filter(session=session).exclude(player_id__in=submitted_ids).delete()
    if session.status == TrainingSessionStatus.SCHEDULED:
        session.status = TrainingSessionStatus.COMPLETED
    session.attendance_revision += 1
    session.save(update_fields=['status', 'attendance_revision'])
    submission = None
    if request_key:
        submission = AttendanceSubmission.objects.create(
            coach=coach,
            session=session,
            request_key=request_key,
            payload_hash=payload_hash,
            committed_revision=session.attendance_revision,
        )
    AuditLog.record(
        coach, 'attendance.replaced', target=str(session.pk), detail=f'{len(records)} players'
    )
    return AttendanceReplacement(session, submission)
