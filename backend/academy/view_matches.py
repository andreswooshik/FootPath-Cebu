"""Domain-focused API views extracted from the legacy view module."""

from django.db import transaction
from django.db.models import Sum
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
    _match_age_bracket,
    _matches_for,
    _role_match,
)
from academy.model_match_performance import PlayerMatchPerformance
from academy.model_operations import (
    AuditLog,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
)
from academy.model_players import PlayerProfile
from academy.model_tournaments import (
    FootballMatch,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
)
from academy.serializer_match_performance import (
    CoachMatchRatingSerializer,
    PlayerMatchPerformanceSerializer,
    PlayerMatchStatisticsWriteSerializer,
)
from academy.serializer_tournaments import FootballMatchSerializer
from academy.tournament_rosters import roster_eligibility
from accounts.models import (
    Roles,
    User,
)


class FootballMatchListCreateView(APIView):
    """List completed matches or let a Coordinator record a result."""

    def get(self, request):
        if request.user.role not in (
            Roles.COORDINATOR,
            Roles.COACH,
            Roles.ADMIN,
        ):
            raise PermissionDenied('Your role cannot view club match records.')
        return Response(FootballMatchSerializer(_matches_for(request.user), many=True).data)

    def post(self, request):
        if request.user.role != Roles.COORDINATOR:
            raise PermissionDenied('Only Coordinators can create match records.')
        if request.user.club_id is None:
            raise PermissionDenied('Coordinator account must belong to a club.')

        fixture_id = request.data.get('fixtureId')
        if fixture_id not in (None, ''):
            raise ValidationError(
                {
                    'fixtureId': (
                        'Use the fixture Record Result action so participants and '
                        'objective statistics are saved atomically.'
                    )
                }
            )
        match_data = request.data.copy()
        match_data.pop('fixtureId', None)
        serializer = FootballMatchSerializer(data=match_data)
        serializer.is_valid(raise_exception=True)
        match = serializer.save(
            club=request.user.club,
            created_by=request.user,
        )
        AuditLog.record(
            request.user,
            'match.created',
            target=str(match.pk),
            detail=(f'{match.opponent} | {match.played_on} | ad-hoc'),
        )
        return Response(
            FootballMatchSerializer(match).data,
            status=status.HTTP_201_CREATED,
        )


