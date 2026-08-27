"""Portal controllers — thin: parse the request, call a service, render.

Business rules and tenancy live in `portal.services`; role/auth policy in
`portal.decorators`. Every coordinator/staff query derives its club from
`request.user.club`, never from client input.
"""
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.contrib.auth.views import PasswordChangeView
from django.contrib.messages.views import SuccessMessageMixin
from django.core.exceptions import PermissionDenied
from django.db import transaction
from django.db.models import Q
from django.shortcuts import redirect, render
from django.urls import reverse_lazy

from django.shortcuts import get_object_or_404

from academy.models import (
    AuditLog,
    DisputeStatus,
    Eligibility,
    EligibilityHistory,
    PlayerProfile,
    TournamentFixture,
    TournamentSchedule,
)
from academy.pin_service import reset_pin
from academy.storage import (
    delete_tournament_document,
    signed_tournament_document_url,
    upload_photo,
    upload_tournament_document,
    validate_photo_upload,
    validate_tournament_document,
)
from accounts.models import GuardianLink, Roles, User
from accounts.services import (
    ProvisioningError,
    enable_coordinator_mobile_access,
    sync_coordinator_mobile_password,
)

from .decorators import portal_role_required
from .forms import (
    CoordinatorMobileAccessForm,
    CoordinatorSignupForm,
    CreateCoachForm,
    CreateGuardianForm,
    CreatePlayerForm,
    CreateStaffForm,
    DisputeResponseForm,
    EligibilityUpdateForm,
    GuardianLinkForm,
    TournamentDocumentForm,
    TournamentFixtureForm,
    TournamentScheduleForm,
)
from .ratelimit import is_rate_limited
from .services import (
    create_club_account,
    link_guardian,
    register_coordinator,
    respond_to_dispute,
    set_player_eligibility,
    staff_dispute_queryset,
    unlink_guardian,
)

_ACCOUNT_FORMS = {
    'player': CreatePlayerForm,
    'coach': CreateCoachForm,
    'staff': CreateStaffForm,
    'guardian': CreateGuardianForm,
}


def _split_name(full_name):
    """Split a full name into the User model's first and last name fields."""
    parts = full_name.strip().split(None, 1)
    return parts[0], (parts[1] if len(parts) > 1 else '')


def signup(request):
    """Accept a club application and create an inactive coordinator login."""
    if request.user.is_authenticated:
        return redirect('portal:dashboard')
    if request.method == 'POST':
        if is_rate_limited(
            request, scope='signup', limit=5, window_seconds=3600
        ):
            messages.error(
                request,
                'Too many registration attempts from your network. Please try '
                'again later.',
            )
            return render(
                request,
                'portal/signup.html',
                {'form': CoordinatorSignupForm()},
                status=429,
            )

        form = CoordinatorSignupForm(request.POST, request.FILES)
        if form.is_valid():
            data = form.cleaned_data
            first_name, last_name = _split_name(data['coordinator_name'])
            register_coordinator(
                first_name=first_name,
                last_name=last_name,
                email=data['email'],
                club_name=data['club_name'],
                password=data['password1'],
                is_school_affiliated=data['is_school_affiliated'],
                school_name=data.get('school_name', ''),
                head_coach_name=data['head_coach_name'],
                coach_license=data['coach_license'],
                cvfa_membership=data['cvfa_membership'],
            )
            return redirect('portal:signup-done')
    else:
        form = CoordinatorSignupForm()
    return render(request, 'portal/signup.html', {'form': form})


def signup_done(request):
    return render(request, 'portal/signup_done.html')


