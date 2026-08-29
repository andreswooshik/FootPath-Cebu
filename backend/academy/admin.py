from django.contrib import admin

from .models import (
    AgeTierSetting,
    AuditLog,
    Dispute,
    DisputeResponse,
    EligibilityHistory,
    FootballMatch,
    InjuryRecord,
    InjuryStatusUpdateRequest,
    NotificationRecord,
    PlayerMatchPerformance,
    PlayerEligibility,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
)


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    """Read-only trail of sensitive changes — append-only by design, so no
    add/change/delete from the admin either (same stance as
    EligibilityHistoryAdmin)."""

    list_display = ('created_at', 'action', 'actor', 'target', 'detail')
    list_filter = ('action',)
    search_fields = ('target', 'detail', 'actor__email')
    date_hierarchy = 'created_at'

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(NotificationRecord)
class NotificationRecordAdmin(admin.ModelAdmin):
    """Read-only delivery/inbox evidence; application endpoints own read state."""

    list_display = ('created_at', 'user', 'event_type', 'title', 'read_at')
    list_filter = ('event_type', 'read_at')
    search_fields = ('user__email', 'title', 'body')
    readonly_fields = (
        'user', 'event_type', 'title', 'body', 'data', 'read_at', 'created_at',
    )

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


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

    def get_queryset(self, request):
        return super().get_queryset(request).filter(
            user__club__is_school_affiliated=True
        )

    def save_model(self, request, obj, form, change):
        # Hand the acting admin to the eligibility signal so the history row it
        # writes is attributed. Model signals have no request context otherwise.
        if not obj.user.club.allows_academic_eligibility:
            raise ValueError(
                'Academic eligibility is not applicable to an Independent club.'
            )
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
        'player', 'description', 'review_status', 'status',
        'occurred_on', 'resolved_on',
    )
    list_filter = ('review_status', 'status')
    search_fields = ('player__email', 'description', 'body_part')
    readonly_fields = (
        'player', 'description', 'body_part', 'status', 'occurred_on',
        'resolved_on', 'notes', 'reported_by', 'review_status', 'reviewed_by',
        'reviewed_at', 'rejection_reason', 'archived_at', 'created_at',
        'updated_at',
    )

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(InjuryStatusUpdateRequest)
class InjuryStatusUpdateRequestAdmin(admin.ModelAdmin):
    list_display = (
        'injury', 'proposed_status', 'review_status', 'submitted_by',
        'created_at',
    )
    list_filter = ('review_status', 'proposed_status')
    readonly_fields = (
        'injury', 'proposed_status', 'proposed_resolved_on', 'notes',
        'submitted_by', 'review_status', 'reviewed_by', 'reviewed_at',
        'rejection_reason', 'created_at', 'updated_at',
    )

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(FootballMatch)
class FootballMatchAdmin(admin.ModelAdmin):
    """Correction-only match surface; coaches create records in the app."""

    list_display = (
        'played_on', 'club', 'opponent', 'competition',
        'our_score', 'opponent_score', 'created_by',
    )
    list_filter = ('club', 'venue', 'competition')
    search_fields = ('opponent', 'competition', 'club__name')
    readonly_fields = ('club', 'created_by', 'created_at', 'updated_at')
    date_hierarchy = 'played_on'

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        AuditLog.record(
            request.user,
            'match.admin_corrected',
            target=str(obj.pk),
            detail=f'{obj.opponent} | {obj.played_on}',
        )


class TournamentFixtureInline(admin.TabularInline):
    model = TournamentFixture
    extra = 0
    readonly_fields = (
        'stage', 'opponent', 'kickoff_at', 'venue', 'location', 'status',
        'completed_match', 'created_at', 'updated_at',
    )
    can_delete = False

    def has_add_permission(self, request, obj=None):
        return False


class TournamentAgeBracketInline(admin.TabularInline):
    model = TournamentAgeBracket
    extra = 0
    readonly_fields = ('max_age', 'scheduled_at', 'created_at', 'updated_at')
    can_delete = False

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(TournamentSchedule)
class TournamentScheduleAdmin(admin.ModelAdmin):
    list_display = (
        'title', 'club', 'starts_on', 'is_published', 'published_at', 'uploaded_by',
    )
    list_filter = ('is_published', 'club')
    search_fields = ('title', 'club__name')
    readonly_fields = (
        'club', 'title', 'starts_on', 'document_path', 'uploaded_by', 'is_published',
        'published_at', 'created_at', 'updated_at',
    )
    inlines = [TournamentAgeBracketInline, TournamentFixtureInline]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(PlayerMatchPerformance)
class PlayerMatchPerformanceAdmin(admin.ModelAdmin):
    """Correction-only player statistics with immutable ownership fields."""

    list_display = (
        'match', 'player', 'position', 'minutes_played',
        'goals', 'assists', 'coach_rating', 'updated_at',
    )
    list_filter = ('match__club', 'position', 'starter', 'clean_sheet')
    search_fields = (
        'player__email', 'player__first_name', 'player__last_name',
        'match__opponent',
    )
    readonly_fields = (
        'match', 'player', 'recorded_by', 'rated_by', 'rated_at',
        'created_at', 'updated_at',
    )

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        AuditLog.record(
            request.user,
            'match.performance_admin_corrected',
            target=f'{obj.match_id}:{obj.player_id}',
        )
