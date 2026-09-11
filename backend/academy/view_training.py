"""Domain-focused API views extracted from the legacy view module."""

import re

from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import (
    PermissionDenied,
    ValidationError,
)
from rest_framework.response import Response
from rest_framework.views import APIView

from academy._view_support import (
    _guardian_may_read,
    _session_in_user_scope,
    _sessions_for,
)
from academy.errors import WorkflowConflict
from academy.model_operations import (
    Attendance,
    AuditLog,
    SessionConfirmation,
)
from academy.model_players import (
    ConfirmationStatus,
    TrainingSessionStatus,
)
from academy.model_training import TrainingSession
from academy.notifications import (
    _recipients_for_session,
    notify_session_cancelled,
    notify_session_scheduled,
    notify_session_updated,
)
from academy.schedule_conflicts import (
    conflicting_fixture_for_training,
    fixture_conflict_payload,
    training_conflicts_for_training,
)
from academy.serializer_training import (
    AttendanceSerializer,
    SessionConfirmationSerializer,
    TrainingSessionSerializer,
)
from accounts.models import Roles

from .pagination import list_response
from .transactions import club_write_transaction
from .view_players import _require_unlock_when_pin_exists


class AttendanceListView(APIView):
    """GET /api/attendance/?player=<id> — one player's attendance history.

    Object-level authz: a guardian may only read a player they are linked to; a
    player only themselves; coach/admin anyone. This is the fix for the BOLA
    risk in the audit (F3).
    """

    def get(self, request):
        player_id = request.query_params.get('player')
        if not player_id:
            raise ValidationError('A player query parameter is required.')
        if not _guardian_may_read(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        records = Attendance.objects.select_related('session', 'recorded_by', 'player').filter(
            player_id=player_id
        )
        return list_response(request, records, AttendanceSerializer)


class SessionAttendanceView(APIView):
    """GET/POST /api/attendance/session/<session_id>/ — one session's roll call.

    GET (coach/admin) returns every record for the session. POST (coach only)
    replaces the session's attendance wholesale: rows are upserted per player
    and rows for players absent from the payload are pruned, so re-finalising a
    session corrects it rather than duplicating it (matching the client's
    MockAttendanceRepository semantics).
    """

    def get(self, request, session_id):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only coaches can view session attendance.')
        session = get_object_or_404(TrainingSession, pk=session_id)
        if not _session_in_user_scope(request.user, session):
            raise PermissionDenied('That session is not in your club.')
        if session.status == TrainingSessionStatus.CANCELLED:
            raise WorkflowConflict(
                'SESSION_CANCELLED',
                'Attendance is unavailable for a cancelled training session.',
            )
        records = Attendance.objects.select_related('session', 'recorded_by').filter(
            session_id=session_id
        )
        response = list_response(request, records, AttendanceSerializer)
        self._set_revision_headers(response, session.attendance_revision)
        return response

    @club_write_transaction
    def post(self, request, session_id):
        from .attendance_service import replace_attendance
        from .serializer_workflows import AttendanceBatchSerializer

        serializer = AttendanceBatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        request_key = request.headers.get('Idempotency-Key')
        if request_key is not None and not re.fullmatch(r'[A-Za-z0-9._:-]{16,128}', request_key):
            raise ValidationError({'Idempotency-Key': 'Use 16 to 128 safe characters.'})
        expected_revision = self._expected_revision(request.headers.get('If-Match'))
        replacement = replace_attendance(
            coach=request.user,
            session_id=session_id,
            records=serializer.validated_data['records'],
            request_key=request_key,
            expected_revision=expected_revision,
        )
        if replacement.duplicate and replacement.submission.response_body is not None:
            response = Response(replacement.submission.response_body)
            self._set_revision_headers(response, replacement.submission.committed_revision)
            return response
        records = Attendance.objects.select_related('session', 'recorded_by').filter(
            session=replacement.session
        )
        response = list_response(request, records, AttendanceSerializer)
        revision = (
            replacement.submission.committed_revision
            if replacement.submission
            else replacement.session.attendance_revision
        )
        self._set_revision_headers(response, revision)
        if replacement.submission is not None:
            replacement.submission.response_body = response.data
            replacement.submission.save(update_fields=['response_body'])
        return response

    @staticmethod
    def _expected_revision(value):
        if value is None:
            return None
        match = re.fullmatch(r'(?:W/)?"?(\d+)"?', value.strip())
        if match is None:
            raise ValidationError({'If-Match': 'Use the attendance revision returned by GET.'})
        return int(match.group(1))

    @staticmethod
    def _set_revision_headers(response, revision):
        response['ETag'] = f'"{revision}"'
        response['X-Attendance-Revision'] = str(revision)


class TrainingSessionListCreateView(APIView):
    """GET (own club's sessions; Admin all) / POST (coach only)
    /api/training-sessions/."""

    def get(self, request):
        sessions = _sessions_for(request.user)
        period = request.query_params.get('period')
        today = timezone.localdate()
        if period == 'UPCOMING':
            sessions = sessions.filter(date__gte=today).order_by('date', 'start_time')
        elif period == 'PAST':
            sessions = sessions.filter(date__lte=today).order_by('-date', '-start_time')
        elif period is not None:
            raise ValidationError({'period': 'Use UPCOMING or PAST.'})
        return list_response(request, sessions, TrainingSessionSerializer)

    @club_write_transaction
    def post(self, request):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can schedule sessions.')
        if request.user.club_id is None:
            raise PermissionDenied('Coach account must belong to a club.')
        with transaction.atomic():
            serializer = TrainingSessionSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            draft = TrainingSession(**serializer.validated_data)
            session_start, session_end = draft.interval()
            fixture = conflicting_fixture_for_training(
                club_id=request.user.club_id,
                tiers=draft.age_tiers,
                start=session_start,
                end=session_end,
            )
            if fixture is not None:
                conflict = fixture_conflict_payload(fixture)
                raise WorkflowConflict(
                    'TOURNAMENT_SCHEDULE_CONFLICT', conflict['message'], conflict=conflict
                )
            conflicts = training_conflicts_for_training(
                club_id=request.user.club_id,
                tiers=draft.age_tiers,
                location=draft.location,
                start=session_start,
                end=session_end,
            )
            if conflicts:
                raise WorkflowConflict(
                    'TRAINING_SCHEDULE_CONFLICT',
                    'This session overlaps an existing training session.',
                    conflicts=conflicts,
                )
            # The club lock serializes conflict checks even on an empty schedule.
            session = serializer.save(created_by=request.user, club=request.user.club)
            AuditLog.record(
                request.user, 'session.scheduled', target=session.title, detail=str(session.date)
            )
            notify_session_scheduled(session)
        return Response(TrainingSessionSerializer(session).data, status=status.HTTP_201_CREATED)


class TrainingSessionDetailView(APIView):
    """PUT/DELETE /api/training-sessions/<pk>/ — a coach edits or cancels a
    scheduled session. Club-scoped like creation: any coach in the owning
    club may manage it (there is no per-coach ownership anywhere else in the
    schema either). Cancelled sessions notify the same recipients as
    scheduling; attendance rows survive a cancellation (FK is SET_NULL), so
    recorded history is never destroyed."""

    def _session_for(self, request, pk):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only coaches can manage sessions.')
        session = get_object_or_404(TrainingSession, pk=pk)
        if not _session_in_user_scope(request.user, session):
            raise PermissionDenied('That session is not in your club.')
        return session

    @club_write_transaction
    def put(self, request, pk):
        with transaction.atomic():
            session = self._session_for(request, pk)
            session = TrainingSession.objects.select_for_update(of=('self',)).get(pk=session.pk)
            if session.status != TrainingSessionStatus.SCHEDULED:
                raise WorkflowConflict(
                    'SESSION_LOCKED',
                    'Only scheduled training sessions can be changed.',
                )
            serializer = TrainingSessionSerializer(session, data=request.data, partial=True)
            serializer.is_valid(raise_exception=True)
            values = serializer.validated_data
            draft = TrainingSession(
                title=values.get('title', session.title),
                date=values.get('date', session.date),
                start_time=values.get('start_time', session.start_time),
                end_time=values.get('end_time', session.end_time),
                location=values.get('location', session.location),
                focus=values.get('focus', session.focus),
                age_tiers=values.get('age_tiers', session.age_tiers),
                additional_focuses=values.get('additional_focuses', session.additional_focuses),
                session_objectives=values.get('session_objectives', session.session_objectives),
                equipment_requirements=values.get(
                    'equipment_requirements', session.equipment_requirements
                ),
                coach_instructions=values.get('coach_instructions', session.coach_instructions),
            )
            session_start, session_end = draft.interval()
            fixture = conflicting_fixture_for_training(
                club_id=request.user.club_id,
                tiers=draft.age_tiers,
                start=session_start,
                end=session_end,
            )
            if fixture is not None:
                conflict = fixture_conflict_payload(fixture)
                raise WorkflowConflict(
                    'TOURNAMENT_SCHEDULE_CONFLICT',
                    conflict['message'],
                    conflict=conflict,
                )
            conflicts = training_conflicts_for_training(
                club_id=request.user.club_id,
                tiers=draft.age_tiers,
                location=draft.location,
                start=session_start,
                end=session_end,
                exclude_id=session.id,
            )
            if conflicts:
                raise WorkflowConflict(
                    'TRAINING_SCHEDULE_CONFLICT',
                    'This session overlaps an existing training session.',
                    conflicts=conflicts,
                )
            session = serializer.save()
            AuditLog.record(
                request.user,
                'session.updated',
                target=session.title,
                detail=str(session.date),
            )
            notify_session_updated(session)
        return Response(TrainingSessionSerializer(session).data)

    @club_write_transaction
    def delete(self, request, pk):
        with transaction.atomic():
            scoped = self._session_for(request, pk)
            session = TrainingSession.objects.select_for_update(of=('self',)).get(pk=scoped.pk)
            if session.status != TrainingSessionStatus.SCHEDULED:
                raise WorkflowConflict(
                    'SESSION_LOCKED',
                    'Only scheduled training sessions can be cancelled.',
                )
            session_start, _session_end = session.interval()
            if (session_start is not None and session_start <= timezone.now()) or (
                session_start is None and session.date < timezone.localdate()
            ):
                raise WorkflowConflict(
                    'SESSION_ALREADY_STARTED',
                    'Past or currently running training cannot be cancelled.',
                )
            recipient_ids = _recipients_for_session(session)
            session.status = TrainingSessionStatus.CANCELLED
            session.cancellation_reason = 'Cancelled by the Coach.'
            session.cancelled_at = timezone.now()
            session.cancelled_by_action = 'coach.cancelled'
            session.save(
                update_fields=[
                    'status',
                    'cancellation_reason',
                    'cancelled_at',
                    'cancelled_by_action',
                ]
            )
            AuditLog.record(
                request.user,
                'session.cancelled',
                target=session.title,
                detail=str(session.date),
            )
            notify_session_cancelled(session, user_ids=recipient_ids, session_id=session.id)
        return Response(status=status.HTTP_204_NO_CONTENT)


class SessionConfirmationView(APIView):
    """GET/POST /api/session-confirmations/ — a player's RSVPs for sessions.

    GET ?player=<id>: that player's confirmations, most recent first. Same
    object-level authz as attendance — a guardian only reads a linked player, a
    player only themselves, coach/admin anyone (audit finding F3).

    POST {sessionId, status}: the signed-in player RSVPs. The player is taken
    from the request, never the client, and the row is upserted on
    (player, session) so re-confirming flips the same row rather than stacking.
    """

    def get(self, request):
        player_id = request.query_params.get('player')
        if not player_id:
            raise ValidationError('A player query parameter is required.')
        if not _guardian_may_read(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        records = SessionConfirmation.objects.select_related('session').filter(player_id=player_id)
        return list_response(request, records, SessionConfirmationSerializer)

    @club_write_transaction
    def post(self, request):
        if request.user.role != Roles.PLAYER:
            raise PermissionDenied('Only players can confirm their own sessions.')
        session_id = request.data.get('sessionId')
        status_value = str(request.data.get('status', '')).upper()
        if not session_id:
            raise ValidationError('A sessionId is required.')
        if status_value not in set(ConfirmationStatus.values):
            raise ValidationError(f'Unknown status: {status_value or "(none)"}.')
        session = get_object_or_404(TrainingSession, pk=session_id)
        # Tenancy: a player may only RSVP to sessions in their own club.
        if not _session_in_user_scope(request.user, session):
            raise PermissionDenied('That session is not in your club.')
        if session.date != timezone.localdate():
            raise ValidationError('Players can only confirm a session on its scheduled day.')
        if session.status == TrainingSessionStatus.CANCELLED:
            raise WorkflowConflict('SESSION_CANCELLED', 'A cancelled session cannot be confirmed.')
        confirmation, _ = SessionConfirmation.objects.update_or_create(
            player=request.user,
            session=session,
            defaults={'status': status_value},
        )
        return Response(
            SessionConfirmationSerializer(confirmation).data,
            status=status.HTTP_201_CREATED,
        )
