"""Domain-focused API views extracted from the legacy view module."""

from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
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

from . import injury_service
from .view_players import _require_unlock_when_pin_exists


def _injury_records():
    """Preloads the people and status requests used when serializing injury records."""
    return InjuryRecord.objects.select_related(
        'player',
        'reported_by',
        'reviewed_by',
    ).prefetch_related(
        'status_update_requests__submitted_by',
        'status_update_requests__reviewed_by',
    )


_same_club_injury_coordinator = injury_service.same_club_coordinator
_care_team_may_view = injury_service.care_team_may_view


def _injury_player_for_report(request):
    """Resolves the reported player and enforces reporting access and any PIN gate."""
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
    """Limits injury records to the requester access scope and requested archive filter."""
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


def _workflow_injury(request, pk, *, lock=True):
    """Loads an injury and enforces care-team access and any required player unlock."""
    records = _injury_records()
    if lock and request.method not in ('GET', 'HEAD', 'OPTIONS'):
        records = records.select_for_update(of=('self',))
    injury = get_object_or_404(records, pk=pk)
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
        """Lists injury reports visible to the requester."""
        records = _scoped_injury_records(request)
        return Response(
            InjuryRecordSerializer(
                records,
                many=True,
                context={'request': request},
            ).data
        )

    @transaction.atomic
    def post(self, request):
        """Creates an injury report for an authorized player and records the action."""
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
        """Lists active club players available for coordinator injury reporting."""
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
        """Returns the selected injury after care-team access checks."""
        record = _workflow_injury(request, pk)
        return Response(
            InjuryRecordSerializer(
                record,
                context={'request': request},
            ).data
        )

    @transaction.atomic
    def put(self, request, pk):
        """Updates an injury report when the requester and review state allow editing."""
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

    @transaction.atomic
    def delete(self, request, pk):
        """Deletes an injury report when its workflow permissions allow withdrawal."""
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
        record = injury_service.review_injury(
            actor=request.user,
            pk=pk,
            action=str(request.data.get('action', '')).upper(),
            reason=str(request.data.get('rejectionReason', '')).strip(),
        )
        return Response(InjuryRecordSerializer(record, context={'request': request}).data)


class InjuryArchiveView(APIView):
    def post(self, request, pk):
        record = injury_service.archive_injury(actor=request.user, pk=pk)
        return Response(InjuryRecordSerializer(record, context={'request': request}).data)


class InjuryStatusUpdateListCreateView(APIView):
    """Parse recovery updates and enforce the transport privacy grant."""

    def post(self, request, pk):
        _workflow_injury(request, pk, lock=False)
        serializer = InjuryStatusUpdateRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        update_request = injury_service.request_status_update(
            actor=request.user,
            pk=pk,
            data=serializer.validated_data,
        )
        return Response(
            InjuryStatusUpdateRequestSerializer(update_request).data, status=status.HTTP_201_CREATED
        )


class InjuryStatusUpdateReviewView(APIView):
    """Coordinator approves or rejects one Pending recovery update."""

    def post(self, request, pk, update_id):
        record = injury_service.review_status_update(
            actor=request.user,
            pk=pk,
            update_id=update_id,
            action=str(request.data.get('action', '')).upper(),
            reason=str(request.data.get('rejectionReason', '')).strip(),
        )
        return Response(InjuryRecordSerializer(record, context={'request': request}).data)
