from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User


@admin.register(User)
class CustomUserAdmin(UserAdmin):
    list_display = ('username', 'email', 'role', 'firebase_uid', 'is_active')
    list_filter = UserAdmin.list_filter + ('role',)
    fieldsets = UserAdmin.fieldsets + (
        ('FootPath', {'fields': ('role', 'firebase_uid')}),
    )
    add_fieldsets = UserAdmin.add_fieldsets + (
        ('FootPath', {'fields': ('role', 'firebase_uid')}),
    )
    search_fields = ('username', 'email', 'firebase_uid')
