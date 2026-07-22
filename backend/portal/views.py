"""Portal controllers — thin: parse the request, call a service, render.

Business rules and tenancy live in `portal.services`; role/auth policy in
`portal.decorators`. Every coordinator/staff query derives its club from
`request.user.club`, never from client input.
"""
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.shortcuts import redirect, render

from academy.models import PlayerProfile
from accounts.models import Roles
from accounts.services import ProvisioningError

from .decorators import portal_role_required
from .forms import (
    CoordinatorSignupForm,
    CreateCoachForm,
    CreateGuardianForm,
    CreatePlayerForm,
    CreateStaffForm,
    EligibilityUpdateForm,
)
from .services import (
    create_club_account,
    register_coordinator,
    set_player_eligibility,
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
                created = {
                    'email': user.email,
                    'role': user.get_role_display(),
                    'credential': credential,
                    'is_web': account_type == 'staff',
                }
                messages.success(
                    request,
                    f'{user.get_role_display()} account created for {user.email}.',
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
    return render(
        request,
        'portal/staff_eligibility.html',
        {'form': form, 'roster': roster},
    )
