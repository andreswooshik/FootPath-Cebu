"""Domain-focused API views extracted from the legacy view module."""

from ._view_support import *  # noqa: F401,F403

def _tournament_schedule_data(value, request, *, many=False):
    return TournamentScheduleSerializer(
        value,
        many=many,
        context={'request': request},
    ).data


class TournamentScheduleListView(APIView):
    """Role-aware tournament list and Coordinator draft creation."""

    _roles = (
        Roles.COORDINATOR,
        Roles.COACH,
        Roles.PLAYER,
        Roles.GUARDIAN,
        Roles.ADMIN,
    )

    def get(self, request):
        if request.user.role not in self._roles:
            raise PermissionDenied(
                'Your role cannot view mobile tournament schedules.'
            )
        schedules = (
            TournamentSchedule.objects.all()
            .select_related('club')
            .prefetch_related(
                Prefetch(
                    'fixtures',
                    queryset=TournamentFixture.objects.select_related(
                        'age_bracket', 'completed_match',
                    ),
                ),
                'age_brackets__squad__entries__player__player_profile',
            )
        )
        if request.user.role == Roles.ADMIN:
            pass
        elif request.user.club_id is None:
            schedules = schedules.none()
        else:
            schedules = schedules.filter(club_id=request.user.club_id)
            if request.user.role != Roles.COORDINATOR:
                schedules = schedules.filter(is_published=True)
        return Response(
            _tournament_schedule_data(schedules, request, many=True)
        )

    def post(self, request):
        if request.user.role != Roles.COORDINATOR:
            raise PermissionDenied('Only Coordinators can create tournaments.')
        if request.user.club_id is None:
            raise PermissionDenied('Coordinator account must belong to a club.')
        serializer = TournamentScheduleWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        document = request.FILES.get('document')
        content_type = None
        if document is not None:
            try:
                content_type = validate_tournament_document(document)
            except ValueError as exc:
                raise ValidationError({'document': str(exc)}) from exc
        document_path = ''
        try:
            with transaction.atomic():
                schedule = serializer.save(
                    club=request.user.club,
                    uploaded_by=request.user,
                    is_published=False,
                    published_at=None,
                )
                if document is not None:
                    document_path = upload_tournament_document(
                        request.user.club_id,
                        schedule.id,
                        sanitized_tournament_document_bytes(
                            document, content_type,
                        ),
                        content_type,
                    )
                    schedule.document_path = document_path
                    schedule.save(update_fields=['document_path', 'updated_at'])
        except RuntimeError as exc:
            if document_path:
                delete_tournament_document(document_path)
            raise ValidationError({'document': str(exc)}) from exc
        AuditLog.record(
            request.user,
            'tournament.draft_created',
            target=schedule.title,
            detail=(
                f'{schedule.starts_on} | '
                f'{"document uploaded" if document else "manual schedule"}'
            ),
        )
        return Response(
            _tournament_schedule_data(schedule, request),
            status=status.HTTP_201_CREATED,
        )


def _coordinator_mobile_schedule(user, schedule_id, *, lock=False):
    if user.role != Roles.COORDINATOR:
        raise PermissionDenied('Only Coordinators can manage tournaments.')
    if user.club_id is None:
        raise PermissionDenied('Coordinator account must belong to a club.')
    queryset = TournamentSchedule.objects.prefetch_related(
            Prefetch(
                'fixtures',
                queryset=TournamentFixture.objects.select_related(
                    'age_bracket', 'completed_match',
                ),
            ),
            'age_brackets__squad__entries__player__player_profile',
        )
    if lock:
        queryset = queryset.select_for_update()
    return get_object_or_404(
        queryset,
        pk=schedule_id,
        club_id=user.club_id,
    )


