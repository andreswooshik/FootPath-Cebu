"""Portal forms — the input-validation boundary for the web surfaces.

Each account-creation form is scoped to the coordinator's club: the guardian /
player pickers only ever offer members of `club`, and the club is never taken
from form input (it is derived from `request.user.club` server-side).
"""
import os

from django import forms
from django.contrib.auth.password_validation import validate_password

from academy.models import Eligibility, PlayerProfile
from accounts.models import Club, Roles, User

# Coach-license upload guardrails (public, unauthenticated form — keep tight).
COACH_LICENSE_MAX_BYTES = 50 * 1024 * 1024  # 50 MB
_COACH_LICENSE_EXTS = {'.jpg', '.jpeg', '.png', '.pdf'}
_COACH_LICENSE_TYPES = {'image/jpeg', 'image/png', 'application/pdf'}
# First-bytes signatures for the allowed types. The extension and the
# browser-supplied content-type are both attacker-controlled, so we also verify
# what the file actually *is* — a .pdf-named script or an HTML/JS polyglot would
# otherwise sail through the two checks above (audit finding S3).
_COACH_LICENSE_SIGNATURES = (
    b'\xff\xd8\xff',          # JPEG
    b'\x89PNG\r\n\x1a\n',     # PNG
    b'%PDF-',                 # PDF
)


def _has_allowed_signature(upload):
    """True if the upload's leading bytes match a JPG/PNG/PDF signature. Seeks
    back to 0 so the later save reads the whole file."""
    upload.seek(0)
    header = upload.read(8)
    upload.seek(0)
    return any(header.startswith(sig) for sig in _COACH_LICENSE_SIGNATURES)


class CoordinatorSignupForm(forms.Form):
    """Public club registration → creates a club + a pending coordinator."""

    club_name = forms.CharField(max_length=120, label='Club name')
    coordinator_name = forms.CharField(
        max_length=150, label='Name of the coordinator'
    )
    head_coach_name = forms.CharField(max_length=150, label='Head coach name')
    coach_license = forms.FileField(
        label='Coach license',
        help_text='JPG, PNG or PDF, max 50 MB.',
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

    def clean_coach_license(self):
        upload = self.cleaned_data['coach_license']
        ext = os.path.splitext(upload.name)[1].lower()
        content_type = getattr(upload, 'content_type', None)
        # Allowlist by BOTH extension and declared content-type, and cap size.
        if ext not in _COACH_LICENSE_EXTS:
            raise forms.ValidationError('Upload a JPG, PNG or PDF file.')
        if content_type and content_type not in _COACH_LICENSE_TYPES:
            raise forms.ValidationError('Unsupported file type. Use JPG, PNG or PDF.')
        if upload.size > COACH_LICENSE_MAX_BYTES:
            raise forms.ValidationError('The file must be 50 MB or smaller.')
        # Last line of defence: the bytes must actually be a JPG/PNG/PDF, not
        # just named like one.
        if not _has_allowed_signature(upload):
            raise forms.ValidationError(
                'That file does not look like a real JPG, PNG or PDF.'
            )
        return upload

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
        required=True,
        help_text='Required: create the guardian account first.',
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


def _user_label(user):
    name = f'{user.first_name} {user.last_name}'.strip()
    if name and user.email:
        return f'{name} ({user.email})'
    return name or user.email or f'Player {user.id}'
