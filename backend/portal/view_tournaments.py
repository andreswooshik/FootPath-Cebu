"""Portal controllers — thin: parse the request, call a service, render.

Business rules and tenancy live in `portal.services`; role/auth policy in
`portal.decorators`. Every coordinator/staff query derives its club from
`request.user.club`, never from client input.
"""

from django.contrib import messages
from django.core.exceptions import PermissionDenied, ValidationError
from django.db import transaction
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone

from academy.models import (
    AuditLog,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
)
from academy.schedule_conflicts import (
    cancel_conflicting_training,
    conflicting_training_for_fixtures,
)
from academy.storage import (
    delete_tournament_document,
    sanitized_tournament_document_bytes,
    signed_tournament_document_url,
    upload_tournament_document,
    validate_tournament_document,
)
from academy.tournament_results import complete_tournament_fixture
from academy.transactions import club_write_transaction
from accounts.models import Roles

from .decorators import portal_role_required
from .forms import (
    TournamentAgeBracketForm,
    TournamentDocumentForm,
    TournamentFixtureForm,
    TournamentFixtureResultForm,
    TournamentScheduleForm,
)


def _coordinator_schedule(request, schedule_id):
    return get_object_or_404(
        TournamentSchedule.objects.select_related('club', 'uploaded_by'),
        pk=schedule_id,
        club_id=request.user.club_id,
    )


@portal_role_required(Roles.COORDINATOR)
@club_write_transaction
def tournament_schedules(request):
    """List shared schedules and create a document-optional draft."""
    form = TournamentScheduleForm(request.POST or None, request.FILES or None)
    if request.method == 'POST' and form.is_valid():
        document = form.cleaned_data['document']
        content_type = validate_tournament_document(document) if document else None
        schedule = None
        document_path = ''
        try:
            with transaction.atomic():
                schedule = TournamentSchedule.objects.create(
                    club=request.user.club,
                    title=form.cleaned_data['title'],
                    venue=form.cleaned_data['venue'],
                    starts_on=form.cleaned_data['starts_on'],
                    uploaded_by=request.user,
                    is_published=False,
                    published_at=None,
                )
                if document:
                    document_path = upload_tournament_document(
                        request.user.club_id,
                        schedule.id,
                        sanitized_tournament_document_bytes(
                            document,
                            content_type,
                        ),
                        content_type,
                    )
                    schedule.document_path = document_path
                    schedule.save(update_fields=['document_path', 'updated_at'])
                AuditLog.record(
                    request.user,
                    'tournament.draft_created',
                    target=schedule.title,
                    detail=(
                        'Official schedule uploaded.'
                        if document
                        else 'Created without an official document.'
                    ),
                )
        except RuntimeError as exc:
            if document_path:
                delete_tournament_document(document_path)
            form.add_error('document', str(exc))
        else:
            messages.success(request, f'{schedule.title} was saved as a draft.')
            return redirect('portal:tournament-detail', schedule_id=schedule.id)

    schedules = TournamentSchedule.objects.filter(club_id=request.user.club_id).prefetch_related(
        'fixtures'
    )
    return render(
        request,
        'portal/tournament_schedules.html',
        {
            'form': form,
            'schedules': schedules,
        },
    )


