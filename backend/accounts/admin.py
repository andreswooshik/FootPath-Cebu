import json

from django import forms
from django.contrib import admin, messages
from django.contrib.auth.admin import UserAdmin
from django.contrib.auth.forms import UserChangeForm, UserCreationForm
from django.contrib.auth.models import Group
from django.contrib.auth.password_validation import (
    get_default_password_validators,
    validate_password,
)
from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Q
from django.http import HttpResponseNotAllowed, JsonResponse
from django.urls import path, reverse
from django.utils.html import format_html
from django.utils.safestring import mark_safe

from .models import Club, GuardianLink, Roles, User
from .services import link_or_create_firebase_user, provision_club_coordinator

# This project authorizes by the custom User.role field (see accounts.permissions),
# not Django's Groups/Permissions. Hide Groups so the admin isn't cluttered with an
# unused system.
admin.site.unregister(Group)

# Solid pill colour per role so the registry can be scanned at a glance. White text
# on a saturated background stays legible in both light and dark theme.
_ROLE_COLORS = {
    Roles.ADMIN: '#7C3AED',         # violet
    Roles.COORDINATOR: '#DB2777',   # rose
    Roles.COACH: '#EA580C',         # orange
    Roles.PLAYER: '#2563EB',        # blue
    Roles.SCHOOL_STAFF: '#0D9488',  # teal
    Roles.GUARDIAN: '#059669',      # emerald
}

_PILL = (
    'display:inline-block;padding:2px 10px;border-radius:999px;'
    'font-size:11px;font-weight:600;letter-spacing:.02em;{extra}'
)


class BulkActionLabelMixin:
    """Replace the bulk-action dropdown's default '---------' with 'Bulk Actions'.

    Done server-side so the label is correct in the HTML from the start, rather
    than relying on JS to rewrite it after select2 has already rendered.
    """

    def get_action_choices(self, request, default_choices=None):
        return super().get_action_choices(
            request, default_choices=[('', 'Bulk Actions')]
        )


class FootPathUserValidationMixin:
    """Keep manual Django-admin edits inside the approved hierarchy."""

    def clean(self):
        cleaned = super().clean()
        role = cleaned.get('role')
        club = cleaned.get('club')
        if role == Roles.PLAYER:
            raise forms.ValidationError(
                'Create Players through the dedicated player flow so their '
                'profile is created atomically.'
            )
        if role != Roles.ADMIN and club is None:
            self.add_error('club', 'Every club-member account needs a club.')
        if role == Roles.SCHOOL_STAFF and club and not club.allows_school_staff:
            self.add_error(
                'club', 'School Staff can be assigned only to a School club.'
            )
        if role == Roles.COORDINATOR and club:
            existing = User.objects.filter(club=club, role=Roles.COORDINATOR)
            if self.instance.pk:
                existing = existing.exclude(pk=self.instance.pk)
            if existing.exists():
                self.add_error('club', 'This club already has a coordinator.')
        return cleaned


class FootPathUserCreationForm(FootPathUserValidationMixin, UserCreationForm):
    class Meta(UserCreationForm.Meta):
        model = User
        fields = ('username', 'email', 'role', 'club')


class FootPathUserChangeForm(FootPathUserValidationMixin, UserChangeForm):
    class Meta(UserChangeForm.Meta):
        model = User


_COORDINATOR_PASSWORD_HELP = mark_safe(
    '<ul id="coordinator-password-requirements" '
    'class="fp-password-requirements" aria-live="polite">'
    '<li data-password-rule="similarity" class="is-unmet">'
    'Not too similar to the coordinator name or email.</li>'
    '<li data-password-rule="minimum_length" class="is-unmet">'
    'Contains at least 8 characters.</li>'
    '<li data-password-rule="common" class="is-unmet">'
    'Not a commonly used password.</li>'
    '<li data-password-rule="numeric" class="is-unmet">'
    'Not entirely numeric.</li>'
    '</ul>'
)


