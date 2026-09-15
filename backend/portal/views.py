"""Portal controllers — thin: parse the request, call a service, render.

Business rules and tenancy live in `portal.services`; role/auth policy in
`portal.decorators`. Every coordinator query derives its club from
`request.user.club`, never from client input.
"""

import logging

from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.contrib.auth.views import PasswordChangeView
from django.contrib.messages.views import SuccessMessageMixin
from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse_lazy

from academy.models import AuditLog, PlayerProfile
from academy.pin_service import reset_pin
from academy.storage import (
    sanitized_photo_bytes,
    upload_photo,
    validate_photo_upload,
)
from accounts.models import GuardianLink, Roles, User
from accounts.services import (
    ProvisioningError,
    sync_coordinator_firebase_password,
)

from .decorators import portal_role_required
from .forms import (
    CoordinatorSignupForm,
    CreateCoachForm,
    CreateGuardianForm,
    CreatePlayerForm,
    GuardianLinkForm,
)
from .ratelimit import is_rate_limited
from .services import (
    create_club_account,
    link_guardian,
    register_coordinator,
    split_coordinator_name,
    unlink_guardian,
)

_ACCOUNT_FORMS = {
    'player': CreatePlayerForm,
    'coach': CreateCoachForm,
    'guardian': CreateGuardianForm,
}

logger = logging.getLogger(__name__)