@portal_role_required(Roles.COORDINATOR)
@club_write_transaction
def tournament_schedule_detail(request, schedule_id):
    schedule = _coordinator_schedule(request, schedule_id)
    document_form = TournamentDocumentForm()
    bracket_form = TournamentAgeBracketForm(prefix='bracket', schedule=schedule)
    fixture_form = TournamentFixtureForm(prefix='fixture', schedule=schedule)
    conflict_confirmation_action = None
    conflict_count = 0

    if request.method == 'POST':
        action = request.POST.get('action')
        if action == 'publish':
            errors = schedule.publication_errors()
            if errors:
                for message in errors.values():
                    messages.error(request, message)
            elif not schedule.is_published:
                fixtures = list(
                    schedule.fixtures.select_related(
                        'schedule',
                        'age_bracket',
                    )
                )
                conflicts = conflicting_training_for_fixtures(fixtures)
                if conflicts and not request.POST.get('confirmTrainingCancellations'):
                    conflict_confirmation_action = 'publish'
                    conflict_count = len(conflicts)
                    messages.warning(
                        request,
                        f'Publishing will cancel {conflict_count} conflicting '
                        'future training session(s). Review and confirm below.',
                    )
                else:
                    with transaction.atomic():
                        schedule = TournamentSchedule.objects.select_for_update(of=('self',)).get(
                            pk=schedule.pk,
                        )
                        fixtures = list(
                            TournamentFixture.objects.select_for_update(of=('self',))
                            .select_related('schedule', 'age_bracket')
                            .filter(schedule=schedule)
                        )
                        schedule.is_published = True
                        schedule.published_at = timezone.now()
                        schedule.save(
                            update_fields=[
                                'is_published',
                                'published_at',
                                'updated_at',
                            ]
                        )
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
                    messages.success(request, 'Tournament published to the club.')
                    return redirect('portal:tournament-detail', schedule_id=schedule.id)
        elif action == 'add-bracket':
            bracket_form = TournamentAgeBracketForm(
                request.POST,
                prefix='bracket',
                schedule=schedule,
            )
            if bracket_form.is_valid():
                bracket = bracket_form.save(commit=False)
                bracket.schedule = schedule
                bracket.save()
                AuditLog.record(
                    request.user,
                    'tournament.bracket_added',
                    target=f'{schedule.title} {bracket.label}',
                )
                messages.success(request, 'Age bracket added.')
                return redirect('portal:tournament-detail', schedule_id=schedule.id)
        elif action == 'remove-document':
            old_path = schedule.document_path
            if old_path:
                schedule.document_path = ''
                schedule.save(update_fields=['document_path', 'updated_at'])
                delete_tournament_document(old_path)
                AuditLog.record(
                    request.user,
                    'tournament.document_removed',
                    target=schedule.title,
                )
                messages.success(request, 'Schedule document removed.')
            return redirect('portal:tournament-detail', schedule_id=schedule.id)
        elif action == 'replace-document':
            document_form = TournamentDocumentForm(request.POST, request.FILES)
            if document_form.is_valid():
                document = document_form.cleaned_data['document']
                content_type = validate_tournament_document(document)
                old_path = schedule.document_path
                try:
                    new_path = upload_tournament_document(
                        request.user.club_id,
                        schedule.id,
                        sanitized_tournament_document_bytes(
                            document,
                            content_type,
                        ),
                        content_type,
                    )
                except RuntimeError as exc:
                    document_form.add_error('document', str(exc))
                else:
                    schedule.document_path = new_path
                    schedule.uploaded_by = request.user
                    schedule.save(
                        update_fields=[
                            'document_path',
                            'uploaded_by',
                            'updated_at',
                        ]
                    )
                    if old_path and old_path != new_path:
                        delete_tournament_document(old_path)
                    AuditLog.record(
                        request.user,
                        'tournament.document_updated',
                        target=schedule.title,
                    )
                    messages.success(request, 'Schedule document replaced.')
                    return redirect('portal:tournament-detail', schedule_id=schedule.id)
        elif action == 'add-fixture':
            fixture_form = TournamentFixtureForm(
                request.POST,
                prefix='fixture',
                schedule=schedule,
            )
            if fixture_form.is_valid():
                fixture = fixture_form.save(commit=False)
                fixture.schedule = schedule
                conflicts = (
                    conflicting_training_for_fixtures([fixture]) if schedule.is_published else []
                )
                if conflicts and not request.POST.get('confirmTrainingCancellations'):
                    conflict_confirmation_action = 'add-fixture'
                    conflict_count = len(conflicts)
                    messages.warning(
                        request,
                        f'Adding this fixture will cancel {conflict_count} '
                        'conflicting future training session(s). Confirm below.',
                    )
                else:
                    with transaction.atomic():
                        fixture.save()
                        if schedule.is_published:
                            cancel_conflicting_training(
                                [fixture],
                                actor=request.user,
                                action='tournament.fixture_created',
                            )
                        AuditLog.record(
                            request.user,
                            'tournament.fixture_created',
                            target=fixture.opponent,
                            detail=(f'{schedule.title} - {fixture.kickoff_at.isoformat()}'),
                        )
                    messages.success(request, 'Fixture added to the tournament.')
                    return redirect('portal:tournament-detail', schedule_id=schedule.id)

    return render(
        request,
        'portal/tournament_schedule_detail.html',
        {
            'schedule': schedule,
            'lifecycle_status': schedule.lifecycle_status,
            'document_url': signed_tournament_document_url(schedule.document_path),
            'document_form': document_form,
            'bracket_form': bracket_form,
            'fixture_form': fixture_form,
            'conflict_confirmation_action': conflict_confirmation_action,
            'conflict_count': conflict_count,
            'fixtures': schedule.fixtures.select_related(
                'completed_match',
                'age_bracket',
            ),
        },
    )


@portal_role_required(Roles.COORDINATOR)
@club_write_transaction
def tournament_fixture_edit(request, fixture_id):
    fixture = get_object_or_404(
        TournamentFixture.objects.select_related('schedule'),
        pk=fixture_id,
        schedule__club_id=request.user.club_id,
    )
    if fixture.completed_match_id:
        messages.error(request, 'A completed fixture can no longer be edited.')
        return redirect('portal:tournament-detail', schedule_id=fixture.schedule_id)
    form = TournamentFixtureForm(
        request.POST or None,
        instance=fixture,
        schedule=fixture.schedule,
    )
    conflict_count = 0
    if request.method == 'POST' and form.is_valid():
        candidate = form.save(commit=False)
        conflicts = (
            conflicting_training_for_fixtures([candidate]) if fixture.schedule.is_published else []
        )
        if conflicts and not request.POST.get('confirmTrainingCancellations'):
            conflict_count = len(conflicts)
            messages.warning(
                request,
                f'This change will cancel {conflict_count} conflicting future '
                'training session(s). Review and confirm below.',
            )
        else:
            with transaction.atomic():
                fixture = form.save()
                if fixture.schedule.is_published:
                    cancel_conflicting_training(
                        [fixture],
                        actor=request.user,
                        action='tournament.fixture_updated',
                    )
                AuditLog.record(
                    request.user,
                    'tournament.fixture_updated',
                    target=fixture.opponent,
                    detail=fixture.schedule.title,
                )
            messages.success(request, 'Fixture updated.')
            return redirect('portal:tournament-detail', schedule_id=fixture.schedule_id)
    return render(
        request,
        'portal/tournament_fixture_form.html',
        {
            'form': form,
            'fixture': fixture,
            'conflict_count': conflict_count,
        },
    )