class FootballMatchDetailView(APIView):
    """Read or correct match metadata without changing tenant ownership."""

    def get(self, request, match_id):
        if request.user.role not in (
            Roles.COORDINATOR,
            Roles.COACH,
            Roles.ADMIN,
        ):
            raise PermissionDenied('Your role cannot view club match records.')
        match = get_object_or_404(_matches_for(request.user), pk=match_id)
        return Response(FootballMatchSerializer(match).data)

    def put(self, request, match_id):
        match = _role_match(request, match_id, Roles.COORDINATOR)
        data = request.data.copy()
        data.pop('fixtureId', None)
        if hasattr(match, 'source_fixture'):
            data = {key: data[key] for key in ('ourScore', 'opponentScore') if key in data}
        serializer = FootballMatchSerializer(
            match,
            data=data,
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        AuditLog.record(
            request.user,
            'match.updated',
            target=str(match.pk),
            detail=f'{match.opponent} | {match.played_on}',
        )
        return Response(FootballMatchSerializer(match).data)


class MatchPerformanceListView(APIView):
    """Role-redacted read view for all recorded players in one match."""

    def get(self, request, match_id):
        if request.user.role not in (
            Roles.COORDINATOR,
            Roles.COACH,
            Roles.ADMIN,
        ):
            raise PermissionDenied('Your role cannot view match performances.')
        match = get_object_or_404(_matches_for(request.user), pk=match_id)
        rows = PlayerMatchPerformance.objects.select_related(
            'match',
            'player',
            'match__club',
        ).filter(match=match)
        return Response(
            PlayerMatchPerformanceSerializer(
                rows,
                many=True,
                context={'request': request},
            ).data
        )


class MatchRosterView(APIView):
    """Server-filtered current match choices plus existing historical rows."""

    def get(self, request, match_id):
        if request.user.role not in (
            Roles.COORDINATOR,
            Roles.COACH,
            Roles.ADMIN,
        ):
            raise PermissionDenied('Your role cannot view this match roster.')
        match = get_object_or_404(_matches_for(request.user), pk=match_id)
        bracket = _match_age_bracket(match)
        include_out_of_squad = request.query_params.get('includeOutOfSquad', '').lower() == 'true'
        if include_out_of_squad and request.user.role != Roles.COORDINATOR:
            raise PermissionDenied('Only Coordinators can review out-of-squad match candidates.')
        profiles = (
            PlayerProfile.objects.select_related('user')
            .filter(
                user__club_id=match.club_id,
                user__role=Roles.PLAYER,
                user__is_active=True,
            )
            .order_by('user__last_name', 'user__first_name', 'user__id')
        )
        performances = {
            row.player_id: row
            for row in PlayerMatchPerformance.objects.select_related(
                'match',
                'player',
                'match__club',
            ).filter(match=match)
        }
        squad_entries = {}
        if bracket is not None:
            squad_entries = {
                entry.player_id: entry
                for entry in TournamentSquadEntry.objects.select_related(
                    'player__player_profile',
                ).filter(
                    squad__bracket=bracket,
                    squad__status=TournamentSquadStatus.PUBLISHED,
                )
            }
        active_injury_statuses = {}
        for player_id, injury_status in InjuryRecord.objects.filter(
            player__club_id=match.club_id,
            review_status=InjuryReportStatus.CONFIRMED,
            status__in=(InjuryStatus.ACTIVE, InjuryStatus.RECOVERING),
        ).values_list('player_id', 'status'):
            current = active_injury_statuses.get(player_id)
            if current is None or injury_status == InjuryStatus.ACTIVE:
                active_injury_statuses[player_id] = injury_status
        result = []
        for profile in profiles:
            performance = performances.get(profile.user_id)
            squad_entry = squad_entries.get(profile.user_id)
            eligibility = roster_eligibility(profile.user, bracket) if bracket is not None else None
            in_tournament_squad = squad_entry is not None
            if bracket is not None:
                if eligibility.blocked and performance is None:
                    continue
                if not include_out_of_squad and not in_tournament_squad and performance is None:
                    continue
            selectable = eligibility is None or not eligibility.blocked
            result.append(
                {
                    'id': str(profile.user_id),
                    'name': (
                        f'{profile.user.first_name} {profile.user.last_name}'.strip()
                        or profile.user.email.split('@')[0]
                    ),
                    'registeredPosition': profile.position,
                    'tournamentPosition': (squad_entry.position if squad_entry is not None else ''),
                    'inTournamentSquad': in_tournament_squad,
                    'requiresSquadOverride': (bracket is not None and not in_tournament_squad),
                    'isSelectable': selectable,
                    'availability': (eligibility.state if eligibility is not None else 'ELIGIBLE'),
                    'availabilityReason': (eligibility.reason if eligibility is not None else ''),
                    'activeInjuryStatus': active_injury_statuses.get(profile.user_id),
                    'performance': (
                        PlayerMatchPerformanceSerializer(
                            performance,
                            context={'request': request},
                        ).data
                        if performance
                        else None
                    ),
                    'ratingStatus': (
                        'RATED'
                        if performance and performance.coach_rating is not None
                        else 'AWAITING_RATING'
                        if performance
                        else 'AWAITING_STATISTICS'
                    ),
                }
            )
        return Response(result)


class MatchPerformanceDetailView(APIView):
    """Coordinator-owned objective statistics for one player/match."""

    def put(self, request, match_id, player_id):
        match = _role_match(request, match_id, Roles.COORDINATOR)
        player = get_object_or_404(
            User.objects.select_related('player_profile'),
            pk=player_id,
            role=Roles.PLAYER,
            club_id=request.user.club_id,
        )
        bracket = _match_age_bracket(match)
        active_injuries = (
            InjuryRecord.objects.filter(
                player=player,
                review_status=InjuryReportStatus.CONFIRMED,
                status__in=(InjuryStatus.ACTIVE, InjuryStatus.RECOVERING),
            )
            if bracket is None
            else InjuryRecord.objects.none()
        )
        injury_override = str(request.data.get('injuryOverrideAcknowledged', '')).lower() == 'true'
        if active_injuries.exists() and not injury_override:
            return Response(
                {
                    'code': 'ACTIVE_INJURY_WARNING',
                    'detail': (
                        'This player has a confirmed Active or Recovering '
                        'injury. Acknowledge the warning to continue.'
                    ),
                    'injuries': [
                        {
                            'id': str(injury.id),
                            'description': injury.description,
                            'status': injury.status,
                        }
                        for injury in active_injuries
                    ],
                },
                status=status.HTTP_409_CONFLICT,
            )
        data = request.data.copy()
        data.pop('injuryOverrideAcknowledged', None)
        requested_squad_reason = str(data.pop('squadOverrideReason', '')).strip()
        if len(requested_squad_reason) > 500:
            raise ValidationError({'squadOverrideReason': 'Use 500 characters or fewer.'})
        squad_override_applied = False
        squad_override_reason = ''
        with transaction.atomic():
            # Lock the parent to serialize two submissions for the same match;
            # the unique DB constraint is the final duplicate-write guard.
            match = (
                FootballMatch.objects.select_for_update(of=('self',))
                .select_related(
                    'source_fixture__age_bracket__schedule',
                )
                .get(pk=match.pk)
            )
            bracket = _match_age_bracket(match)
            existing = (
                PlayerMatchPerformance.objects.select_for_update()
                .filter(
                    match=match,
                    player=player,
                )
                .first()
            )
            save_kwargs = {}
            if bracket is not None:
                eligibility = roster_eligibility(player, bracket)
                if eligibility.blocked:
                    raise ValidationError(
                        {
                            'player': {
                                'code': eligibility.code,
                                'detail': eligibility.reason,
                            }
                        }
                    )
                squad = (
                    TournamentSquad.objects.select_for_update()
                    .filter(
                        bracket=bracket,
                        status=TournamentSquadStatus.PUBLISHED,
                    )
                    .first()
                )
                in_published_squad = (
                    squad is not None and squad.entries.filter(player=player).exists()
                )
                if not in_published_squad:
                    previous_reason = existing.squad_override_reason if existing else ''
                    squad_override_reason = (requested_squad_reason or previous_reason).strip()
                    if not squad_override_reason:
                        raise ValidationError(
                            {
                                'squadOverrideReason': (
                                    'Explain why this eligible out-of-squad player '
                                    'is being added to the match.'
                                )
                            }
                        )
                    if squad_override_reason != previous_reason:
                        save_kwargs.update(
                            {
                                'squad_override_reason': squad_override_reason,
                                'squad_override_by': request.user,
                                'squad_override_at': timezone.now(),
                            }
                        )
                        squad_override_applied = True
            serializer = PlayerMatchStatisticsWriteSerializer(
                existing,
                data=data,
            )
            serializer.is_valid(raise_exception=True)
            proposed_goals = serializer.validated_data.get(
                'goals',
                existing.goals if existing else 0,
            )
            other_goals = (
                PlayerMatchPerformance.objects.filter(
                    match=match,
                )
                .exclude(player=player)
                .aggregate(total=Sum('goals'))['total']
                or 0
            )
            if other_goals + proposed_goals > match.our_score:
                raise ValidationError({'goals': 'Recorded player goals exceed the team score.'})
            proposed_conceded = serializer.validated_data.get(
                'goals_conceded',
                existing.goals_conceded if existing else 0,
            )
            if proposed_conceded > match.opponent_score:
                raise ValidationError(
                    {'goalsConceded': ('Goals conceded cannot exceed the opponent score.')}
                )
            performance = serializer.save(
                match=match,
                player=player,
                recorded_by=request.user,
                **save_kwargs,
            )
        AuditLog.record(
            request.user,
            'match.performance_saved',
            target=f'{match.pk}:{player.pk}',
        )
        if injury_override and active_injuries.exists():
            AuditLog.record(
                request.user,
                'match.injury_override',
                target=f'{match.pk}:{player.pk}',
                detail=','.join(str(item.id) for item in active_injuries),
            )
        if squad_override_applied:
            AuditLog.record(
                request.user,
                'match.squad_override',
                target=f'{match.pk}:{player.pk}',
                detail=squad_override_reason,
            )
        return Response(
            PlayerMatchPerformanceSerializer(
                performance,
                context={'request': request},
            ).data,
            status=status.HTTP_200_OK if existing else status.HTTP_201_CREATED,
        )

    def delete(self, request, match_id, player_id):
        match = _role_match(request, match_id, Roles.COORDINATOR)
        performance = get_object_or_404(
            PlayerMatchPerformance,
            match=match,
            player_id=player_id,
        )
        if (
            performance.coach_rating is not None
            and request.query_params.get('confirmRated', '').lower() != 'true'
        ):
            return Response(
                {'detail': 'Deleting these statistics also removes the Coach rating.'},
                status=status.HTTP_409_CONFLICT,
            )
        performance.delete()
        AuditLog.record(
            request.user,
            'match.performance_deleted',
            target=f'{match.pk}:{player_id}',
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class MatchPerformanceRatingView(APIView):
    """Coach-only rating and optional notes for existing objective statistics."""

    def put(self, request, match_id, player_id):
        match = _role_match(request, match_id, Roles.COACH)
        with transaction.atomic():
            performance = get_object_or_404(
                PlayerMatchPerformance.objects.select_for_update().select_related(
                    'match',
                    'player',
                ),
                match=match,
                player_id=player_id,
            )
            serializer = CoachMatchRatingSerializer(
                performance,
                data=request.data,
                partial=False,
            )
            serializer.is_valid(raise_exception=True)
            performance = serializer.save(
                rated_by=request.user,
                rated_at=timezone.now(),
            )
        AuditLog.record(
            request.user,
            'match.rating_saved',
            target=f'{match.pk}:{player_id}',
        )
        return Response(
            PlayerMatchPerformanceSerializer(
                performance,
                context={'request': request},
            ).data
        )

    def delete(self, request, match_id, player_id):
        match = _role_match(request, match_id, Roles.COACH)
        performance = get_object_or_404(
            PlayerMatchPerformance,
            match=match,
            player_id=player_id,
        )
        performance.coach_rating = None
        performance.notes = ''
        performance.rated_by = None
        performance.rated_at = None
        performance.save(
            update_fields=[
                'coach_rating',
                'notes',
                'rated_by',
                'rated_at',
                'updated_at',
            ]
        )
        AuditLog.record(
            request.user,
            'match.rating_cleared',
            target=f'{match.pk}:{player_id}',
        )
        return Response(status=status.HTTP_204_NO_CONTENT)
