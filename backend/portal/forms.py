"""Portal forms — the input-validation boundary for the web surfaces.

Each account-creation form is scoped to the coordinator's club: the guardian /
player pickers only ever offer members of `club`, and the club is never taken
from form input (it is derived from `request.user.club` server-side).
"""
from django import forms
from django.contrib.auth.forms import AuthenticationForm
from django.contrib.auth.password_validation import validate_password

from academy.models import (
    AgeTier,
    DisputeStatus,
    Eligibility,
    FixtureStatus,
    PlayerProfile,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSquadStatus,
)
from academy.serializers import TournamentFixtureResultWriteSerializer
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
    venue = forms.CharField(
        max_length=160,
        label='Tournament venue',
        widget=forms.TextInput(
            attrs={'placeholder': 'e.g. Cebu City Sports Center'}
        ),
    )
    document = forms.FileField(
        label='Official schedule document',
        help_text='Optional. PDF, JPG, or PNG, up to 5 MB.',
        validators=[validate_tournament_document],
        required=False,
    )

    def clean_title(self):
        return self.cleaned_data['title'].strip()

    def clean_venue(self):
        return self.cleaned_data['venue'].strip()


class TournamentDocumentForm(forms.Form):
    document = forms.FileField(
        label='Replacement schedule document',
        help_text='PDF, JPG, or PNG, up to 5 MB.',
        validators=[validate_tournament_document],
    )