class ClubAdminForm(forms.ModelForm):
    """Create the club and its required Coordinator in one admin form."""

    coordinator_name = forms.CharField(
        max_length=150,
        label='Coordinator name',
        help_text='The person who will manage this club.',
    )
    coordinator_email = forms.EmailField(
        label='Coordinator email',
        help_text='This email will also be the Coordinator username.',
    )
    coordinator_password1 = forms.CharField(
        label='Coordinator password',
        strip=False,
        widget=forms.PasswordInput(attrs={'autocomplete': 'new-password'}),
        help_text=_COORDINATOR_PASSWORD_HELP,
    )
    coordinator_password2 = forms.CharField(
        label='Confirm coordinator password',
        strip=False,
        widget=forms.PasswordInput(attrs={'autocomplete': 'new-password'}),
        help_text=mark_safe(
            '<span id="coordinator-password-match" '
            'class="fp-password-match is-pending" aria-live="polite">'
            'Enter the same password again.</span>'
        ),
    )

    class Meta:
        model = Club
        fields = '__all__'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.needs_coordinator = (
            not self.instance.pk or self.instance.coordinator is None
        )
        for field_name in (
            'coordinator_name',
            'coordinator_email',
            'coordinator_password1',
            'coordinator_password2',
        ):
            self.fields[field_name].required = self.needs_coordinator
        if self.needs_coordinator:
            self.fields['coordinator_password1'].widget.attrs[
                'data-password-check-url'
            ] = reverse('admin:accounts_club_password_check')

    def clean_coordinator_email(self):
        email = self.cleaned_data.get('coordinator_email', '').strip().lower()
        if not self.needs_coordinator or not email:
            return email
        if User.objects.filter(
            Q(email__iexact=email) | Q(username__iexact=email)
        ).exists():
            raise forms.ValidationError(
                'An account already uses this Coordinator email.'
            )
        return email

    def clean(self):
        cleaned = super().clean()
        if not self.needs_coordinator:
            return cleaned

        password1 = cleaned.get('coordinator_password1')
        password2 = cleaned.get('coordinator_password2')
        if password1 and password2 and password1 != password2:
            self.add_error(
                'coordinator_password2',
                'The two coordinator passwords do not match.',
            )

        if password1:
            name_parts = cleaned.get('coordinator_name', '').strip().split(None, 1)
            coordinator = User(
                username=cleaned.get('coordinator_email', ''),
                email=cleaned.get('coordinator_email', ''),
                first_name=name_parts[0] if name_parts else '',
                last_name=name_parts[1] if len(name_parts) > 1 else '',
                role=Roles.COORDINATOR,
            )
            try:
                validate_password(password1, user=coordinator)
            except ValidationError as exc:
                self.add_error('coordinator_password1', exc)
        return cleaned