def signup(request):
    """Accept a club application and create an inactive coordinator login."""
    if request.user.is_authenticated:
        return redirect('portal:dashboard')
    if request.method == 'POST':
        if is_rate_limited(request, scope='signup', limit=5, window_seconds=3600):
            messages.error(
                request,
                'Too many registration attempts from your network. Please try again later.',
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
            first_name, last_name = split_coordinator_name(data['coordinator_name'])
            try:
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
            except ProvisioningError:
                form.add_error(
                    None,
                    'The application could not be submitted. Please contact an administrator.',
                )
            except OSError:
                logger.exception('Club application storage failed.')
                form.add_error(
                    'coach_license',
                    'Coach-license storage is temporarily unavailable.',
                )
            else:
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
        members = User.objects.filter(club=club, is_active=True)
        profiles = PlayerProfile.objects.filter(
            user__club=club,
            user__is_active=True,
        )
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
    return render(request, 'portal/dashboard.html', context)


class PortalPasswordChangeView(SuccessMessageMixin, PasswordChangeView):
    """Change the signed-in portal user's password.

    Coordinators arrive with a password created during club registration. The
    Coordinator's Firebase password is
    updated before the local password so both login surfaces stay aligned.
    """

    template_name = 'portal/password_change.html'
    success_url = reverse_lazy('portal:dashboard')
    success_message = 'Your password has been changed.'

    def form_valid(self, form):
        try:
            sync_coordinator_firebase_password(
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
def create_account(request):
    club = request.user.club
    available = dict(_ACCOUNT_FORMS)
    forms = {key: cls(club=club, auto_id=f'id_{key}_%s') for key, cls in available.items()}
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
                    request.user,
                    'account.created',
                    target=user.email or user.get_full_name() or user.username,
                    detail=user.role,
                )
                created = {
                    'email': user.email,
                    'display_name': user.get_full_name() or user.username,
                    'role': user.get_role_display(),
                    'credential': credential,
                    'is_web': False,
                    'managed': account_type == 'player' and not user.email,
                    'account_type': account_type,
                }
                messages.success(
                    request,
                    (
                        f'{user.get_role_display()} profile created for '
                        f'{user.get_full_name() or user.username}.'
                        if not user.email
                        else f'{user.get_role_display()} account created for {user.email}.'
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
        .filter(user__club=request.user.club, user__is_active=True)
        .order_by('user__last_name', 'user__first_name')
    )
    return render(request, 'portal/players.html', {'roster': roster})


@portal_role_required(Roles.COORDINATOR)
def player_pin_reset(request, player_id):
    if request.method != 'POST':
        return redirect('portal:players')
    profile = get_object_or_404(
        PlayerProfile.objects.select_related('user'),
        user_id=player_id,
        user__club=request.user.club,
        user__is_active=True,
    )
    reset_pin(profile.user)
    AuditLog.record(
        request.user,
        'player_pin.reset',
        target=profile.user.email,
        detail='Coordinator portal',
    )
    messages.success(request, f'Privacy PIN reset for {profile.user.email}.')
    return redirect('portal:players')


@portal_role_required(Roles.COORDINATOR)
def coaches(request):
    club = request.user.club
    coach_list = User.objects.filter(
        club=club,
        role=Roles.COACH,
        is_active=True,
    ).order_by(
        'last_name', 'first_name'
    )
    # There is no per-coach roster assignment anywhere in the schema — club
    # is the only tenancy boundary, so every coach in a club can coach/assess
    # every player in it. This is the same roster for every coach, not a
    # subset; the template says so explicitly rather than implying otherwise.
    roster = (
        PlayerProfile.objects.select_related('user')
        .filter(user__club=club, user__is_active=True)
        .order_by('user__last_name', 'user__first_name')
    )
    return render(
        request,
        'portal/coaches.html',
        {'coach_list': coach_list, 'roster': roster},
    )


@portal_role_required(Roles.COORDINATOR)
def guardians(request):
    club = request.user.club
    link_form = GuardianLinkForm(request.POST or None, club=club)
    if request.method == 'POST' and link_form.is_valid():
        guardian = link_form.cleaned_data['guardian']
        players = list(link_form.cleaned_data['players'])
        with transaction.atomic():
            for player in players:
                link, _created = link_guardian(
                    coordinator=request.user,
                    guardian=guardian,
                    player=player,
                )
                AuditLog.record(
                    request.user,
                    'guardian_link.created',
                    target=f'{link.guardian.email} → {link.player.email}',
                )
        messages.success(
            request,
            f'{guardian.email} linked to {len(players)} player{"s" if len(players) != 1 else ""}.',
        )
        return redirect('portal:guardians')

    guardian_list = (
        User.objects.filter(club=club, role=Roles.GUARDIAN, is_active=True)
        .prefetch_related('guardian_links__player')
        .order_by('last_name', 'first_name')
    )
    return render(
        request,
        'portal/guardians.html',
        {'guardian_list': guardian_list, 'link_form': link_form},
    )


@portal_role_required(Roles.COORDINATOR)
def guardian_unlink(request, pk):
    if request.method != 'POST':
        return redirect('portal:guardians')
    link = get_object_or_404(GuardianLink.objects.select_related('guardian', 'player'), pk=pk)
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
        user_id=player_id,
        user__club=request.user.club,
        user__is_active=True,
    )
    upload = request.FILES.get('photo')
    if upload is None:
        messages.error(request, 'Choose a photo file first.')
    else:
        try:
            content_type = validate_photo_upload(upload)
            path = upload_photo(
                player_id,
                sanitized_photo_bytes(upload, content_type),
                content_type=content_type,
            )
        except (RuntimeError, ValueError) as exc:
            messages.error(request, str(exc))
        else:
            profile.photo_path = path
            profile.save(update_fields=['photo_path'])
            messages.success(request, f'Photo updated for {profile.user.email}.')
    return redirect('portal:players')


from .view_tournaments import (
    tournament_bracket_delete as tournament_bracket_delete,
)
from .view_tournaments import (
    tournament_fixture_delete as tournament_fixture_delete,
)
from .view_tournaments import (
    tournament_fixture_edit as tournament_fixture_edit,
)
from .view_tournaments import (
    tournament_fixture_result as tournament_fixture_result,
)
from .view_tournaments import (
    tournament_schedule_delete as tournament_schedule_delete,
)
from .view_tournaments import (
    tournament_schedule_detail as tournament_schedule_detail,
)
from .view_tournaments import (
    tournament_schedules as tournament_schedules,
)