@login_required
def dashboard(request):
    context = {}
    club = request.user.club

    if request.user.role == Roles.COORDINATOR and club:
        members = User.objects.filter(club=club)
        profiles = PlayerProfile.objects.filter(user__club=club)
        context['dashboard_stats'] = {
            'players': members.filter(role=Roles.PLAYER).count(),
            'coaches': members.filter(role=Roles.COACH).count(),
            'guardians': members.filter(role=Roles.GUARDIAN).count(),
            'unlinked_players': members.filter(
                role=Roles.PLAYER,
                player_links__isnull=True,
            ).count(),
            'missing_photos': profiles.filter(
                Q(photo_path='') | Q(photo_path__isnull=True)
            ).count(),
        }
    elif request.user.role == Roles.SCHOOL_STAFF and club:
        profiles = PlayerProfile.objects.filter(user__club=club)
        disputes = staff_dispute_queryset(staff=request.user)
        context['dashboard_stats'] = {
            'players': profiles.count(),
            'warnings': profiles.filter(
                eligibility=Eligibility.ACADEMIC_WARNING,
            ).count(),
            'not_eligible': profiles.filter(
                eligibility=Eligibility.NOT_ELIGIBLE,
            ).count(),
            'active_disputes': disputes.exclude(
                status__in=[DisputeStatus.RESOLVED, DisputeStatus.DISMISSED],
            ).count(),
        }
        context['recent_eligibility_changes'] = (
            EligibilityHistory.objects.select_related('player', 'changed_by')
            .filter(player__club=club)
            .order_by('-changed_at')[:5]
        )

    return render(request, 'portal/dashboard.html', context)


class PortalPasswordChangeView(SuccessMessageMixin, PasswordChangeView):
    """Change the signed-in portal user's password.

    Coordinators and School Staff arrive with a password provisioned by an
    authorized account creator. A linked Coordinator's Firebase password is
    updated before the local password so both login surfaces stay aligned.
    """

    template_name = 'portal/password_change.html'
    success_url = reverse_lazy('portal:dashboard')
    success_message = 'Your password has been changed.'

    def form_valid(self, form):
        try:
            sync_coordinator_mobile_password(
                self.request.user,
                password=form.cleaned_data['new_password1'],
            )
        except Exception:
            form.add_error(
                None,
                'The mobile password could not be updated. No password was changed.',
            )
            return self.form_invalid(form)
        return super().form_valid(form)


@portal_role_required(Roles.COORDINATOR)
def coordinator_mobile_access(request):
    form = CoordinatorMobileAccessForm(request.POST or None)
    if request.method == 'POST' and form.is_valid():
        try:
            created = enable_coordinator_mobile_access(
                request.user,
                password=form.cleaned_data['current_password'],
            )
        except ProvisioningError as exc:
            form.add_error('current_password', str(exc))
        except Exception:
            form.add_error(
                None,
                'Mobile access is temporarily unavailable. Please try again.',
            )
        else:
            AuditLog.record(
                request.user,
                'coordinator.mobile_enabled',
                target=request.user.email,
                detail=(
                    'Firebase identity created.'
                    if created else 'Firebase identity linked.'
                ),
            )
            messages.success(
                request,
                'Mobile access is enabled. Use the same email and password in the app.',
            )
            return redirect('portal:mobile-access')
    return render(request, 'portal/coordinator_mobile_access.html', {
        'form': form,
        'mobile_enabled': bool(request.user.firebase_uid),
    })


@portal_role_required(Roles.COORDINATOR)
def create_account(request):
    club = request.user.club
    # School staff exist only for school-affiliated clubs — drop the form
    # entirely so it can neither render nor be submitted (server-side gate).
    available = dict(_ACCOUNT_FORMS)
    if not club.allows_school_staff:
        available.pop('staff', None)
    forms = {
        key: cls(club=club, auto_id=f'id_{key}_%s')
        for key, cls in available.items()
    }
    active_tab = 'player'
    created = None

    if request.method == 'POST':
        account_type = request.POST.get('account_type')
        form_cls = available.get(account_type)
        if form_cls is None:
            messages.error(request, 'Unknown or unavailable account type.')
            return redirect('portal:create-account')

        active_tab = account_type
        form = form_cls(
            request.POST,
            club=club,
            auto_id=f'id_{account_type}_%s',
        )
        forms[account_type] = form
        if form.is_valid():
            try:
                user, credential = create_club_account(
                    account_type=account_type,
                    coordinator=request.user,
                    data=form.cleaned_data,
                )
            except ProvisioningError as exc:
                messages.error(request, str(exc))
            else:
                AuditLog.record(
                    request.user, 'account.created',
                    target=user.email or user.get_full_name() or user.username,
                    detail=user.role,
                )
                created = {
                    'email': user.email,
                    'display_name': user.get_full_name() or user.username,
                    'role': user.get_role_display(),
                    'credential': credential,
                    'is_web': account_type == 'staff',
                    'managed': account_type == 'player' and not user.email,
                    'account_type': account_type,
                }
                messages.success(
                    request,
                    (
                        f'{user.get_role_display()} profile created for '
                        f'{user.get_full_name() or user.username}.'
                        if not user.email else
                        f'{user.get_role_display()} account created for {user.email}.'
                    ),
                )
                # Reset the submitted tab's form so the fields clear.
                forms[account_type] = form_cls(
                    club=club,
                    auto_id=f'id_{account_type}_%s',
                )

    return render(
        request,
        'portal/create_account.html',
        {'forms': forms, 'active_tab': active_tab, 'created': created},
    )


