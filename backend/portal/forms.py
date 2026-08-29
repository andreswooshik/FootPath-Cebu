"""Portal forms — the input-validation boundary for the web surfaces.

Each account-creation form is scoped to the coordinator's club: the guardian /
player pickers only ever offer members of `club`, and the club is never taken
from form input (it is derived from `request.user.club` server-side).
"""
from django import forms
from django.contrib.auth.forms import AuthenticationForm
from django.contrib.auth.password_validation import validate_password

from academy.models import (
    DisputeStatus,
    Eligibility,
    FixtureStatus,
    PlayerProfile,
    TournamentFixture,
)
from academy.storage import validate_tournament_document
from accounts.models import Club, Roles, User
from accounts.validators import (
    COACH_LICENSE_MAX_BYTES,
    validate_coach_license_upload,
)

# Coach-license upload guardrails (public, unauthenticated form — keep tight).


class PortalAuthenticationForm(AuthenticationForm):
    """Session-login form with browser-friendly identity metadata."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['username'].widget.attrs.update({
            'autocomplete': 'username',
            'autofocus': True,
            'inputmode': 'email',
            'placeholder': 'name@example.com',
        })
        self.fields['password'].widget.attrs.update({
            'autocomplete': 'current-password',
            'placeholder': 'Enter your password',
        })


class CoordinatorSignupForm(forms.Form):
    """Public club application form for a pending coordinator account."""

    club_name = forms.CharField(max_length=120, label='Club name')
    coordinator_name = forms.CharField(
        max_length=150, label='Name of the coordinator'
    )
    head_coach_name = forms.CharField(max_length=150, label='Head coach name')
    coach_license = forms.FileField(
        label='Coach license',
        help_text='JPG, PNG or PDF, max 50 MB.',
        validators=[validate_coach_license_upload],
    )
    cvfa_membership = forms.CharField(
        max_length=80, label='CVFA membership number'
    )
    is_school_affiliated = forms.BooleanField(
        required=False, label='This club is affiliated with a school',
    )
    school_name = forms.CharField(
        max_length=150, required=False, label='School name (if affiliated)',
    )
    email = forms.EmailField(label='Coordinator email')
    password1 = forms.CharField(widget=forms.PasswordInput, label='Password')
    password2 = forms.CharField(
        widget=forms.PasswordInput, label='Confirm password'
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['email'].widget.attrs['autocomplete'] = 'email'
        self.fields['coordinator_name'].widget.attrs['autocomplete'] = 'name'
        self.fields['password1'].widget.attrs['autocomplete'] = 'new-password'
        self.fields['password2'].widget.attrs['autocomplete'] = 'new-password'

    def clean_email(self):
        email = self.cleaned_data['email'].strip().lower()
        # Generic wording avoids confirming which emails are registered
        # (OWASP A07 — user enumeration).
        if User.objects.filter(email__iexact=email).exists():
            raise forms.ValidationError('This email cannot be used.')
        return email

    def clean_club_name(self):
        name = self.cleaned_data['club_name'].strip()
        if Club.objects.filter(name__iexact=name).exists():
            raise forms.ValidationError('A club with this name already exists.')
        return name

    def clean_password1(self):
        password = self.cleaned_data['password1']
        validate_password(password)  # honours AUTH_PASSWORD_VALIDATORS
        return password

    def clean(self):
        cleaned = super().clean()
        p1, p2 = cleaned.get('password1'), cleaned.get('password2')
        if p1 and p2 and p1 != p2:
            self.add_error('password2', 'The two passwords do not match.')
        if cleaned.get('is_school_affiliated') and not cleaned.get('school_name'):
            self.add_error(
                'school_name', 'Enter the school name for an affiliated club.'
            )
        return cleaned


class _BaseCreateAccountForm(forms.Form):
    """Common identity fields for every coordinator-created account.

    Accepts (and ignores, unless a subclass uses it) a `club` kwarg so the view
    can instantiate every form uniformly.
    """

    first_name = forms.CharField(max_length=150)
    last_name = forms.CharField(max_length=150)
    email = forms.EmailField()

    def __init__(self, *args, club=None, **kwargs):
        self.club = club
        super().__init__(*args, **kwargs)

    def clean_email(self):
        email = self.cleaned_data['email'].strip().lower()
        if not email:
            return ''
        if User.objects.filter(email__iexact=email).exists():
            raise forms.ValidationError('An account with this email already exists.')
        return email


class CreateCoachForm(_BaseCreateAccountForm):
    """Coach = a mobile-app (Firebase) account, no extra profile."""


class CreateStaffForm(_BaseCreateAccountForm):
    """School staff = a web-portal (Django session) account."""


class CreatePlayerForm(_BaseCreateAccountForm):
    email = forms.EmailField(
        required=False,
        label='Player email (optional)',
        help_text=(
            'Leave blank for a guardian-managed player profile. Do not reuse '
            'the guardian email as a second login.'
        ),
    )
    middle_initial = forms.CharField(max_length=5, required=False)
    date_of_birth = forms.DateField(
        widget=forms.DateInput(attrs={'type': 'date'})
    )
    guardian = forms.ModelChoiceField(
        queryset=User.objects.none(),
        required=False,
        help_text='Optional: link an existing Guardian in this club.',
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.club is not None:
            self.fields['guardian'].queryset = User.objects.filter(
                role=Roles.GUARDIAN, club=self.club
            ).order_by('last_name', 'first_name')
        self.fields['guardian'].label_from_instance = _user_label


class CreateGuardianForm(_BaseCreateAccountForm):
    player = forms.ModelChoiceField(
        queryset=User.objects.none(),
        required=False,
        help_text='Optionally link an existing player in your club.',
    )

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.club is not None:
            self.fields['player'].queryset = User.objects.filter(
                role=Roles.PLAYER, club=self.club
            ).order_by('last_name', 'first_name')
        self.fields['player'].label_from_instance = _user_label


class EligibilityUpdateForm(forms.Form):
    """School-staff eligibility change, scoped to the staff member's club."""

    player = forms.ModelChoiceField(queryset=PlayerProfile.objects.none())
    eligibility = forms.ChoiceField(choices=Eligibility.choices)

    def __init__(self, *args, club=None, **kwargs):
        super().__init__(*args, **kwargs)
        qs = PlayerProfile.objects.select_related('user')
        if club is not None:
            qs = qs.filter(user__club=club)
        self.fields['player'].queryset = qs.order_by(
            'user__last_name', 'user__first_name'
        )
        self.fields['player'].label_from_instance = lambda p: _user_label(p.user)