@portal_role_required(Roles.COORDINATOR)
@club_write_transaction
def tournament_fixture_delete(request, fixture_id):
    fixture = get_object_or_404(
        TournamentFixture.objects.select_related('schedule'),
        pk=fixture_id,
        schedule__club_id=request.user.club_id,
    )
    if request.method != 'POST':
        raise PermissionDenied('Fixture deletion requires confirmation.')
    schedule_id = fixture.schedule_id
    if fixture.completed_match_id:
        messages.error(request, 'A completed fixture cannot be deleted.')
    else:
        AuditLog.record(
            request.user,
            'tournament.fixture_deleted',
            target=fixture.opponent,
            detail=fixture.schedule.title,
        )
        fixture.delete()
        messages.success(request, 'Fixture deleted.')
    return redirect('portal:tournament-detail', schedule_id=schedule_id)


@portal_role_required(Roles.COORDINATOR)
@club_write_transaction
def tournament_fixture_result(request, fixture_id):
    fixture = get_object_or_404(
        TournamentFixture.objects.select_related(
            'schedule',
            'age_bracket',
        ),
        pk=fixture_id,
        schedule__club_id=request.user.club_id,
    )
    if fixture.completed_match_id:
        messages.error(request, 'This fixture already has a recorded result.')
        return redirect('portal:tournament-detail', schedule_id=fixture.schedule_id)
    form = TournamentFixtureResultForm(
        request.POST or None,
        fixture=fixture,
    )
    if request.method == 'POST' and form.is_valid():
        try:
            with transaction.atomic():
                locked_fixture = get_object_or_404(
                    TournamentFixture.objects.select_for_update(of=('self',)).select_related(
                        'schedule',
                        'age_bracket',
                    ),
                    pk=fixture.id,
                    schedule__club_id=request.user.club_id,
                )
                complete_tournament_fixture(
                    fixture=locked_fixture,
                    actor=request.user,
                    payload=form.result_payload,
                )
        except ValidationError as exc:
            for message in exc.messages:
                form.add_error(None, message)
        else:
            messages.success(
                request,
                'Result and player statistics were recorded.',
            )
            return redirect('portal:tournament-detail', schedule_id=fixture.schedule_id)
    return render(
        request,
        'portal/tournament_fixture_result.html',
        {
            'fixture': fixture,
            'form': form,
        },
    )


@portal_role_required(Roles.COORDINATOR)
@club_write_transaction
def tournament_bracket_delete(request, bracket_id):
    bracket = get_object_or_404(
        TournamentAgeBracket.objects.select_related('schedule'),
        pk=bracket_id,
        schedule__club_id=request.user.club_id,
    )
    if request.method != 'POST':
        raise PermissionDenied('Age-bracket deletion requires confirmation.')
    schedule = bracket.schedule
    if schedule.is_published:
        messages.error(request, 'Published tournament brackets cannot be removed.')
    elif bracket.fixtures.exists():
        messages.error(request, 'Remove linked fixtures before this bracket.')
    elif hasattr(bracket, 'squad') and bracket.squad.entries.exists():
        messages.error(request, 'Remove roster members before this bracket.')
    else:
        target = f'{schedule.title} {bracket.label}'
        bracket.delete()
        AuditLog.record(
            request.user,
            'tournament.bracket_removed',
            target=target,
        )
        messages.success(request, 'Age bracket removed.')
    return redirect('portal:tournament-detail', schedule_id=schedule.id)


@portal_role_required(Roles.COORDINATOR)
@club_write_transaction
def tournament_schedule_delete(request, schedule_id):
    schedule = _coordinator_schedule(request, schedule_id)
    if request.method != 'POST':
        raise PermissionDenied('Tournament deletion requires confirmation.')
    if schedule.fixtures.filter(completed_match__isnull=False).exists():
        messages.error(
            request,
            'This tournament has completed matches and cannot be deleted.',
        )
        return redirect('portal:tournament-detail', schedule_id=schedule.id)
    document_path = schedule.document_path
    AuditLog.record(request.user, 'tournament.deleted', target=schedule.title)
    schedule.delete()
    delete_tournament_document(document_path)
    messages.success(request, 'Tournament schedule deleted.')
    return redirect('portal:tournaments')