@admin.register(User)
class CustomUserAdmin(BulkActionLabelMixin, UserAdmin):
    add_form = FootPathUserCreationForm
    form = FootPathUserChangeForm
    list_display = (
        'email', 'full_name', 'role_badge', 'club', 'status_chip', 'access_chip'
    )
    list_display_links = ('email',)
    list_filter = ('role', 'club', 'is_active', 'is_staff')
    ordering = ('email',)
    search_fields = ('username', 'email', 'firebase_uid')
    autocomplete_fields = ('club',)
    actions = ['approve_coordinators']

    # Rebuilt from scratch (rather than appending to UserAdmin.fieldsets) to drop
    # the groups / user_permissions dual-listbox widgets this project never uses.
    fieldsets = (
        ('Account', {'fields': ('username', 'password')}),
        ('Personal info', {'fields': ('first_name', 'last_name', 'email')}),
        ('Role & Club', {'fields': ('role', 'club', 'firebase_uid')}),
        # Account activation is controlled by the explicit approval actions.
        # Hiding the raw checkbox prevents accidental lockouts/deactivations.
        ('Access', {'fields': ('is_staff', 'is_superuser')}),
        ('Important dates', {'fields': ('last_login', 'date_joined')}),
    )
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('username', 'email', 'password1', 'password2', 'role', 'club'),
        }),
    )

    @admin.action(description='Approve selected coordinators (activate login)')
    def approve_coordinators(self, request, queryset):
        """Super Admin activation gate for coordinator accounts.

        A coordinator signs up via the web portal with is_active=False; until a
        developer runs this action they cannot log in (Django's ModelBackend
        rejects inactive users). Only pending COORDINATOR rows are touched.
        """
        pending = queryset.filter(role=Roles.COORDINATOR, is_active=False)
        approved = pending.count()
        pending.update(is_active=True)
        if approved:
            self.message_user(
                request,
                f'Approved and activated {approved} coordinator account(s).',
                level=messages.SUCCESS,
            )
        else:
            self.message_user(
                request,
                'No pending coordinator accounts were in the selection.',
                level=messages.WARNING,
            )

    def save_model(self, request, obj, form, change):
        """Auto-sync a Firebase identity when an Admin creates an app account.

        Creating a User here normally writes only a DB row, so the account has
        no Firebase identity and can't log into the app (that is how a
        firebase_uid ends up NULL). For a NEW, non-Django-admin account with an
        email, we create/link a Firebase account and stamp firebase_uid — the
        same provisioning the /api/admin/users/ endpoint does. The password
        typed in the add form becomes the Firebase password, so the account
        works in the app immediately.
        """
        if not change and obj.role == Roles.PLAYER:
            raise forms.ValidationError(
                'Create Players through the dedicated player flow.'
            )
        if obj.role != Roles.ADMIN and obj.club_id is None:
            raise forms.ValidationError('Every club-member account needs a club.')
        super().save_model(request, obj, form, change)

        # Only newly-created mobile app accounts. Coordinator and School Staff
        # use Django session passwords in the web portal.
        if change or obj.firebase_uid or obj.is_staff or obj.is_superuser:
            return
        if obj.role in (Roles.COORDINATOR, Roles.SCHOOL_STAFF):
            return

        if not obj.email:
            self.message_user(
                request,
                f'{obj.username}: no email set, so it was NOT synced to Firebase '
                'and cannot log into the app. Add an email and re-save to sync.',
                level=messages.WARNING,
            )
            return

        try:
            temp_password = link_or_create_firebase_user(
                obj, password=form.cleaned_data.get('password1')
            )
            obj.save(update_fields=['firebase_uid', 'password'])
        except Exception as exc:  # keep the admin resilient to Firebase errors
            self.message_user(
                request,
                f'Saved locally, but Firebase sync failed: {exc}. The user '
                'cannot log into the app until this is resolved.',
                level=messages.ERROR,
            )
            return

        if temp_password is not None:
            self.message_user(
                request,
                f'Synced to Firebase. App login → {obj.email} / the password you set.',
                level=messages.SUCCESS,
            )
        else:
            self.message_user(
                request,
                f'Linked to the existing Firebase account for {obj.email} '
                '(its password was left unchanged).',
                level=messages.SUCCESS,
            )

    @admin.display(description='Name')
    def full_name(self, obj):
        return f'{obj.first_name} {obj.last_name}'.strip() or '—'

    @admin.display(description='Role', ordering='role')
    def role_badge(self, obj):
        color = _ROLE_COLORS.get(obj.role, '#475569')
        return format_html(
            '<span style="{}">{}</span>',
            _PILL.format(extra=f'color:#fff;background:{color};'),
            obj.get_role_display(),
        )

    @admin.display(description='Status', ordering='is_active')
    def status_chip(self, obj):
        if obj.is_active:
            style = _PILL.format(extra='color:#10B981;background:rgba(16,185,129,.15);')
            label = '● Active'
        else:
            style = _PILL.format(extra='color:#94A3B8;background:rgba(148,163,184,.18);')
            label = '○ Inactive'
        return format_html('<span style="{}">{}</span>', style, label)

    @admin.display(description='Access', ordering='is_staff')
    def access_chip(self, obj):
        if obj.is_superuser:
            style = _PILL.format(extra='color:#7C3AED;background:rgba(124,58,237,.15);')
            label = 'Superuser'
        elif obj.is_staff:
            style = _PILL.format(extra='color:#0EA5E9;background:rgba(14,165,233,.15);')
            label = 'Staff'
        else:
            return format_html('<span style="color:#64748B;">—</span>')
        return format_html('<span style="{}">{}</span>', style, label)