@portal_role_required(Roles.COORDINATOR)
def players(request):
    roster = (
        PlayerProfile.objects.select_related('user')
        .filter(user__club=request.user.club)
        .order_by('user__last_name', 'user__first_name')
    )
    return render(request, 'portal/players.html', {'roster': roster})


@portal_role_required(Roles.COORDINATOR)
def player_pin_reset(request, player_id):
    if request.method != 'POST':
        return redirect('portal:players')
    profile = get_object_or_404(
        PlayerProfile.objects.select_related('user'),
        user_id=player_id, user__club=request.user.club,
    )
    reset_pin(profile.user)
    AuditLog.record(
        request.user, 'player_pin.reset', target=profile.user.email,
        detail='Coordinator portal',
    )
    messages.success(request, f'Privacy PIN reset for {profile.user.email}.')
    return redirect('portal:players')


@portal_role_required(Roles.COORDINATOR)
def coaches(request):
    club = request.user.club
    coach_list = User.objects.filter(
        club=club, role=Roles.COACH
    ).order_by('last_name', 'first_name')
    # There is no per-coach roster assignment anywhere in the schema — club
    # is the only tenancy boundary, so every coach in a club can coach/assess
    # every player in it. This is the same roster for every coach, not a
    # subset; the template says so explicitly rather than implying otherwise.
    roster = (
        PlayerProfile.objects.select_related('user')
        .filter(user__club=club)
        .order_by('user__last_name', 'user__first_name')
    )
    return render(
        request, 'portal/coaches.html',
        {'coach_list': coach_list, 'roster': roster},
    )


@portal_role_required(Roles.COORDINATOR)
def guardians(request):
    club = request.user.club
    link_form = GuardianLinkForm(request.POST or None, club=club)
    if request.method == 'POST' and link_form.is_valid():
        link, created = link_guardian(
            coordinator=request.user,
            guardian=link_form.cleaned_data['guardian'],
            player=link_form.cleaned_data['player'],
        )
        if created:
            AuditLog.record(
                request.user, 'guardian_link.created',
                target=f'{link.guardian.email} → {link.player.email}',
            )
            messages.success(
                request,
                f'{link.guardian.email} linked to {link.player.email}.',
            )
        else:
            messages.info(request, 'That link already exists.')
        return redirect('portal:guardians')

    guardian_list = (
        User.objects.filter(club=club, role=Roles.GUARDIAN)
        .prefetch_related('guardian_links__player')
        .order_by('last_name', 'first_name')
    )
    return render(
        request, 'portal/guardians.html',
        {'guardian_list': guardian_list, 'link_form': link_form},
    )


@portal_role_required(Roles.COORDINATOR)
def guardian_unlink(request, pk):
    if request.method != 'POST':
        return redirect('portal:guardians')
    link = get_object_or_404(
        GuardianLink.objects.select_related('guardian', 'player'), pk=pk
    )
    target = f'{link.guardian.email} → {link.player.email}'
    unlink_guardian(coordinator=request.user, link=link)
    AuditLog.record(request.user, 'guardian_link.removed', target=target)
    messages.success(request, f'Link removed: {target}.')
    return redirect('portal:guardians')


# Portal photo guardrails — images only, far smaller than the license cap.


