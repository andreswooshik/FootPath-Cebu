"""Domain-focused API views extracted from the legacy view module."""

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import (
    PermissionDenied,
    ValidationError,
)
from rest_framework.response import Response
from rest_framework.views import APIView

from academy.model_operations import (
    AuditLog,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    InjuryStatusUpdateRequest,
    InjuryUpdateReviewStatus,
)
from academy.model_players import PlayerProfile
from academy.serializer_players import PlayerSelectorSerializer
from academy.serializer_workflows import (
    InjuryRecordSerializer,
    InjuryStatusUpdateRequestSerializer,
)
from accounts.guardian_access import guardian_can_access_player
from accounts.models import (
    Roles,
    User,
)

from .view_players import _require_unlock_when_pin_exists


def _injury_records():
    return InjuryRecord.objects.select_related(
        'player',
        'reported_by',
        'reviewed_by',
    ).prefetch_related(
        'status_update_requests__submitted_by',
        'status_update_requests__reviewed_by',
    )


def _same_club_injury_coordinator(user, injury):
    return (
        user.role == Roles.COORDINATOR
        and user.club_id is not None
        and user.club_id == injury.player.club_id
    )


def _care_team_may_view(user, injury):
    if user.role == Roles.ADMIN:
        return True
    if user.role == Roles.PLAYER:
        return user.id == injury.player_id
    if user.role in (Roles.COACH, Roles.COORDINATOR):
        return user.club_id is not None and user.club_id == injury.player.club_id
    if user.role == Roles.GUARDIAN:
        return guardian_can_access_player(user, injury.player_id)
    return False


def _injury_player_for_report(request):
    user = request.user
    if user.role == Roles.PLAYER:
        return user
    player_id = request.data.get('playerId')
    if not player_id:
        raise ValidationError({'playerId': 'Choose the injured player.'})
    player = get_object_or_404(User, pk=player_id, role=Roles.PLAYER)
    if user.role == Roles.GUARDIAN:
        if not guardian_can_access_player(user, player.id):
            raise PermissionDenied('You may not report for this player.')
        _require_unlock_when_pin_exists(request, player.id)
        return player
    if user.role in (Roles.COACH, Roles.COORDINATOR):
        if user.club_id is None or user.club_id != player.club_id:
            raise PermissionDenied('You may not report for this player.')
        return player
    raise PermissionDenied('Your role cannot submit injury reports.')