class TournamentScheduleDetailView(APIView):
    """Read, edit, or safely remove one Coordinator-owned tournament."""

    def get(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        return Response(_tournament_schedule_data(schedule, request))

    def patch(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        old_title = schedule.title
        old_date = schedule.starts_on
        with transaction.atomic():
            serializer = TournamentScheduleWriteSerializer(
                schedule, data=request.data, partial=True,
            )
            serializer.is_valid(raise_exception=True)
            schedule = serializer.save()
            invalid = []
            for bracket in schedule.age_brackets.all():
                invalid.extend(
                    (entry, result)
                    for entry, result in invalid_squad_entries(bracket)
                    if result.code in ('OVERAGE', 'DOB_REQUIRED', 'PROFILE_REQUIRED')
                )
            if invalid:
                names = ', '.join(
                    entry.player.get_full_name() or entry.player.email
                    for entry, _ in invalid
                )
                raise ValidationError({
                    'startsOn': f'Roster members must be reviewed first: {names}.'
                })
        AuditLog.record(
            request.user,
            'tournament.updated',
            target=schedule.title,
            detail=(
                f'{old_title} ({old_date}) -> '
                f'{schedule.title} ({schedule.starts_on})'
            ),
        )
        return Response(_tournament_schedule_data(schedule, request))

    def delete(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        if schedule.fixtures.filter(completed_match__isnull=False).exists():
            raise ValidationError({
                'tournament': (
                    'This tournament has completed matches and cannot be deleted.'
                )
            })
        target = schedule.title
        document_path = schedule.document_path
        schedule.delete()
        delete_tournament_document(document_path)
        AuditLog.record(request.user, 'tournament.deleted', target=target)
        return Response(status=status.HTTP_204_NO_CONTENT)


class TournamentSchedulePublishView(APIView):
    """Publish a configured tournament to the whole club."""

    def post(self, request, schedule_id):
        with transaction.atomic():
            schedule = _coordinator_mobile_schedule(
                request.user, schedule_id, lock=True,
            )
            errors = schedule.publication_errors()
            if errors:
                raise ValidationError(errors)
            if schedule.is_published:
                return Response(_tournament_schedule_data(schedule, request))
            fixtures = list(
                TournamentFixture.objects.select_for_update().select_related(
                    'schedule', 'age_bracket',
                ).filter(schedule=schedule)
            )
            conflicts = conflicting_training_for_fixtures(fixtures, lock=True)
            if conflicts and not _confirmed(request):
                raise WorkflowConflict(
                    'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
                    'Publishing this tournament will cancel conflicting future '
                    'training sessions. Confirm to continue.',
                    cancellation=_training_cancellation_details(conflicts),
                )
            schedule.is_published = True
            schedule.published_at = timezone.now()
            schedule.save(update_fields=[
                'is_published', 'published_at', 'updated_at',
            ])
            cancel_conflicting_training(
                fixtures,
                actor=request.user,
                action='tournament.published',
            )
            AuditLog.record(
                request.user,
                'tournament.published',
                target=schedule.title,
                detail=str(schedule.starts_on),
            )
        return Response(_tournament_schedule_data(schedule, request))


class TournamentScheduleDocumentView(APIView):
    """Replace or remove the private official schedule document."""

    throttle_scope = 'uploads'

    def post(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        document = request.FILES.get('document')
        if document is None:
            raise ValidationError({'document': 'Choose a document to upload.'})
        try:
            content_type = validate_tournament_document(document)
        except ValueError as exc:
            raise ValidationError({'document': str(exc)}) from exc
        old_path = schedule.document_path
        try:
            new_path = upload_tournament_document(
                request.user.club_id,
                schedule.id,
                sanitized_tournament_document_bytes(document, content_type),
                content_type,
            )
        except RuntimeError as exc:
            raise ValidationError({'document': str(exc)}) from exc
        schedule.document_path = new_path
        schedule.uploaded_by = request.user
        schedule.save(update_fields=[
            'document_path', 'uploaded_by', 'updated_at',
        ])
        if old_path and old_path != new_path:
            invalidate_signed_tournament_document_url(old_path)
            delete_tournament_document(old_path)
        invalidate_signed_tournament_document_url(new_path)
        AuditLog.record(
            request.user,
            'tournament.document_replaced' if old_path
            else 'tournament.document_uploaded',
            target=schedule.title,
        )
        return Response(_tournament_schedule_data(schedule, request))

    def delete(self, request, schedule_id):
        schedule = _coordinator_mobile_schedule(request.user, schedule_id)
        old_path = schedule.document_path
        if not old_path:
            return Response(status=status.HTTP_204_NO_CONTENT)
        schedule.document_path = ''
        schedule.save(update_fields=['document_path', 'updated_at'])
        invalidate_signed_tournament_document_url(old_path)
        delete_tournament_document(old_path)
        AuditLog.record(
            request.user,
            'tournament.document_removed',
            target=schedule.title,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class TournamentFixtureCreateView(APIView):
    """Add a manually-entered fixture to the shared tournament schedule."""

    def post(self, request, schedule_id):
        with transaction.atomic():
            schedule = _coordinator_mobile_schedule(
                request.user, schedule_id, lock=True,
            )
            serializer = TournamentFixtureWriteSerializer(
                data=request.data,
                context={'schedule': schedule},
            )
            serializer.is_valid(raise_exception=True)
            fixture = serializer.save(schedule=schedule)
            if schedule.is_published:
                conflicts = conflicting_training_for_fixtures(
                    [fixture], lock=True,
                )
                if conflicts and not _confirmed(request):
                    raise WorkflowConflict(
                        'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
                        'Adding this fixture will cancel conflicting future '
                        'training sessions. Confirm to continue.',
                        cancellation=_training_cancellation_details(conflicts),
                    )
                cancel_conflicting_training(
                    [fixture],
                    actor=request.user,
                    action='tournament.fixture_created',
                )
            AuditLog.record(
                request.user,
                'tournament.fixture_created',
                target=f'{schedule.title} vs {fixture.opponent}',
                detail=fixture.kickoff_at.isoformat(),
            )
        schedule.refresh_from_db()
        return Response(
            _tournament_schedule_data(schedule, request),
            status=status.HTTP_201_CREATED,
        )


def _coordinator_mobile_fixture(user, fixture_id, *, lock=False):
    if user.role != Roles.COORDINATOR:
        raise PermissionDenied('Only Coordinators can manage fixtures.')
    if user.club_id is None:
        raise PermissionDenied('Coordinator account must belong to a club.')
    queryset = TournamentFixture.objects.select_related(
        'schedule', 'age_bracket', 'completed_match',
    )
    if lock:
        queryset = queryset.select_for_update()
    return get_object_or_404(
        queryset,
        pk=fixture_id,
        schedule__club_id=user.club_id,
    )


class TournamentFixtureDetailView(APIView):
    def patch(self, request, fixture_id):
        with transaction.atomic():
            fixture = _coordinator_mobile_fixture(
                request.user, fixture_id, lock=True,
            )
            if (
                fixture.completed_match_id
                or fixture.status == FixtureStatus.COMPLETED
            ):
                raise ValidationError({
                    'fixture': 'A completed fixture\'s schedule cannot be edited.'
                })
            serializer = TournamentFixtureWriteSerializer(
                fixture,
                data=request.data,
                partial=True,
                context={'schedule': fixture.schedule},
            )
            serializer.is_valid(raise_exception=True)
            fixture = serializer.save()
            if fixture.schedule.is_published:
                conflicts = conflicting_training_for_fixtures(
                    [fixture], lock=True,
                )
                if conflicts and not _confirmed(request):
                    raise WorkflowConflict(
                        'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
                        'Rescheduling this fixture will cancel conflicting '
                        'future training sessions. Confirm to continue.',
                        cancellation=_training_cancellation_details(conflicts),
                    )
                cancel_conflicting_training(
                    [fixture],
                    actor=request.user,
                    action='tournament.fixture_updated',
                )
            AuditLog.record(
                request.user,
                'tournament.fixture_updated',
                target=f'{fixture.schedule.title} vs {fixture.opponent}',
                detail=fixture.kickoff_at.isoformat(),
            )
        fixture.schedule.refresh_from_db()
        return Response(_tournament_schedule_data(fixture.schedule, request))

    def delete(self, request, fixture_id):
        fixture = _coordinator_mobile_fixture(request.user, fixture_id)
        if fixture.completed_match_id or fixture.status == FixtureStatus.COMPLETED:
            raise ValidationError({
                'fixture': 'A completed fixture cannot be deleted.'
            })
        schedule = fixture.schedule
        target = f'{schedule.title} vs {fixture.opponent}'
        fixture.delete()
        AuditLog.record(
            request.user,
            'tournament.fixture_deleted',
            target=target,
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class TournamentFixtureResultView(APIView):
    """Atomically create the tournament match and all participant statistics."""

    def post(self, request, fixture_id):
        serializer = TournamentFixtureResultWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = serializer.validated_data
        with transaction.atomic():
            fixture = _coordinator_mobile_fixture(
                request.user, fixture_id, lock=True,
            )
            try:
                complete_tournament_fixture(
                    fixture=fixture,
                    actor=request.user,
                    payload=payload,
                )
            except DjangoValidationError as exc:
                raise ValidationError(exc.message_dict) from exc
        fixture.schedule.refresh_from_db()
        return Response(_tournament_schedule_data(fixture.schedule, request))

__all__ = [name for name in globals() if not name.startswith('__')]
