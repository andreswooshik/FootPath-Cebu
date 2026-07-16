from django.contrib import admin

from .models import Attendance, DeviceToken, PlayerProfile, TrainingSession


@admin.register(PlayerProfile)
class PlayerProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'age_tier', 'position', 'eligibility')
    list_filter = ('age_tier', 'eligibility')
    search_fields = ('user__email', 'user__username')
    autocomplete_fields = ('user',)


@admin.register(TrainingSession)
class TrainingSessionAdmin(admin.ModelAdmin):
    list_display = ('title', 'date', 'focus', 'location', 'created_by')
    list_filter = ('focus', 'date')
    search_fields = ('title', 'location')


@admin.register(Attendance)
class AttendanceAdmin(admin.ModelAdmin):
    list_display = ('player', 'session', 'status', 'updated_at')
    list_filter = ('status',)
    search_fields = ('player__email',)
    autocomplete_fields = ('player', 'session', 'recorded_by')


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ('user', 'platform', 'updated_at')
    search_fields = ('user__email', 'token')
