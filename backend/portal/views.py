"""Portal controllers — thin: parse the request, call a service, render.

Business rules and tenancy live in `portal.services`; role/auth policy in
`portal.decorators`. Every coordinator/staff query derives its club from
`request.user.club`, never from client input.
"""
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.contrib.auth.views import PasswordChangeView
from django.contrib.messages.views import SuccessMessageMixin
from django.shortcuts import redirect, render
from django.urls import reverse_lazy

from django.shortcuts import get_object_or_404

from academy.models import AuditLog, EligibilityHistory, PlayerProfile
from academy.pin_service import reset_pin
from academy.storage import upload_photo
from accounts.models import GuardianLink, Roles, User
from accounts.services import ProvisioningError

from .decorators import portal_role_required
from .ratelimit import is_rate_limited
from .forms import (
    CoordinatorSignupForm,
    CreateCoachForm,
    CreateGuardianForm,
    CreatePlayerForm,
    CreateStaffForm,
    EligibilityUpdateForm,
    GuardianLinkForm,
)
from .services import (
    create_club_account,
    link_guardian,
    register_coordinator,
    set_player_eligibility,
    unlink_guardian,
)

_ACCOUNT_FORMS = {
    'player': CreatePlayerForm,
    'coach': CreateCoachForm,
    'staff': CreateStaffForm,
    'guardian': CreateGuardianForm,
}


def _split_name(full_name):
    """Split a single 'Full Name' field into (first, last) for the User model."""
    parts = full_name.strip().split(None, 1)
    return parts[0], (parts[1] if len(parts) > 1 else '')


def signup(request):
    """Public club registration → creates a club + a pending coordinator."""
    if request.user.is_authenticated:
        return redirect('portal:dashboard')
    if request.method == 'POST':
        # Throttle the anonymous create-and-upload so it cannot be scripted to
        # spam pending clubs or spool large files (audit finding S3).
        if is_rate_limited(
            request, scope='signup', limit=5, window_seconds=3600
        ):
            messages.error(
                request,
                'Too many registration attempts from your network. Please try '
                'again later.',
            )
            return render(
                request, 'portal/signup.html',
                {'form': CoordinatorSignupForm()}, status=429,
            )
        form = CoordinatorSignupForm(request.POST, request.FILES)
        if form.is_valid():
            cd = form.cleaned_data
            first_name, last_name = _split_name(cd['coordinator_name'])
            register_coordinator(
                first_name=first_name,
                last_name=last_name,
                email=cd['email'],
                club_name=cd['club_name'],
                password=cd['password1'],
                is_school_affiliated=cd['is_school_affiliated'],
                school_name=cd.get('school_name', ''),
                head_coach_name=cd['head_coach_name'],
                coach_license=cd['coach_license'],
                cvfa_membership=cd['cvfa_membership'],
            )
            return redirect('portal:signup-done')
    else:
        form = CoordinatorSignupForm()
    return render(request, 'portal/signup.html', {'form': form})


def signup_done(request):
    return render(request, 'portal/signup_done.html')


@login_required
def dashboard(request):
    return render(request, 'portal/dashboard.html')


class PortalPasswordChangeView(SuccessMessageMixin, PasswordChangeView):
    """Change the signed-in portal user's password.

    Coordinators arrive with the password they chose at signup, but School
    Staff arrive with a relayed one-time password — without this page they'd
    keep it forever (Django admin was the only escape hatch). Session auth
    only; app roles change theirs through Firebase.
    """

    template_name = 'portal/password_change.html'
    success_url = reverse_lazy('portal:dashboard')
    success_message = 'Your password has been changed.'


@portal_role_required(Roles.COORDINATOR)
def create_account(request):
    club = request.user.club
    # School staff exist only for school-affiliated clubs — drop the form
    # entirely so it can neither render nor be submitted (server-side gate).
    available = dict(_ACCOUNT_FORMS)
    if not club.allows_school_staff:
        available.pop('staff', None)
    forms = {key: cls(club=club) for key, cls in available.items()}
    active_tab = 'player'
    created = None

    if request.method == 'POST':
        account_type = request.POST.get('account_type')
        form_cls = available.get(account_type)
        if form_cls is None:
            messages.error(request, 'Unknown or unavailable account type.')
            return redirect('portal:create-account')

        active_tab = account_type
        form = form_cls(request.POST, club=club)
        forms[account_type] = form
        if form.is_valid():
            try:
                user, credential = create_club_account(
                    account_type=account_type,
                    club=club,
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
                forms[account_type] = form_cls(club=club)

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
_PHOTO_MAX_BYTES = 10 * 1024 * 1024  # 10 MB
_PHOTO_TYPES = {'image/jpeg', 'image/png', 'image/webp'}


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
    elif upload.size > _PHOTO_MAX_BYTES:
        messages.error(request, 'The photo must be 10 MB or smaller.')
    elif upload.content_type not in _PHOTO_TYPES:
        messages.error(request, 'Only JPG, PNG or WebP photos are accepted.')
    else:
        try:
            path = upload_photo(
                player_id, upload.read(),
                content_type=upload.content_type,
            )
        except RuntimeError as exc:
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