class TournamentAgeBracketForm(forms.ModelForm):
    scheduled_at = forms.DateTimeField(
        label='Optional division date and time',
        required=False,
        input_formats=['%Y-%m-%dT%H:%M'],
        widget=forms.DateTimeInput(
            format='%Y-%m-%dT%H:%M', attrs={'type': 'datetime-local'}
        ),
    )
    academy_tiers = forms.MultipleChoiceField(
        label='Academy tiers',
        choices=AgeTier.choices,
        help_text='Select every academy tier represented by this bracket.',
    )

    class Meta:
        model = TournamentAgeBracket
        fields = ['max_age', 'academy_tiers', 'scheduled_at']
        labels = {'max_age': 'Maximum age (U-age)'}

    def __init__(self, *args, schedule=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.schedule = schedule
        self.fields['max_age'].widget.attrs.update({'min': 3, 'max': 21})

    def clean_max_age(self):
        max_age = self.cleaned_data['max_age']
        brackets = (
            self.schedule.age_brackets.filter(max_age=max_age)
            if self.schedule is not None else TournamentAgeBracket.objects.none()
        )
        if self.instance.pk:
            brackets = brackets.exclude(pk=self.instance.pk)
        if brackets.exists():
            raise forms.ValidationError(
                f'{self.schedule.title} already has a U{max_age} bracket.'
            )
        return max_age


class TournamentFixtureForm(forms.ModelForm):
    kickoff_at = forms.DateTimeField(
        label='Kickoff',
        input_formats=['%Y-%m-%dT%H:%M'],
        widget=forms.DateTimeInput(
            format='%Y-%m-%dT%H:%M', attrs={'type': 'datetime-local'}
        ),
    )
    ends_at = forms.DateTimeField(
        label='Expected end',
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
        fields = [
            'age_bracket', 'stage', 'opponent', 'kickoff_at', 'ends_at',
            'venue', 'location', 'status',
        ]
        labels = {
            'age_bracket': 'Age bracket',
            'stage': 'Stage or round',
            'opponent': 'Opponent',
            'venue': 'Home, away, or neutral',
        }
        help_texts = {
            'age_bracket': 'Required for new tournament fixtures.',
            'opponent': 'Use TBD when the knockout opponent is not known.',
            'location': 'Pitch, stadium, or meeting location.',
        }

    def __init__(self, *args, schedule=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.schedule = schedule or getattr(self.instance, 'schedule', None)
        queryset = self.fields['age_bracket'].queryset.none()
        if self.schedule is not None:
            queryset = self.schedule.age_brackets.order_by('max_age', 'id')
        self.fields['age_bracket'].queryset = queryset
        self.fields['age_bracket'].required = True
        self.fields['age_bracket'].empty_label = 'Choose an age bracket'
        self.fields['stage'].required = True
        self.fields['location'].required = True

    def clean_age_bracket(self):
        bracket = self.cleaned_data.get('age_bracket')
        if bracket and (
            self.schedule is None or bracket.schedule_id != self.schedule.id
        ):
            raise forms.ValidationError(
                'Select an age bracket from this tournament.'
            )
        return bracket

    def clean_opponent(self):
        return self.cleaned_data['opponent'].strip() or 'TBD'

    def clean(self):
        cleaned = super().clean()
        kickoff = cleaned.get('kickoff_at')
        ends_at = cleaned.get('ends_at')
        if kickoff and ends_at and ends_at <= kickoff:
            self.add_error(
                'ends_at', 'Expected end time must be later than kickoff.',
            )
        return cleaned


class TournamentFixtureResultForm(forms.Form):
    """Dynamic result form limited to a fixture's Coach-published squad."""

    our_score = forms.IntegerField(label='FootPath Cebu score', min_value=0,
                                   max_value=99)
    opponent_score = forms.IntegerField(label='Opponent score', min_value=0,
                                        max_value=99)
    statistic_fields = (
        ('minutesPlayed', 'Minutes', 180),
        ('goals', 'Goals', None),
        ('assists', 'Assists', None),
        ('shots', 'Shots', None),
        ('shotsOnTarget', 'Shots on target', None),
        ('passesAttempted', 'Passes attempted', None),
        ('passesCompleted', 'Passes completed', None),
        ('tackles', 'Tackles', None),
        ('interceptions', 'Interceptions', None),
        ('yellowCards', 'Yellow cards', 2),
        ('redCards', 'Red cards', 1),
        ('saves', 'Saves (GK)', None),
        ('goalsConceded', 'Goals conceded (GK)', None),
    )
    positions = (
        ('', 'Choose position'), ('GK', 'GK'), ('CB', 'CB'), ('LB', 'LB'),
        ('RB', 'RB'), ('CDM', 'CDM'), ('CM', 'CM'), ('CAM', 'CAM'),
        ('LW', 'LW'), ('RW', 'RW'), ('ST', 'ST'),
    )

    def __init__(self, *args, fixture, **kwargs):
        super().__init__(*args, **kwargs)
        self.fixture = fixture
        self.entries = []
        if fixture.age_bracket_id:
            self.entries = list(
                fixture.age_bracket.squad.entries.select_related(
                    'player', 'player__player_profile',
                ).filter(
                    squad__status=TournamentSquadStatus.PUBLISHED,
                ).order_by('player__last_name', 'player__first_name', 'player_id')
            ) if hasattr(fixture.age_bracket, 'squad') else []
        for entry in self.entries:
            player_id = entry.player_id
            position = entry.position
            if not position:
                position = getattr(entry.player.player_profile, 'position', '')
            self.fields[f'participant_{player_id}'] = forms.BooleanField(
                required=False,
                label=entry.player.get_full_name().strip() or entry.player.email,
            )
            self.fields[f'position_{player_id}'] = forms.ChoiceField(
                choices=self.positions,
                initial=position,
                required=False,
                label='Position',
            )
            self.fields[f'starter_{player_id}'] = forms.BooleanField(
                required=False, label='Starter',
            )
            for name, label, maximum in self.statistic_fields:
                self.fields[f'{name}_{player_id}'] = forms.IntegerField(
                    min_value=0,
                    max_value=maximum,
                    initial=0,
                    required=False,
                    label=label,
                )
            self.fields[f'cleanSheet_{player_id}'] = forms.BooleanField(
                required=False, label='Clean sheet (GK)',
            )

    @property
    def participant_rows(self):
        rows = []
        for entry in self.entries:
            player_id = entry.player_id
            rows.append({
                'player': entry.player,
                'selected': self[f'participant_{player_id}'],
                'position': self[f'position_{player_id}'],
                'starter': self[f'starter_{player_id}'],
                'statistics': [
                    self[f'{name}_{player_id}']
                    for name, _label, _maximum in self.statistic_fields
                ],
                'clean_sheet': self[f'cleanSheet_{player_id}'],
            })
        return rows

    def clean(self):
        cleaned = super().clean()
        if self.errors:
            return cleaned
        participants = []
        for entry in self.entries:
            player_id = entry.player_id
            if not cleaned.get(f'participant_{player_id}'):
                continue
            statistics = {
                'position': cleaned.get(f'position_{player_id}', ''),
                'starter': cleaned.get(f'starter_{player_id}', False),
                'cleanSheet': cleaned.get(f'cleanSheet_{player_id}', False),
            }
            for name, _label, _maximum in self.statistic_fields:
                statistics[name] = cleaned.get(f'{name}_{player_id}') or 0
            participants.append({
                'playerId': player_id,
                'statistics': statistics,
            })
        serializer = TournamentFixtureResultWriteSerializer(data={
            'ourScore': cleaned.get('our_score'),
            'opponentScore': cleaned.get('opponent_score'),
            'participants': participants,
        })
        if not serializer.is_valid():
            messages = []
            for value in serializer.errors.values():
                messages.extend(str(item) for item in value)
            raise forms.ValidationError(messages)
        self.result_payload = serializer.validated_data
        return cleaned


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
