from django.contrib import admin

from .models import (
    AgeTierSetting,
    Dispute,
    DisputeResponse,
    EligibilityHistory,
    InjuryRecord,
    PlayerEligibility,
)


@admin.register(AgeTierSetting)
class AgeTierSettingAdmin(admin.ModelAdmin):
    """Editable age boundaries per tier. The three rows are fixed (seeded by
    migration) — the tier set is a wire contract with the client, so add and
    delete are disabled; only the boundaries change."""

    list_display = ('tier', 'min_age', 'max_age')
    list_editable = ('min_age', 'max_age')

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(PlayerEligibility)
class PlayerEligibilityAdmin(admin.ModelAdmin):
    """Narrow eligibility-review screen. Players are created via the
    console's Add Player flow (which also creates PlayerProfile), not here —
    add is disabled so this stays a review-only surface."""

    list_display = ('user', 'eligibility', 'date_of_birth')
    list_filter = ('eligibility',)
    search_fields = ('user__email', 'user__first_name', 'user__last_name')
    fields = ('user', 'eligibility', 'date_of_birth', 'middle_initial')
    readonly_fields = ('user', 'date_of_birth', 'middle_initial')

    def has_add_permission(self, request):
        return False

    def save_model(self, request, obj, form, change):
        # Hand the acting admin to the eligibility signal so the history row it
        # writes is attributed. Model signals have no request context otherwise.
        obj._changed_by = request.user
        super().save_model(request, obj, form, change)


@admin.register(EligibilityHistory)
class EligibilityHistoryAdmin(admin.ModelAdmin):
    """Read-only trail of eligibility transitions — append-only by design, so
    no add/change/delete from the admin either."""

    list_display = (
        'player', 'old_status', 'new_status', 'changed_by', 'changed_at',
    )
    list_filter = ('new_status',)
    search_fields = ('player__email', 'player__first_name', 'player__last_name')

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


class DisputeResponseInline(admin.TabularInline):
    """The thread inline on the dispute — "Admin review" happens in one
    screen. The API keeps the thread append-only (no update/delete
    endpoints); the admin site is the trusted escape hatch."""

    model = DisputeResponse
    extra = 1
    readonly_fields = ('created_at',)


@admin.register(Dispute)
class DisputeAdmin(admin.ModelAdmin):
    list_display = (
        'summary', 'category', 'status', 'raised_by', 'subject_player',
        'created_at',
    )
    list_filter = ('status', 'category')
    search_fields = ('summary', 'detail', 'raised_by__email')
    autocomplete_fields = ('raised_by', 'subject_player')
    inlines = [DisputeResponseInline]


@admin.register(InjuryRecord)
class InjuryRecordAdmin(admin.ModelAdmin):
    list_display = (
        'player', 'description', 'body_part', 'status',
        'occurred_on', 'resolved_on',
    )
    list_filter = ('status',)
    search_fields = ('player__email', 'description', 'body_part')
    autocomplete_fields = ('player',)