def _scoped_injury_records(request):
    user = request.user
    records = _injury_records()
    player_id = request.query_params.get('player')
    if user.role == Roles.ADMIN:
        pass
    elif user.role == Roles.PLAYER:
        records = records.filter(player=user)
    elif user.role in (Roles.COACH, Roles.COORDINATOR):
        if user.club_id is None:
            records = records.none()
        else:
            records = records.filter(player__club_id=user.club_id)
    elif user.role == Roles.GUARDIAN:
        if not player_id or not guardian_can_access_player(user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        records = records.filter(player_id=player_id)
    else:
        raise PermissionDenied('You may not view injury records.')

    if player_id and user.role != Roles.GUARDIAN:
        records = records.filter(player_id=player_id)
    if user.role not in (Roles.ADMIN, Roles.COORDINATOR):
        records = records.filter(
            ~Q(review_status=InjuryReportStatus.REJECTED) | Q(reported_by=user)
        )
    include_archived = request.query_params.get('includeArchived', '').lower() == 'true'
    if not include_archived or user.role not in (Roles.ADMIN, Roles.COORDINATOR):
        records = records.exclude(review_status=InjuryReportStatus.ARCHIVED)
    return records


def _workflow_injury(request, pk):
    injury = get_object_or_404(_injury_records(), pk=pk)
    if not _care_team_may_view(request.user, injury):
        raise PermissionDenied('You may not access this injury report.')
    if (
        injury.review_status == InjuryReportStatus.REJECTED
        and request.user.role not in (Roles.ADMIN, Roles.COORDINATOR)
        and injury.reported_by_id != request.user.id
    ):
        raise PermissionDenied('You may not access this injury report.')
    if request.user.role == Roles.GUARDIAN:
        _require_unlock_when_pin_exists(request, injury.player_id)
    return injury


class InjuryWorkflowListCreateView(APIView):
    """List private care-team reports or submit one for confirmation."""

    def get(self, request):
        records = _scoped_injury_records(request)
        return Response(
            InjuryRecordSerializer(
                records,
                many=True,
                context={'request': request},
            ).data
        )

    def post(self, request):
        player = _injury_player_for_report(request)
        data = request.data.copy()
        data['status'] = InjuryStatus.ACTIVE
        data['resolvedOn'] = None
        serializer = InjuryRecordSerializer(
            data=data,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        record = serializer.save(
            player=player,
            reported_by=request.user,
            review_status=InjuryReportStatus.PENDING,
        )
        AuditLog.record(
            request.user,
            'injury.reported',
            target=f'{player.id}:{record.id}',
        )
        return Response(
            InjuryRecordSerializer(
                record,
                context={'request': request},
            ).data,
            status=status.HTTP_201_CREATED,
        )


class InjuryReportablePlayersView(APIView):
    """Minimal same-club player selector for care-team injury reporting."""

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.COORDINATOR):
            raise PermissionDenied('Your role cannot list club players here.')
        if request.user.club_id is None:
            return Response([])
        profiles = (
            PlayerProfile.objects.select_related('user')
            .filter(
                user__club_id=request.user.club_id,
                user__role=Roles.PLAYER,
                user__is_active=True,
            )
            .order_by('user__last_name', 'user__first_name', 'user__id')
        )
        return Response(PlayerSelectorSerializer(profiles, many=True).data)


class InjuryWorkflowDetailView(APIView):
    """Read a report; Pending reporter/Coordinator or confirmed Coordinator edit."""

    def get(self, request, pk):
        record = _workflow_injury(request, pk)
        return Response(
            InjuryRecordSerializer(
                record,
                context={'request': request},
            ).data
        )

    def put(self, request, pk):
        record = _workflow_injury(request, pk)
        coordinator = _same_club_injury_coordinator(request.user, record)
        pending_editor = record.review_status == InjuryReportStatus.PENDING and (
            record.reported_by_id == request.user.id or coordinator
        )
        confirmed_editor = record.review_status == InjuryReportStatus.CONFIRMED and coordinator
        if not (pending_editor or confirmed_editor):
            raise PermissionDenied('This injury report cannot be edited.')
        data = request.data.copy()
        if pending_editor:
            data['status'] = InjuryStatus.ACTIVE
            data['resolvedOn'] = None
        serializer = InjuryRecordSerializer(
            record,
            data=data,
            partial=True,
            context={'request': request},
        )
        serializer.is_valid(raise_exception=True)
        record = serializer.save()
        AuditLog.record(
            request.user,
            'injury.updated',
            target=f'{record.player_id}:{record.id}',
        )
        return Response(
            InjuryRecordSerializer(
                record,
                context={'request': request},
            ).data
        )

    def delete(self, request, pk):
        record = _workflow_injury(request, pk)
        coordinator = _same_club_injury_coordinator(request.user, record)
        if not (
            record.review_status == InjuryReportStatus.PENDING
            and (record.reported_by_id == request.user.id or coordinator)
        ):
            raise PermissionDenied('Only a Pending report can be withdrawn.')
        target = f'{record.player_id}:{record.id}'
        record.delete()
        AuditLog.record(request.user, 'injury.withdrawn', target=target)
        return Response(status=status.HTTP_204_NO_CONTENT)


class InjuryReviewView(APIView):
    """Coordinator confirms or rejects a Pending injury report."""

    def post(self, request, pk):
        with transaction.atomic():
            record = get_object_or_404(
                _injury_records().select_for_update(of=('self',)),
                pk=pk,
            )
            if not _same_club_injury_coordinator(request.user, record):
                raise PermissionDenied('Only the club Coordinator can review this report.')
            if record.review_status != InjuryReportStatus.PENDING:
                raise ValidationError('Only a Pending report can be reviewed.')
            action = str(request.data.get('action', '')).upper()
            reason = str(request.data.get('rejectionReason', '')).strip()
            if action == 'CONFIRM':
                record.review_status = InjuryReportStatus.CONFIRMED
                record.rejection_reason = ''
                audit_action = 'injury.confirmed'
            elif action == 'REJECT':
                if not reason:
                    raise ValidationError(
                        {'rejectionReason': 'Explain why the report was rejected.'}
                    )
                record.review_status = InjuryReportStatus.REJECTED
                record.rejection_reason = reason
                audit_action = 'injury.rejected'
            else:
                raise ValidationError({'action': 'Choose CONFIRM or REJECT.'})
            record.reviewed_by = request.user
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
            request.user,
            audit_action,
            target=f'{record.player_id}:{record.id}',
            detail=reason,
        )
        return Response(
            InjuryRecordSerializer(
                record,
                context={'request': request},
            ).data
        )