class DisputeResponseForm(forms.Form):
    """Append a School Staff response and optionally move the dispute."""

    body = forms.CharField(
        max_length=2000,
        label='Response',
        widget=forms.Textarea(attrs={'rows': 5}),
    )
    status_change_to = forms.ChoiceField(
        required=False,
        label='Update status',
        choices=[('', 'Keep current status'), *DisputeStatus.choices],
    )


class GuardianLinkForm(forms.Form):
    """Link an existing guardian to an existing player, both pickers scoped
    to the coordinator's club."""

    guardian = forms.ModelChoiceField(queryset=User.objects.none())
    player = forms.ModelChoiceField(queryset=User.objects.none())

    def __init__(self, *args, club=None, **kwargs):
        super().__init__(*args, **kwargs)
        if club is not None:
            self.fields['guardian'].queryset = User.objects.filter(
                role=Roles.GUARDIAN, club=club
            ).order_by('last_name', 'first_name')
            self.fields['player'].queryset = User.objects.filter(
                role=Roles.PLAYER, club=club
            ).order_by('last_name', 'first_name')
        self.fields['guardian'].label_from_instance = _user_label
        self.fields['player'].label_from_instance = _user_label


class TournamentScheduleForm(forms.Form):
    title = forms.CharField(
        max_length=120,
        label='Tournament name',
        widget=forms.TextInput(attrs={'placeholder': 'e.g. Cebu Youth Cup 2026'}),
    )
    starts_on = forms.DateField(
        label='Tournament start date',
        widget=forms.DateInput(attrs={'type': 'date'}),
    )
    document = forms.FileField(
        label='Official schedule document',
        help_text='Optional. PDF, JPG, or PNG, up to 5 MB.',
        validators=[validate_tournament_document],
        required=False,
    )

    def clean_title(self):
        return self.cleaned_data['title'].strip()


class TournamentDocumentForm(forms.Form):
    document = forms.FileField(
        label='Replacement schedule document',
        help_text='PDF, JPG, or PNG, up to 5 MB.',
        validators=[validate_tournament_document],
    )


class TournamentFixtureForm(forms.ModelForm):
    kickoff_at = forms.DateTimeField(
        label='Kickoff',
        input_formats=['%Y-%m-%dT%H:%M'],
        widget=forms.DateTimeInput(
            format='%Y-%m-%dT%H:%M', attrs={'type': 'datetime-local'}
        ),
    )
    status = forms.ChoiceField(choices=[
        (FixtureStatus.SCHEDULED, FixtureStatus.SCHEDULED.label),
        (FixtureStatus.POSTPONED, FixtureStatus.POSTPONED.label),
        (FixtureStatus.CANCELLED, FixtureStatus.CANCELLED.label),
    ])

    class Meta:
        model = TournamentFixture
        fields = ['stage', 'opponent', 'kickoff_at', 'venue', 'location', 'status']
        labels = {
            'stage': 'Stage or round',
            'opponent': 'Opponent',
            'venue': 'Home, away, or neutral',
        }
        help_texts = {
            'opponent': 'Use TBD when the knockout opponent is not known.',
            'location': 'Pitch, stadium, or meeting location.',
        }

    def clean_opponent(self):
        return self.cleaned_data['opponent'].strip() or 'TBD'


class CoordinatorMobileAccessForm(forms.Form):
    current_password = forms.CharField(
        label='Current portal password',
        widget=forms.PasswordInput(attrs={'autocomplete': 'current-password'}),
        help_text='This same password will be used for the mobile app.',
    )


def _user_label(user):
    name = f'{user.first_name} {user.last_name}'.strip()
    if name and user.email:
        return f'{name} ({user.email})'
    return name or user.email or f'Player {user.id}'
