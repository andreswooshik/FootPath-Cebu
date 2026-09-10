"""Match statistics and player-growth API views."""

from django.db.models import (
    Avg,
    Count,
    Q,
)
from django.shortcuts import get_object_or_404
from django.utils.dateparse import parse_date
from rest_framework.exceptions import (
    PermissionDenied,
    ValidationError,
)
from rest_framework.response import Response
from rest_framework.views import APIView

from academy._view_support import _may_read_match_statistics
from academy.assessment_framework import framework_for
from academy.growth import (
    build_assessment_growth,
    build_development_assessment_growth,
    build_match_growth,
    build_tournament_groups,
    build_training_groups,
    limited,
    resolve_growth_filter,
)
from academy.match_statistics import build_performance_summary
from academy.model_match_performance import PlayerMatchPerformance
from academy.model_operations import Attendance
from academy.model_players import (
    AttendanceStatus,
    MatchCategory,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerProfile,
    PlayerStatsAssessment,
)
from academy.serializer_match_performance import PlayerMatchPerformanceSerializer
from academy.serializer_players import (
    PlayerAssessmentSnapshotSerializer,
    PlayerDevelopmentAssessmentSerializer,
    PlayerStatsAssessmentSerializer,
)
from academy.serializer_training import AttendanceSerializer
from accounts.models import (
    Roles,
    User,
)

from .view_players import _require_unlock_when_pin_exists


