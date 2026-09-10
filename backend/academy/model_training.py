"""Training-session model."""

import re
from datetime import datetime

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone

from academy.model_players import (
    SessionFocus,
    TrainingSessionStatus,
)


class TrainingSession(models.Model):
    """A scheduled session. Times are display strings (e.g. "04:30 PM") to match
    the client entity, which never parses them as clock times."""

    title = models.CharField(max_length=120)
    date = models.DateField()
    start_time = models.CharField(max_length=20, blank=True)
    end_time = models.CharField(max_length=20, blank=True)
    location = models.CharField(max_length=120, blank=True)
    focus = models.CharField(
        max_length=20, choices=SessionFocus.choices, default=SessionFocus.TECHNICAL
    )
    # Existing ``focus`` remains the primary focus for legacy clients/rows.
    additional_focuses = models.JSONField(default=list, blank=True)
    session_objectives = models.TextField(blank=True, default='')
    equipment_requirements = models.TextField(blank=True, default='')
    coach_instructions = models.TextField(blank=True, default='')
    # Explicit set of tiers the session targets, as wire strings — a new tier
    # never silently absorbs existing sessions (mirrors the client rationale).
    age_tiers = models.JSONField(default=list)
    status = models.CharField(
        max_length=20,
        choices=TrainingSessionStatus.choices,
        default=TrainingSessionStatus.SCHEDULED,
    )
    cancellation_reason = models.CharField(max_length=500, blank=True)
    conflicting_tournament_id = models.PositiveBigIntegerField(
        null=True,
        blank=True,
    )
    conflicting_fixture_id = models.PositiveBigIntegerField(
        null=True,
        blank=True,
    )
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancelled_by_action = models.CharField(max_length=80, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='created_sessions',
    )
    # The club that owns this session (multi-tenancy). Set from the scheduling
    # coach's club; null only for legacy rows created before tenancy. PROTECT
    # preserves both the tenant boundary and calendar ownership; operationally
    # a club is deactivated instead of deleted.
    club = models.ForeignKey(
        'accounts.Club',
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='training_sessions',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    # Monotonic version of the complete roll call. Clients use it for
    # optimistic concurrency when replacing attendance from multiple devices.
    attendance_revision = models.PositiveBigIntegerField(default=0)

    _TIME_PATTERN = re.compile(
        r'^(?P<hour>0?[1-9]|1[0-2]):(?P<minute>[0-5][0-9])\s*'
        r'(?P<period>AM|PM)$',
        re.IGNORECASE,
    )

    @classmethod
    def validate_time_window(cls, start_time, end_time):
        """Validate and normalize the session's paired 12-hour clock values.

        Both values may be blank for legacy/unscheduled records. Otherwise the
        pair is required, each value must use the app's 12-hour wire format,
        and the end must be later on the same day than the start.
        """
        start_text = str(start_time or '').strip()
        end_text = str(end_time or '').strip()
        errors = {}

        if bool(start_text) != bool(end_text):
            missing_field = 'start_time' if not start_text else 'end_time'
            errors[missing_field] = 'Start time and end time must be provided together.'
        if errors:
            raise ValidationError(errors)
        if not start_text:
            return '', ''

        parsed = {}
        normalized = {}
        for field, value in (
            ('start_time', start_text),
            ('end_time', end_text),
        ):
            match = cls._TIME_PATTERN.fullmatch(value)
            if match is None:
                errors[field] = 'Use a 12-hour time such as 04:30 PM.'
                continue
            hour = int(match.group('hour'))
            minute = int(match.group('minute'))
            period = match.group('period').upper()
            hour_24 = hour % 12 + (12 if period == 'PM' else 0)
            parsed[field] = hour_24 * 60 + minute
            normalized[field] = f'{hour:02d}:{minute:02d} {period}'

        if errors:
            raise ValidationError(errors)
        if parsed['start_time'] >= parsed['end_time']:
            raise ValidationError({'end_time': 'End time must be later than start time.'})
        return normalized['start_time'], normalized['end_time']

    def clean(self):
        super().clean()
        self.start_time, self.end_time = self.validate_time_window(self.start_time, self.end_time)

    def save(self, *args, **kwargs):
        # ModelForm/admin calls full_clean automatically, but ordinary ORM
        # create/save does not. Enforce the same invariant on both paths.
        self.full_clean()
        return super().save(*args, **kwargs)

    def interval(self):
        """Return timezone-aware datetimes in the configured academy zone."""
        start, end = self.validate_time_window(self.start_time, self.end_time)
        if not start:
            return None, None

        def combine(value):
            parsed = datetime.strptime(value, '%I:%M %p').time()
            combined = datetime.combine(self.date, parsed)
            return timezone.make_aware(combined, timezone.get_current_timezone())

        return combine(start), combine(end)

    @property
    def is_cancelled(self):
        return self.status == TrainingSessionStatus.CANCELLED

    class Meta:
        ordering = ['-date']

    def __str__(self):
        return f'{self.title} ({self.date})'