class InjuryArchiveView(APIView):
    def post(self, request, pk):
        record = _workflow_injury(request, pk)
        if not _same_club_injury_coordinator(request.user, record):
            raise PermissionDenied('Only the club Coordinator can archive reports.')
        if record.review_status != InjuryReportStatus.CONFIRMED:
            raise ValidationError('Only a Confirmed report can be archived.')
        if record.status != InjuryStatus.RECOVERED:
            raise ValidationError('Only a Recovered injury report can be archived.')
        record.review_status = InjuryReportStatus.ARCHIVED
        record.archived_at = timezone.now()
        record.save(update_fields=['review_status', 'archived_at', 'updated_at'])
        AuditLog.record(
            request.user,
            'injury.archived',
            target=f'{record.player_id}:{record.id}',
        )
        return Response(
            InjuryRecordSerializer(
                record,
                context={'request': request},
            ).data
        )


class InjuryStatusUpdateListCreateView(APIView):
    """Care team requests a recovery-state change for a Confirmed injury."""

    def post(self, request, pk):
        with transaction.atomic():
            record = get_object_or_404(
                _injury_records().select_for_update(of=('self',)),
                pk=pk,
            )
            if not _care_team_may_view(request.user, record):
                raise PermissionDenied('You may not update this injury.')
            if request.user.role not in (
                Roles.PLAYER,
                Roles.GUARDIAN,
                Roles.COACH,
            ):
                raise PermissionDenied('Players, Guardians, and Coaches submit recovery updates.')
            if request.user.role == Roles.GUARDIAN:
                _require_unlock_when_pin_exists(request, record.player_id)
            if record.review_status != InjuryReportStatus.CONFIRMED:
                raise ValidationError('Recovery updates require a Confirmed injury report.')
            if record.status == InjuryStatus.RECOVERED:
                raise ValidationError('This injury is already Recovered.')
            if record.status_update_requests.filter(
                review_status=InjuryUpdateReviewStatus.PENDING,
            ).exists():
                raise ValidationError('A recovery update is already awaiting Coordinator review.')
            serializer = InjuryStatusUpdateRequestSerializer(data=request.data)
            serializer.is_valid(raise_exception=True)
            proposed_resolved = serializer.validated_data.get('proposed_resolved_on')
            if proposed_resolved and proposed_resolved < record.occurred_on:
                raise ValidationError(
                    {'proposedResolvedOn': ('The recovery date cannot precede the injury.')}
                )
            update_request = serializer.save(
                injury=record,
                submitted_by=request.user,
            )
        AuditLog.record(
            request.user,
            'injury.status_requested',
            target=f'{record.id}:{update_request.id}',
            detail=update_request.proposed_status,
        )
        return Response(
            InjuryStatusUpdateRequestSerializer(update_request).data,
            status=status.HTTP_201_CREATED,
        )


class InjuryStatusUpdateReviewView(APIView):
    """Coordinator approves or rejects one Pending recovery update."""

    def post(self, request, pk, update_id):
        with transaction.atomic():
            update_request = get_object_or_404(
                InjuryStatusUpdateRequest.objects.select_for_update(
                    of=('self', 'injury')
                ).select_related('injury__player', 'submitted_by'),
                pk=update_id,
                injury_id=pk,
            )
            record = update_request.injury
            if not _same_club_injury_coordinator(request.user, record):
                raise PermissionDenied('Only the club Coordinator can review updates.')
            if update_request.review_status != InjuryUpdateReviewStatus.PENDING:
                raise ValidationError('This recovery update is no longer Pending.')
            action = str(request.data.get('action', '')).upper()
            reason = str(request.data.get('rejectionReason', '')).strip()
            if action == 'APPROVE':
                update_request.review_status = InjuryUpdateReviewStatus.APPROVED
                update_request.rejection_reason = ''
                record.status = update_request.proposed_status
                record.resolved_on = update_request.proposed_resolved_on
                record.save(update_fields=['status', 'resolved_on', 'updated_at'])
                audit_action = 'injury.status_approved'
            elif action == 'REJECT':
                if not reason:
                    raise ValidationError(
                        {'rejectionReason': 'Explain why the update was rejected.'}
                    )
                update_request.review_status = InjuryUpdateReviewStatus.REJECTED
                update_request.rejection_reason = reason
                audit_action = 'injury.status_rejected'
            else:
                raise ValidationError({'action': 'Choose APPROVE or REJECT.'})
            update_request.reviewed_by = request.user
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
            request.user,
            audit_action,
            target=f'{record.id}:{update_request.id}',
            detail=reason or update_request.proposed_status,
        )
        return Response(
            InjuryRecordSerializer(
                _injury_records().get(pk=record.pk),
                context={'request': request},
            ).data
        )