class PlayerMatchStatisticsView(APIView):
    """Historical match totals and trend rows for one authorized player."""

    _MAX_ROWS = 100

    def get(self, request, player_id):
        if not _may_read_match_statistics(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        player = get_object_or_404(
            User.objects.select_related('player_profile'),
            pk=player_id,
            role=Roles.PLAYER,
        )

        rows = PlayerMatchPerformance.objects.select_related(
            'match',
            'match__club',
            'player',
        ).filter(player=player)
        from_text = request.query_params.get('from')
        to_text = request.query_params.get('to')
        if from_text:
            from_date = parse_date(from_text)
            if from_date is None:
                raise ValidationError({'from': 'Use YYYY-MM-DD.'})
            rows = rows.filter(match__played_on__gte=from_date)
        if to_text:
            to_date = parse_date(to_text)
            if to_date is None:
                raise ValidationError({'to': 'Use YYYY-MM-DD.'})
            rows = rows.filter(match__played_on__lte=to_date)
        if from_text and to_text and from_date > to_date:
            raise ValidationError({'to': 'End date must not precede start date.'})

        selected_range = request.query_params.get('range')
        selected_limit = None
        if selected_range is not None:
            selected_range = selected_range.lower()
            if selected_range not in ('last5', 'last10', 'all'):
                raise ValidationError({'range': 'Use last5, last10, or all.'})
            selected_limit = {'last5': 5, 'last10': 10}.get(selected_range)
        elif 'limit' in request.query_params:
            try:
                selected_limit = int(request.query_params['limit'])
            except (TypeError, ValueError) as exc:
                raise ValidationError({'limit': 'Use a whole number.'}) from exc
            if not 1 <= selected_limit <= self._MAX_ROWS:
                raise ValidationError({'limit': f'Choose a value from 1 to {self._MAX_ROWS}.'})

        # The summary uses the complete selected range. Only the history
        # payload is capped, so an "All" total is never silently truncated by
        # the response-size safeguard.
        summary_records = list(rows[:selected_limit] if selected_limit is not None else rows)
        records = summary_records[: self._MAX_ROWS]
        name = f'{player.first_name} {player.last_name}'.strip()
        return Response(
            {
                'playerId': str(player.id),
                'playerName': name or player.email.split('@')[0],
                'range': selected_range
                or (f'last{selected_limit}' if selected_limit is not None else 'all'),
                'summary': build_performance_summary(summary_records),
                'performances': PlayerMatchPerformanceSerializer(
                    records,
                    many=True,
                    context={'request': request},
                ).data,
            }
        )


class PlayerGrowthView(APIView):
    """Categorized historical growth for one authorized player."""

    def get(self, request, player_id):
        if not _may_read_match_statistics(request.user, player_id):
            raise PermissionDenied('You may not view this player.')
        _require_unlock_when_pin_exists(request, player_id)
        player = get_object_or_404(
            User.objects.select_related('player_profile'),
            pk=player_id,
            role=Roles.PLAYER,
        )
        selected = resolve_growth_filter(request.query_params)
        category = selected['category']
        from_date = selected['from']
        to_date = selected['to']
        limit = selected['limit']

        def include(name):
            return category in ('all', name)

        assessment_rows = []
        development_rows = []
        player_stats_rows = []
        if include('assessment'):
            snapshots = PlayerAssessmentSnapshot.objects.select_related(
                'player', 'assessed_by'
            ).filter(player=player)
            if from_date:
                snapshots = snapshots.filter(created_at__date__gte=from_date)
            if to_date:
                snapshots = snapshots.filter(created_at__date__lte=to_date)
            assessment_rows = limited(snapshots, limit)
            development = PlayerDevelopmentAssessment.objects.select_related(
                'player', 'assessed_by'
            ).filter(player=player)
            if from_date:
                development = development.filter(created_at__date__gte=from_date)
            if to_date:
                development = development.filter(created_at__date__lte=to_date)
            development_rows = limited(development, limit)
            player_stats = PlayerStatsAssessment.objects.select_related('assessed_by').filter(
                player=player
            )
            if from_date:
                player_stats = player_stats.filter(created_at__date__gte=from_date)
            if to_date:
                player_stats = player_stats.filter(created_at__date__lte=to_date)
            player_stats_rows = limited(player_stats, limit)

        training_rows = []
        if include('training'):
            attendance = Attendance.objects.select_related(
                'session', 'recorded_by', 'player'
            ).filter(player=player, session__isnull=False)
            if from_date:
                attendance = attendance.filter(session__date__gte=from_date)
            if to_date:
                attendance = attendance.filter(session__date__lte=to_date)
            all_training = list(attendance.order_by('-session__date', '-id'))
            if limit is None:
                training_rows = all_training
            else:
                counts = {}
                for row in all_training:
                    focus = row.session.focus
                    counts.setdefault(focus, 0)
                    if counts[focus] < limit:
                        training_rows.append(row)
                        counts[focus] += 1

        match_base = PlayerMatchPerformance.objects.select_related(
            'player',
            'match',
            'match__club',
            'match__source_fixture__schedule',
            'match__source_fixture__age_bracket',
        ).filter(player=player)
        if from_date:
            match_base = match_base.filter(match__played_on__gte=from_date)
        if to_date:
            match_base = match_base.filter(match__played_on__lte=to_date)

        regular_rows = []
        if include('regular_match'):
            regular_rows = limited(
                match_base.exclude(match__category=MatchCategory.TOURNAMENT),
                limit,
            )
        tournament_rows = []
        if include('tournament'):
            tournament_rows = limited(
                match_base.filter(
                    match__category=MatchCategory.TOURNAMENT,
                    match__source_fixture__isnull=False,
                ),
                limit,
            )

        assessment_data = (
            {
                'summary': build_assessment_growth(assessment_rows),
                'history': PlayerAssessmentSnapshotSerializer(assessment_rows, many=True).data,
                'framework': framework_for(
                    player.player_profile.age_tier,
                    player.player_profile.position,
                ),
                'developmentSummary': build_development_assessment_growth(development_rows),
                'developmentHistory': PlayerDevelopmentAssessmentSerializer(
                    development_rows, many=True
                ).data,
                # Player Stats deliberately remains a separate 0–99, gamified
                # stream; the formal 1–5 framework above is never combined with it.
                'playerStatsHistory': PlayerStatsAssessmentSerializer(
                    player_stats_rows, many=True
                ).data,
            }
            if include('assessment')
            else None
        )

        training_groups = build_training_groups(training_rows)
        if include('training'):
            for group in training_groups:
                rows = [row for row in training_rows if row.session.focus == group['focus']]
                group['history'] = AttendanceSerializer(rows, many=True).data

        regular_data = (
            {
                **build_match_growth(regular_rows),
                'history': PlayerMatchPerformanceSerializer(
                    regular_rows, many=True, context={'request': request}
                ).data,
            }
            if include('regular_match')
            else None
        )

        tournament_groups = build_tournament_groups(tournament_rows)
        if include('tournament'):
            for group in tournament_groups:
                rows = [
                    row
                    for row in tournament_rows
                    if str(row.match.source_fixture.schedule_id) == group['tournamentId']
                    and (
                        str(row.match.source_fixture.age_bracket_id)
                        if row.match.source_fixture.age_bracket_id
                        else None
                    )
                    == group['ageBracketId']
                ]
                group['growth'] = build_match_growth(rows)
                group['history'] = PlayerMatchPerformanceSerializer(
                    rows, many=True, context={'request': request}
                ).data

        name = f'{player.first_name} {player.last_name}'.strip()
        return Response(
            {
                'playerId': str(player.id),
                'playerName': name or player.email.split('@')[0],
                'position': player.player_profile.position,
                'filter': {
                    'range': selected['range'],
                    'from': from_date.isoformat() if from_date else None,
                    'to': to_date.isoformat() if to_date else None,
                    'category': category,
                },
                'assessments': assessment_data,
                'training': {'groups': training_groups} if include('training') else None,
                'regularMatches': regular_data,
                'tournaments': {'groups': tournament_groups} if include('tournament') else None,
            }
        )


class SquadProgressView(APIView):
    """GET /api/progress/squad/ — per-player attendance and effort aggregates
    for the requester's club: the data behind the coach's Progress tab.

    Coach sees only their own club; Super Admin sees every club. One aggregate
    query, not one per player.
    """

    def get(self, request):
        if request.user.role not in (Roles.COACH, Roles.ADMIN):
            raise PermissionDenied('Only Coaches and the Super Admin can view squad progress.')

        profiles = PlayerProfile.objects.select_related('user')
        attendance = Attendance.objects.all()
        if request.user.role == Roles.COACH:
            if request.user.club_id is None:
                profiles = profiles.none()
                attendance = attendance.none()
            else:
                profiles = profiles.filter(user__club_id=request.user.club_id)
                attendance = attendance.filter(player__club_id=request.user.club_id)
        profiles = profiles.order_by('user__first_name', 'user__last_name')
        stats = {
            row['player_id']: row
            for row in attendance.values('player_id').annotate(
                present=Count('id', filter=Q(status=AttendanceStatus.PRESENT)),
                absent=Count('id', filter=Q(status=AttendanceStatus.ABSENT)),
                excused=Count('id', filter=Q(status=AttendanceStatus.EXCUSED)),
                avg_effort=Avg('effort'),
            )
        }

        def row(profile):
            s = stats.get(profile.user_id, {})
            avg_effort = s.get('avg_effort')
            return {
                'id': str(profile.user_id),
                'name': (
                    f'{profile.user.first_name} {profile.user.last_name}'.strip()
                    or profile.user.email.split('@')[0]
                    or f'Player {profile.user_id}'
                ),
                'position': profile.position,
                'ageTier': profile.age_tier,
                'present': s.get('present', 0),
                'absent': s.get('absent', 0),
                'excused': s.get('excused', 0),
                'avgEffort': (round(avg_effort) if avg_effort is not None else None),
            }

        return Response([row(p) for p in profiles])
