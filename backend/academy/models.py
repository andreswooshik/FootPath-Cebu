"""Academy domain models — player profiles, training sessions, attendance.

Identity and roles live in `accounts` (see ADR 0001); this app holds the
football-domain data keyed to those users. Wire values (uppercase enums like
FOUNDATION / PRESENT) mirror the Flutter entities in
`footpath_cebu/lib/domain/entities/` so the JSON contract needs no translation
layer on the client.
"""
from django.conf import settings
from django.db import models

from accounts.models import Roles


class AgeTier(models.TextChoices):
    FOUNDATION = 'FOUNDATION', 'Foundation'      # ages 10–12
    DEVELOPMENT = 'DEVELOPMENT', 'Development'    # ages 13–15
    PATHWAY = 'PATHWAY', 'Pathway'               # ages 16–18


class Eligibility(models.TextChoices):
    ELIGIBLE = 'ELIGIBLE', 'Eligible'
    NOT_ELIGIBLE = 'NOT_ELIGIBLE', 'Not Eligible'
    PENDING = 'PENDING', 'Pending'
    ACADEMIC_WARNING = 'ACADEMIC_WARNING', 'Academic Warning'


class SessionFocus(models.TextChoices):
    TECHNICAL = 'TECHNICAL', 'Technical'
    PHYSICAL = 'PHYSICAL', 'Physical'
    MENTAL = 'MENTAL', 'Mental'


class AttendanceStatus(models.TextChoices):
    PRESENT = 'PRESENT', 'Present'
    ABSENT = 'ABSENT', 'Absent'
    EXCUSED = 'EXCUSED', 'Excused'


class PlayerProfile(models.Model):
    """A player's football profile. One-to-one with a PLAYER-role user.

    Ratings are the six 0–99 FUT-style attributes shown on the roster card. The
    tier is stored (not derived from age) so a coach can hold a player in a
    lower tier and nobody shifts tier on their birthday mid-season — matching
    the client's `AgeTierInfo.forAge` note.
    """

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='player_profile',
        limit_choices_to={'role': Roles.PLAYER},
    )
    age = models.PositiveIntegerField(default=0)
    class_year = models.CharField(max_length=40, blank=True)
    age_tier = models.CharField(
        max_length=20, choices=AgeTier.choices, default=AgeTier.DEVELOPMENT
    )
    position = models.CharField(max_length=8, blank=True)  # ST, CM, GK, ...

    pace = models.PositiveSmallIntegerField(default=0)
    shooting = models.PositiveSmallIntegerField(default=0)
    passing = models.PositiveSmallIntegerField(default=0)
    dribbling = models.PositiveSmallIntegerField(default=0)
    defending = models.PositiveSmallIntegerField(default=0)
    physical = models.PositiveSmallIntegerField(default=0)

    eligibility = models.CharField(
        max_length=20, choices=Eligibility.choices, default=Eligibility.PENDING
    )
    # Storage object path (e.g. "player-photos/12.jpg"); the API serves a signed
    # URL, never this raw path. Null until an Admin uploads a photo.
    photo_path = models.CharField(max_length=255, null=True, blank=True)

    def __str__(self):
        return f'{self.user.email} · {self.get_age_tier_display()}'


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
    # Explicit set of tiers the session targets, as wire strings — a new tier
    # never silently absorbs existing sessions (mirrors the client rationale).
    age_tiers = models.JSONField(default=list)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='created_sessions',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-date']

    def __str__(self):
        return f'{self.title} ({self.date})'


class Attendance(models.Model):
    """One player's attendance for one training day."""

    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='attendance_records',
        limit_choices_to={'role': Roles.PLAYER},
    )
    session = models.ForeignKey(
        TrainingSession,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='attendance_records',
    )
    status = models.CharField(
        max_length=10, choices=AttendanceStatus.choices,
        default=AttendanceStatus.ABSENT,
    )
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='recorded_attendance',
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-updated_at']

    def __str__(self):
        return f'{self.player.email} · {self.status} · {self.updated_at:%Y-%m-%d}'


class DeviceToken(models.Model):
    """An FCM registration token for a user's device. Used to fan out push
    notifications (M3). A user may have several (multiple devices)."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='device_tokens',
    )
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=20, blank=True)  # android / ios / web
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'{self.user.email} · {self.platform or "?"}'