@portal_role_required(Roles.COORDINATOR)
def player_photo(request, player_id):
    """POST a roster photo for one of the club's players (stored via the same
    Supabase path the admin console uses)."""
    if request.method != 'POST':
        return redirect('portal:players')
    profile = get_object_or_404(
        PlayerProfile.objects.select_related('user'),
        user_id=player_id, user__club=request.user.club,
    )
    upload = request.FILES.get('photo')
    if upload is None:
        messages.error(request, 'Choose a photo file first.')
    else:
        try:
            content_type = validate_photo_upload(upload)
            path = upload_photo(
                player_id, upload.read(),
                content_type=content_type,
            )
        except (RuntimeError, ValueError) as exc:
            messages.error(request, str(exc))
        else:
            profile.photo_path = path
            profile.save(update_fields=['photo_path'])
            messages.success(
                request, f'Photo updated for {profile.user.email}.'
            )
    return redirect('portal:players')


@portal_role_required(Roles.SCHOOL_STAFF)
def staff_eligibility(request):
    club = request.user.club
    form = EligibilityUpdateForm(request.POST or None, club=club)
    if request.method == 'POST' and form.is_valid():
        profile = set_player_eligibility(
            staff=request.user,
            player_profile=form.cleaned_data['player'],
            new_status=form.cleaned_data['eligibility'],
        )
        messages.success(
            request, f'Eligibility updated for {profile.user.email}.'
        )
        return redirect('portal:staff-eligibility')

    roster = (
        PlayerProfile.objects.select_related('user')
        .filter(user__club=club)
        .order_by('user__last_name', 'user__first_name')
    )
    # The club's recent eligibility transitions (spec: staff view the status
    # history of linked players — the club is the link). Same club-scoping as
    # the roster; capped so years of history never bloat the page.
    history = (
        EligibilityHistory.objects.select_related('player', 'changed_by')
        .filter(player__club=club)[:50]
    )
    return render(
        request,
        'portal/staff_eligibility.html',
        {'form': form, 'roster': roster, 'history': history},
    )


@portal_role_required(Roles.SCHOOL_STAFF)
def staff_disputes(request):
    """List dispute threads raised by Coaches in the staff member's Club."""
    disputes = staff_dispute_queryset(staff=request.user)
    return render(
        request,
        'portal/staff_disputes.html',
        {'disputes': disputes},
    )


@portal_role_required(Roles.SCHOOL_STAFF)
def staff_dispute_detail(request, pk):
    """Show and append to one same-Club dispute thread."""
    dispute = get_object_or_404(
        staff_dispute_queryset(staff=request.user),
        pk=pk,
    )
    form = DisputeResponseForm(request.POST or None)
    if request.method == 'POST' and form.is_valid():
        respond_to_dispute(
            staff=request.user,
            dispute_id=dispute.pk,
            body=form.cleaned_data['body'],
            status_change_to=form.cleaned_data['status_change_to'],
        )
        messages.success(request, 'Your response was added to the dispute.')
        return redirect('portal:staff-dispute-detail', pk=dispute.pk)

    return render(
        request,
        'portal/staff_dispute_detail.html',
        {'dispute': dispute, 'form': form},
    )


def _coordinator_schedule(request, schedule_id):
    return get_object_or_404(
        TournamentSchedule.objects.select_related('club', 'uploaded_by'),
        pk=schedule_id,
        club_id=request.user.club_id,
    )


@portal_role_required(Roles.COORDINATOR)
def tournament_schedules(request):
    """List published schedules and create a new tournament programme."""
    form = TournamentScheduleForm(request.POST or None, request.FILES or None)
    if request.method == 'POST' and form.is_valid():
        document = form.cleaned_data['document']
        content_type = validate_tournament_document(document)
        schedule = None
        document_path = ''
        try:
            with transaction.atomic():
                schedule = TournamentSchedule.objects.create(
                    club=request.user.club,
                    title=form.cleaned_data['title'],
                    uploaded_by=request.user,
                )
                document_path = upload_tournament_document(
                    request.user.club_id,
                    schedule.id,
                    document.read(),
                    content_type,
                )
                schedule.document_path = document_path
                schedule.save(update_fields=['document_path', 'updated_at'])
                AuditLog.record(
                    request.user,
                    'tournament.created',
                    target=schedule.title,
                    detail='Official schedule uploaded.',
                )
        except RuntimeError as exc:
            if document_path:
                delete_tournament_document(document_path)
            form.add_error('document', str(exc))
        else:
            messages.success(request, f'{schedule.title} has been published.')
            return redirect('portal:tournament-detail', schedule_id=schedule.id)

    schedules = (
        TournamentSchedule.objects.filter(club_id=request.user.club_id)
        .prefetch_related('fixtures')
    )
    return render(request, 'portal/tournament_schedules.html', {
        'form': form,
        'schedules': schedules,
    })


