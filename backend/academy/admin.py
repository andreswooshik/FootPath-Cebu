from django.contrib import admin

from .models import Dispute, DisputeResponse, InjuryRecord, PlayerEligibility


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
