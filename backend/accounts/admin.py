from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from django.contrib.auth.models import Group
from django.utils.html import format_html

from .models import GuardianLink, Roles, User

# This project authorizes by the custom User.role field (see accounts.permissions),
# not Django's Groups/Permissions. Hide Groups so the admin isn't cluttered with an
# unused system.
admin.site.unregister(Group)

# Solid pill colour per role so the registry can be scanned at a glance. White text
# on a saturated background stays legible in both light and dark theme.
_ROLE_COLORS = {
    Roles.ADMIN: '#7C3AED',         # violet
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


@admin.register(User)
class CustomUserAdmin(BulkActionLabelMixin, UserAdmin):
    list_display = ('email', 'full_name', 'role_badge', 'status_chip', 'access_chip')
    list_display_links = ('email',)
    list_filter = ('role', 'is_active', 'is_staff')
    ordering = ('email',)
    search_fields = ('username', 'email', 'firebase_uid')

    # Rebuilt from scratch (rather than appending to UserAdmin.fieldsets) to drop
    # the groups / user_permissions dual-listbox widgets this project never uses.
    fieldsets = (
        ('Account', {'fields': ('username', 'password')}),
        ('Personal info', {'fields': ('first_name', 'last_name', 'email')}),
        ('Role & Firebase', {'fields': ('role', 'firebase_uid')}),
        ('Access', {'fields': ('is_active', 'is_staff', 'is_superuser')}),
        ('Important dates', {'fields': ('last_login', 'date_joined')}),
    )
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('username', 'email', 'password1', 'password2', 'role'),
        }),
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