@portal_role_required(Roles.COORDINATOR)
def tournament_schedule_detail(request, schedule_id):
    schedule = _coordinator_schedule(request, schedule_id)
    document_form = TournamentDocumentForm()
    fixture_form = TournamentFixtureForm(prefix='fixture')

    if request.method == 'POST':
        action = request.POST.get('action')
        if action == 'replace-document':
            document_form = TournamentDocumentForm(request.POST, request.FILES)
            if document_form.is_valid():
                document = document_form.cleaned_data['document']
                content_type = validate_tournament_document(document)
                old_path = schedule.document_path
                try:
                    new_path = upload_tournament_document(
                        request.user.club_id,
                        schedule.id,
                        document.read(),
                        content_type,
                    )
                except RuntimeError as exc:
                    document_form.add_error('document', str(exc))
                else:
                    schedule.document_path = new_path
                    schedule.uploaded_by = request.user
                    schedule.save(update_fields=[
                        'document_path', 'uploaded_by', 'updated_at',
                    ])
                    if old_path and old_path != new_path:
                        delete_tournament_document(old_path)
                    AuditLog.record(
                        request.user,
                        'tournament.document_updated',
                        target=schedule.title,
                    )
                    messages.success(request, 'Schedule document replaced.')
                    return redirect(
                        'portal:tournament-detail', schedule_id=schedule.id
                    )
        elif action == 'add-fixture':
            fixture_form = TournamentFixtureForm(request.POST, prefix='fixture')
            if fixture_form.is_valid():
                fixture = fixture_form.save(commit=False)
                fixture.schedule = schedule
                fixture.save()
                AuditLog.record(
                    request.user,
                    'fixture.created',
                    target=fixture.opponent,
                    detail=f'{schedule.title} · {fixture.kickoff_at.isoformat()}',
                )
                messages.success(request, 'Fixture added to the tournament.')
                return redirect(
                    'portal:tournament-detail', schedule_id=schedule.id
                )

    return render(request, 'portal/tournament_schedule_detail.html', {
        'schedule': schedule,
        'document_url': signed_tournament_document_url(schedule.document_path),
        'document_form': document_form,
        'fixture_form': fixture_form,
        'fixtures': schedule.fixtures.select_related('completed_match'),
    })


@portal_role_required(Roles.COORDINATOR)
def tournament_fixture_edit(request, fixture_id):
    fixture = get_object_or_404(
        TournamentFixture.objects.select_related('schedule'),
        pk=fixture_id,
        schedule__club_id=request.user.club_id,
    )
    if fixture.completed_match_id:
        messages.error(request, 'A completed fixture can no longer be edited.')
        return redirect(
            'portal:tournament-detail', schedule_id=fixture.schedule_id
        )
    form = TournamentFixtureForm(request.POST or None, instance=fixture)
    if request.method == 'POST' and form.is_valid():
        fixture = form.save()
        AuditLog.record(
            request.user,
            'fixture.updated',
            target=fixture.opponent,
            detail=fixture.schedule.title,
        )
        messages.success(request, 'Fixture updated.')
        return redirect('portal:tournament-detail', schedule_id=fixture.schedule_id)
    return render(request, 'portal/tournament_fixture_form.html', {
        'form': form,
        'fixture': fixture,
    })


@portal_role_required(Roles.COORDINATOR)
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
            'fixture.deleted',
            target=fixture.opponent,
            detail=fixture.schedule.title,
        )
        fixture.delete()
        messages.success(request, 'Fixture deleted.')
    return redirect('portal:tournament-detail', schedule_id=schedule_id)


@portal_role_required(Roles.COORDINATOR)
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
