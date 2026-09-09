"""Tournament bracket and squad API views."""

from ._view_support import *  # noqa: F401,F403
from .view_tournaments import (
    _coordinator_mobile_schedule,
    _tournament_schedule_data,
)

class TournamentAgeBracketCreateView(APIView):
    """Add one flexible U-age bracket to a Coordinator's tournament."""

    def post(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        serializer = TournamentAgeBracketWriteSerializer(
            data=request.data,
            context={'schedule': schedule},
        )
        serializer.is_valid(raise_exception=True)
        bracket = serializer.save(schedule=schedule)
        TournamentSchedule.objects.filter(pk=schedule.pk).update(
            updated_at=timezone.now()
        )
        AuditLog.record(
            request.user,
            'tournament.bracket_added',
            target=f'{schedule.title} {bracket.label}',
            detail=bracket.scheduled_at or 'Schedule time TBD',
        )
        schedule.refresh_from_db()
        return Response(
            _tournament_schedule_data(schedule, request),
            status=status.HTTP_201_CREATED,
        )


def _coordinator_mobile_bracket(user, bracket_id, *, lock=False):
    if user.role != Roles.COORDINATOR:
        raise PermissionDenied('Only Coordinators can manage age brackets.')
    if user.club_id is None:
        raise PermissionDenied('Coordinator account must belong to a club.')
    queryset = TournamentAgeBracket.objects.select_related('schedule')
    if lock:
        queryset = queryset.select_for_update()
    return get_object_or_404(
        queryset,
        pk=bracket_id,
        schedule__club_id=user.club_id,
    )


class TournamentAgeBracketDetailView(APIView):
    def patch(self, request, bracket_id):
        with transaction.atomic():
            bracket = _coordinator_mobile_bracket(
                request.user, bracket_id, lock=True,
            )
            serializer = TournamentAgeBracketWriteSerializer(
                bracket,
                data=request.data,
                partial=True,
                context={'schedule': bracket.schedule},
            )
            serializer.is_valid(raise_exception=True)
            bracket = serializer.save()
            invalid = [
                (entry, result)
                for entry, result in invalid_squad_entries(bracket)
                if result.code in ('OVERAGE', 'DOB_REQUIRED', 'PROFILE_REQUIRED')
            ]
            if invalid:
                names = ', '.join(
                    entry.player.get_full_name() or entry.player.email
                    for entry, _ in invalid
                )
                raise ValidationError({
                    'maxAge': f'Roster members must be reviewed first: {names}.'
                })
            if bracket.schedule.is_published:
                fixtures = list(
                    TournamentFixture.objects.select_for_update().select_related(
                        'schedule', 'age_bracket',
                    ).filter(age_bracket=bracket)
                )
                conflicts = conflicting_training_for_fixtures(
                    fixtures, lock=True,
                )
                if conflicts and not _confirmed(request):
                    raise WorkflowConflict(
                        'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
                        'Changing this bracket association will cancel '
                        'conflicting future training sessions. Confirm to '
                        'continue.',
                        cancellation=_training_cancellation_details(conflicts),
                    )
                cancel_conflicting_training(
                    fixtures,
                    actor=request.user,
                    action='tournament.bracket_updated',
                )
        TournamentSchedule.objects.filter(pk=bracket.schedule_id).update(
            updated_at=timezone.now()
        )
        AuditLog.record(
            request.user,
            'tournament.bracket_updated',
            target=f'{bracket.schedule.title} {bracket.label}',
            detail=bracket.scheduled_at or 'Schedule time TBD',
        )
        bracket.schedule.refresh_from_db()
        return Response(_tournament_schedule_data(bracket.schedule, request))

    def delete(self, request, bracket_id):
        bracket = _coordinator_mobile_bracket(request.user, bracket_id)
        schedule = bracket.schedule
        if schedule.is_published:
            raise ValidationError({
                'ageBracket': 'Published tournament brackets cannot be removed.'
            })
        if bracket.fixtures.exists():
            raise ValidationError({
                'ageBracket': 'Remove linked fixtures before deleting this bracket.'
            })
        try:
            squad_has_entries = bracket.squad.entries.exists()
        except TournamentSquad.DoesNotExist:
            squad_has_entries = False
        if squad_has_entries:
            raise ValidationError({
                'ageBracket': 'Remove roster members before deleting this bracket.'
            })
        target = f'{schedule.title} {bracket.label}'
        bracket.delete()
        TournamentSchedule.objects.filter(pk=schedule.pk).update(
            updated_at=timezone.now()
        )
        AuditLog.record(
            request.user,
            'tournament.bracket_removed',
            target=target,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


def _mobile_tournament_bracket(user, bracket_id):
    allowed = (
        Roles.COORDINATOR,
        Roles.COACH,
        Roles.PLAYER,
        Roles.GUARDIAN,
        Roles.ADMIN,
    )
    if user.role not in allowed:
        raise PermissionDenied('Your role cannot view tournament rosters.')
    brackets = TournamentAgeBracket.objects.select_related(
        'schedule', 'schedule__club',
    )
    if user.role != Roles.ADMIN:
        if user.club_id is None:
            raise PermissionDenied('Your account must belong to a club.')
        brackets = brackets.filter(schedule__club_id=user.club_id)
    bracket = get_object_or_404(brackets, pk=bracket_id)
    if (
        user.role not in (Roles.COACH, Roles.COORDINATOR, Roles.ADMIN)
        and not bracket.schedule.is_published
    ):
        raise PermissionDenied('This tournament has not been published.')
    return bracket


def _squad_data(squad, request):
    return TournamentSquadSerializer(
        squad,
        context={'request': request},
    ).data


class TournamentSquadDetailView(APIView):
    """Read a role-visible roster or atomically save it as a Coach."""

    def get(self, request, bracket_id):
        bracket = _mobile_tournament_bracket(request.user, bracket_id)
        try:
            squad = TournamentSquad.objects.prefetch_related(
                'entries__player__player_profile',
            ).get(bracket=bracket)
        except TournamentSquad.DoesNotExist:
            if request.user.role not in (
                Roles.COACH, Roles.COORDINATOR, Roles.ADMIN,
            ):
                raise PermissionDenied('No published roster is available.')
            return Response({
                'id': None,
                'bracketId': str(bracket.id),
                'status': TournamentSquadStatus.DRAFT,
                'publishedAt': None,
                'entries': [],
            })
        if (
            squad.status != TournamentSquadStatus.PUBLISHED
            and request.user.role not in (
                Roles.COACH, Roles.COORDINATOR, Roles.ADMIN,
            )
        ):
            raise PermissionDenied('No published roster is available.')
        return Response(_squad_data(squad, request))

    def put(self, request, bracket_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only Coaches can manage tournament rosters.')
        bracket = _mobile_tournament_bracket(request.user, bracket_id)
        serializer = TournamentSquadWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        rows = serializer.validated_data['entries']
        player_ids = [row['playerId'] for row in rows]
        players = {
            player.id: player
            for player in User.objects.filter(
                id__in=player_ids,
                role=Roles.PLAYER,
                club_id=request.user.club_id,
                is_active=True,
            ).select_related('player_profile')
        }
        missing = sorted(set(player_ids) - set(players))
        if missing:
            raise ValidationError({
                'entries': f'Unknown or inactive club player IDs: {missing}.'
            })
        blocked = {
            player_id: result.reason
            for player_id, player in players.items()
            if (result := roster_eligibility(player, bracket)).blocked
        }
        if blocked:
            raise ValidationError({'entries': blocked})

        with transaction.atomic():
            squad, _ = TournamentSquad.objects.select_for_update().get_or_create(
                bracket=bracket,
                defaults={'updated_by': request.user},
            )
            if squad.status == TournamentSquadStatus.PUBLISHED:
                raise WorkflowConflict(
                    'ROSTER_LOCKED',
                    'This roster has been published and can no longer be changed.',
                )
            current = {
                entry.player_id: entry
                for entry in squad.entries.select_related('player')
            }
            incoming = set(player_ids)
            removed = set(current) - incoming
            added = incoming - set(current)
            changed_positions = []
            if removed:
                squad.entries.filter(player_id__in=removed).delete()
            for row in rows:
                player_id = row['playerId']
                position = row.get('position', '')
                entry = current.get(player_id)
                if entry is None:
                    TournamentSquadEntry.objects.create(
                        squad=squad,
                        player=players[player_id],
                        position=position,
                        added_by=request.user,
                    )
                elif entry.position != position:
                    entry.position = position
                    entry.save(update_fields=['position', 'updated_at'])
                    changed_positions.append(player_id)
            squad.updated_by = request.user
            squad.save(update_fields=['updated_by', 'updated_at'])
            AuditLog.record(
                request.user,
                'tournament.squad_saved',
                target=f'{bracket.schedule.title} {bracket.label}',
                detail=(
                    f'added={sorted(added)}; removed={sorted(removed)}; '
                    f'positions={sorted(changed_positions)}'
                ),
            )
        squad = TournamentSquad.objects.prefetch_related(
            'entries__player__player_profile',
        ).get(pk=squad.pk)
        return Response(_squad_data(squad, request))


class TournamentSquadCandidatesView(APIView):
    """Coach-only player choices with privacy-safe eligibility outcomes."""

    def get(self, request, bracket_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only Coaches can select roster members.')
        bracket = _mobile_tournament_bracket(request.user, bracket_id)
        try:
            squad = bracket.squad
            selected = {
                entry.player_id: entry.position
                for entry in squad.entries.all()
            }
        except TournamentSquad.DoesNotExist:
            selected = {}
        players = User.objects.filter(
            role=Roles.PLAYER,
            club_id=request.user.club_id,
            is_active=True,
        ).select_related('player_profile').order_by(
            'last_name', 'first_name', 'email',
        )
        data = []
        for player in players:
            result = roster_eligibility(player, bracket)
            name = player.get_full_name().strip() or player.email.split('@')[0]
            try:
                current_position = player.player_profile.position
            except PlayerProfile.DoesNotExist:
                current_position = ''
            data.append({
                'playerId': str(player.id),
                'playerName': name,
                'currentPosition': current_position,
                'eligibility': result.state,
                'eligibilityCode': result.code,
                'eligibilityReason': result.reason,
                'selected': player.id in selected,
                'tournamentPosition': selected.get(player.id, ''),
            })
        return Response(data)


class TournamentSquadPublishView(APIView):
    def post(self, request, bracket_id):
        if request.user.role != Roles.COACH:
            raise PermissionDenied('Only Coaches can publish tournament rosters.')
        bracket = _mobile_tournament_bracket(request.user, bracket_id)
        if not bracket.schedule.is_published:
            raise ValidationError({
                'tournament': 'The Coordinator must publish the tournament first.'
            })
        with transaction.atomic():
            squad = get_object_or_404(
                TournamentSquad.objects.select_for_update().prefetch_related(
                    'entries__player__player_profile',
                ),
                bracket=bracket,
            )
            if squad.status == TournamentSquadStatus.PUBLISHED:
                raise WorkflowConflict(
                    'ROSTER_ALREADY_PUBLISHED',
                    'This roster has already been published.',
                )
            entries = list(squad.entries.all())
            if not entries:
                raise ValidationError({'entries': 'Add at least one player first.'})
            blocked = {
                str(entry.player_id): result.reason
                for entry in entries
                if (result := roster_eligibility(entry.player, bracket)).blocked
            }
            if blocked:
                raise ValidationError({'entries': blocked})
            squad.status = TournamentSquadStatus.PUBLISHED
            squad.published_at = timezone.now()
            squad.updated_by = request.user
            squad.save(update_fields=[
                'status', 'published_at', 'updated_by', 'updated_at',
            ])
            AuditLog.record(
                request.user,
                'tournament.squad_published',
                target=f'{bracket.schedule.title} {bracket.label}',
                detail=f'{len(entries)} players',
            )
            transaction.on_commit(
                lambda: notify_tournament_roster_published(squad)
            )
        return Response(_squad_data(squad, request))