@admin.register(GuardianLink)
class GuardianLinkAdmin(BulkActionLabelMixin, admin.ModelAdmin):
    list_display = ('guardian', 'player', 'created_at')
    search_fields = (
        'guardian__email', 'player__email',
        'guardian__username', 'player__username',
    )
    autocomplete_fields = ('guardian', 'player')
    readonly_fields = ('created_at',)


@admin.register(Club)
class ClubAdmin(BulkActionLabelMixin, admin.ModelAdmin):
    form = ClubAdminForm
    list_display = (
        'name', 'coordinator_email', 'registration_status', 'member_count', 'school_chip',
        'active_chip', 'created_at',
    )
    list_filter = ('is_active', 'is_school_affiliated')
    search_fields = ('name', 'slug', 'head_coach_name', 'cvfa_membership')
    prepopulated_fields = {'slug': ('name',)}
    readonly_fields = ('created_at',)
    # Approval/deactivation is performed with the named bulk actions below;
    # do not expose Django's ambiguous raw "Is active" checkbox.
    exclude = ('is_active',)
    actions = ('approve_registrations', 'disapprove_registrations')

    def get_urls(self):
        custom_urls = [
            path(
                'password-check/',
                self.admin_site.admin_view(self.password_check_view),
                name='accounts_club_password_check',
            ),
        ]
        return custom_urls + super().get_urls()

    def get_fieldsets(self, request, obj=None):
        club_fields = (
            'name',
            'slug',
            'is_school_affiliated',
            'school_name',
            'head_coach_name',
            'coach_license',
            'cvfa_membership',
        )
        needs_coordinator = obj is None or obj.coordinator is None
        if not needs_coordinator:
            return (
                ('Club details', {'fields': club_fields + ('created_at',)}),
            )
        fieldsets = [
            (
                'Club details',
                {'fields': club_fields + (('created_at',) if obj else ())},
            ),
            (
                'Coordinator account',
                {
                    'fields': (
                        'coordinator_name',
                        'coordinator_email',
                        'coordinator_password1',
                        'coordinator_password2',
                    ),
                    'description': (
                        'This account will be created as the Club Coordinator '
                        'and assigned to the new club automatically.'
                    ),
                },
            ),
        ]
        return tuple(fieldsets)

    def password_check_view(self, request):
        """Return exact Django password-validator states for live feedback."""
        if request.method != 'POST':
            return HttpResponseNotAllowed(['POST'])
        try:
            payload = json.loads(request.body or b'{}')
        except (json.JSONDecodeError, UnicodeDecodeError):
            return JsonResponse({'error': 'Invalid request.'}, status=400)

        password = str(payload.get('password', ''))
        email = str(payload.get('email', '')).strip().lower()
        name_parts = str(payload.get('name', '')).strip().split(None, 1)
        coordinator = User(
            username=email,
            email=email,
            first_name=name_parts[0] if name_parts else '',
            last_name=name_parts[1] if len(name_parts) > 1 else '',
            role=Roles.COORDINATOR,
        )
        rule_names = {
            'UserAttributeSimilarityValidator': 'similarity',
            'MinimumLengthValidator': 'minimum_length',
            'CommonPasswordValidator': 'common',
            'NumericPasswordValidator': 'numeric',
        }
        rules = {rule_name: False for rule_name in rule_names.values()}
        if password:
            for validator in get_default_password_validators():
                rule_name = rule_names.get(type(validator).__name__)
                if rule_name is None:
                    continue
                try:
                    validator.validate(password, user=coordinator)
                except ValidationError:
                    rules[rule_name] = False
                else:
                    rules[rule_name] = True
        return JsonResponse({'rules': rules})

    @transaction.atomic
    def save_model(self, request, obj, form, change):
        needs_coordinator = not change or obj.coordinator is None
        super().save_model(request, obj, form, change)
        if not needs_coordinator:
            return

        name_parts = form.cleaned_data['coordinator_name'].strip().split(None, 1)
        provision_club_coordinator(
            email=form.cleaned_data['coordinator_email'],
            first_name=name_parts[0],
            last_name=name_parts[1] if len(name_parts) > 1 else '',
            club=obj,
            password=form.cleaned_data['coordinator_password1'],
            is_active=True,
        )
        self.message_user(
            request,
            'The Club Coordinator account was created and linked to this club.',
            level=messages.SUCCESS,
        )

    def has_delete_permission(self, request, obj=None):
        """Clubs are durable tenant boundaries; deactivate them instead."""
        return False

    @admin.action(description='Activate selected clubs and coordinators')
    def approve_registrations(self, request, queryset):
        """Approve clubs and activate their pending coordinator logins."""
        approved = 0
        with transaction.atomic():
            for club in queryset:
                coordinator = club.coordinator
                if coordinator is None:
                    continue
                changed = False
                if not club.is_active:
                    club.is_active = True
                    club.save(update_fields=['is_active'])
                    changed = True
                if not coordinator.is_active:
                    coordinator.is_active = True
                    coordinator.save(update_fields=['is_active'])
                    changed = True
                if changed:
                    approved += 1
        self.message_user(
            request,
            f'Activated {approved} club(s).',
            level=messages.SUCCESS if approved else messages.WARNING,
        )

    @admin.action(description='Deactivate selected clubs and coordinators')
    def disapprove_registrations(self, request, queryset):
        """Deactivate clubs and prevent their coordinators from logging in."""
        disapproved = 0
        with transaction.atomic():
            for club in queryset:
                coordinator = club.coordinator
                if coordinator is None:
                    continue
                changed = club.is_active or coordinator.is_active
                club.is_active = False
                club.save(update_fields=['is_active'])
                coordinator.is_active = False
                coordinator.save(update_fields=['is_active'])
                if changed:
                    disapproved += 1
        self.message_user(
            request,
            f'Deactivated {disapproved} club(s).',
            level=messages.SUCCESS if disapproved else messages.WARNING,
        )

    @admin.display(description='Coordinator')
    def coordinator_email(self, obj):
        coordinator = obj.coordinator
        return coordinator.email if coordinator else '—'

    @admin.display(description='Status')
    def registration_status(self, obj):
        coordinator = obj.coordinator
        if coordinator is None:
            label, color = 'Incomplete', '#64748B'
        elif not obj.is_active:
            label, color = 'Disapproved', '#DC2626'
        elif not coordinator.is_active:
            label, color = 'Pending', '#D97706'
        else:
            label, color = 'Approved', '#059669'
        style = _PILL.format(extra=f'color:{color};background:{color}1A;')
        return format_html('<span style="{}">{}</span>', style, label)

    @admin.display(description='Club type', ordering='is_school_affiliated')
    def school_chip(self, obj):
        if obj.is_school_affiliated:
            style = _PILL.format(extra='color:#0D9488;background:rgba(13,148,136,.15);')
            return format_html(
                '<span style="{}">{}</span>', style, obj.school_name or 'School Club'
            )
        return format_html('<span style="color:#64748B;">Independent Club</span>')

    @admin.display(description='Members')
    def member_count(self, obj):
        return obj.members.count()

    @admin.display(description='Status', ordering='is_active')
    def active_chip(self, obj):
        if obj.is_active:
            style = _PILL.format(extra='color:#10B981;background:rgba(16,185,129,.15);')
            label = '● Active'
        else:
            style = _PILL.format(extra='color:#94A3B8;background:rgba(148,163,184,.18);')
            label = '○ Inactive'
        return format_html('<span style="{}">{}</span>', style, label)
