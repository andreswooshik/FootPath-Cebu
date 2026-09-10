"""Academy domain models — player profiles, training sessions, attendance.

Identity and roles live in `accounts` (see ADR 0001); this app holds the
football-domain data keyed to those users. Wire values (uppercase enums like
FOUNDATION / PRESENT) mirror the Flutter entities in
`footpath_cebu/lib/domain/entities/` so the JSON contract needs no translation
layer on the client.
"""

import copy
import logging
from datetime import date

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models, transaction

from accounts.models import Roles

audit_logger = logging.getLogger('footpath.audit')


class AgeTier(models.TextChoices):
    FOUNDATION = 'FOUNDATION', 'Foundation'  # ages 10–12
    DEVELOPMENT = 'DEVELOPMENT', 'Development'  # ages 13–15
    PATHWAY = 'PATHWAY', 'Pathway'  # ages 16–18


class AgeTierSetting(models.Model):
    """Admin-configurable age boundaries for one tier.

    Exactly three rows, seeded by migration — Admin edits the boundaries,
    never the set of tiers: the tier names are a wire contract with the
    client. The boundaries decide a NEW player's initial tier from their date
    of birth; existing players keep their stored tier (see PlayerProfile),
    so retuning a boundary never reshuffles the current roster.
    """

    tier = models.CharField(max_length=20, choices=AgeTier.choices, unique=True)
    min_age = models.PositiveSmallIntegerField()
    max_age = models.PositiveSmallIntegerField()

    class Meta:
        ordering = ['min_age']
        verbose_name = 'Age tier setting'
        verbose_name_plural = 'Age tier settings'

    def __str__(self):
        return f'{self.get_tier_display()} ({self.min_age}–{self.max_age})'

    @classmethod
    def tier_for_age(cls, age):
        """The wire tier value for an age. Ages outside every band clamp to
        the nearest one (an 8-year-old is Foundation, a 19-year-old Pathway),
        so provisioning never fails on an out-of-band birth date."""
        bands = list(cls.objects.order_by('min_age'))
        if not bands:
            return AgeTier.DEVELOPMENT
        for band in bands:
            if age <= band.max_age:
                return band.tier
        return bands[-1].tier

    @classmethod
    def profile_defaults_for(cls, date_of_birth):
        """(age, tier) for a new player born on `date_of_birth`."""
        today = date.today()
        age = (
            today.year
            - date_of_birth.year
            - ((today.month, today.day) < (date_of_birth.month, date_of_birth.day))
        )
        return age, cls.tier_for_age(age)


class Eligibility(models.TextChoices):
    ELIGIBLE = 'ELIGIBLE', 'Eligible'
    NOT_ELIGIBLE = 'NOT_ELIGIBLE', 'Not Eligible'
    PENDING = 'PENDING', 'Pending'
    ACADEMIC_WARNING = 'ACADEMIC_WARNING', 'Academic Warning'


class SessionFocus(models.TextChoices):
    TECHNICAL = 'TECHNICAL', 'Technical'
    PHYSICAL = 'PHYSICAL', 'Physical'
    MENTAL = 'MENTAL', 'Mental'
    TACTICAL = 'TACTICAL', 'Tactical'
    RECOVERY = 'RECOVERY', 'Recovery'
    MATCH_PREPARATION = 'MATCH_PREPARATION', 'Match Preparation'


class TrainingSessionStatus(models.TextChoices):
    SCHEDULED = 'SCHEDULED', 'Scheduled'
    COMPLETED = 'COMPLETED', 'Completed'
    CANCELLED = 'CANCELLED', 'Cancelled'


class AttendanceStatus(models.TextChoices):
    PRESENT = 'PRESENT', 'Present'
    ABSENT = 'ABSENT', 'Absent'
    EXCUSED = 'EXCUSED', 'Excused'


class AssessmentReason(models.TextChoices):
    GENERAL_REVIEW = 'GENERAL_REVIEW', 'General review'
    MONTHLY_REVIEW = 'MONTHLY_REVIEW', 'Monthly review'
    POST_TOURNAMENT = 'POST_TOURNAMENT', 'Post-tournament'
    RETURN_FROM_INJURY = 'RETURN_FROM_INJURY', 'Return from injury'
    BASELINE = 'BASELINE', 'Baseline'
    OTHER = 'OTHER', 'Other'


class ConfirmationStatus(models.TextChoices):
    CONFIRMED = 'CONFIRMED', 'Confirmed'
    DECLINED = 'DECLINED', 'Declined'


class MatchVenue(models.TextChoices):
    HOME = 'HOME', 'Home'
    AWAY = 'AWAY', 'Away'
    NEUTRAL = 'NEUTRAL', 'Neutral'


class MatchCategory(models.TextChoices):
    FRIENDLY = 'FRIENDLY', 'Friendly'
    LEAGUE = 'LEAGUE', 'League'
    TOURNAMENT = 'TOURNAMENT', 'Tournament'
    OTHER = 'OTHER', 'Other'


class FixtureStatus(models.TextChoices):
    SCHEDULED = 'SCHEDULED', 'Scheduled'
    POSTPONED = 'POSTPONED', 'Postponed'
    CANCELLED = 'CANCELLED', 'Cancelled'
    COMPLETED = 'COMPLETED', 'Completed'


PLAYER_POSITION_CODES = {
    'GK',
    'CB',
    'LB',
    'RB',
    'CDM',
    'CM',
    'CAM',
    'LW',
    'RW',
    'ST',
}


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
    age_tier = models.CharField(max_length=20, choices=AgeTier.choices, default=AgeTier.DEVELOPMENT)
    position = models.CharField(max_length=8, blank=True)  # ST, CM, GK, ...

    pace = models.PositiveSmallIntegerField(default=0)
    shooting = models.PositiveSmallIntegerField(default=0)
    passing = models.PositiveSmallIntegerField(default=0)
    dribbling = models.PositiveSmallIntegerField(default=0)
    defending = models.PositiveSmallIntegerField(default=0)
    physical = models.PositiveSmallIntegerField(default=0)

    # Goalkeeper six — same 0–99 scale, shown instead of the outfield six when
    # the position is GK. Stored for every player, whatever their position, so
    # a position change never loses what was on file (mirrors the client's
    # assessment-draft behaviour).
    diving = models.PositiveSmallIntegerField(default=0)
    handling = models.PositiveSmallIntegerField(default=0)
    kicking = models.PositiveSmallIntegerField(default=0)
    reflexes = models.PositiveSmallIntegerField(default=0)
    speed = models.PositiveSmallIntegerField(default=0)
    positioning = models.PositiveSmallIntegerField(default=0)

    # The coach's standing qualitative evaluation, saved alongside the six
    # ratings. Overwritten on each assessment (it is the *current* view of the
    # player) — the per-session running commentary lives on Attendance.note.
    coach_notes = models.TextField(blank=True, default='')

    # Current FootPath Development Framework assessment. These fields mirror
    # the latest immutable PlayerDevelopmentAssessment so roster/profile reads
    # do not need one query per player. Empty values deliberately mean that no
    # five-domain assessment has been recorded; legacy 0-99 values are never
    # converted into this scale.
    development_framework_version = models.PositiveSmallIntegerField(
        null=True,
        blank=True,
    )
    development_scores = models.JSONField(default=dict, blank=True)
    development_strengths = models.TextField(blank=True, default='')
    development_targets = models.TextField(blank=True, default='')
    development_assessed_at = models.DateTimeField(null=True, blank=True)

    eligibility = models.CharField(
        max_length=20, choices=Eligibility.choices, default=Eligibility.PENDING
    )
    # Storage object path (e.g. "player-photos/12.jpg"); the API serves a signed
    # URL, never this raw path. Null until an Admin uploads a photo.
    photo_path = models.CharField(max_length=255, null=True, blank=True)

    # Optional for guardian-managed players; required only when the player is
    # provisioned with an independent Firebase login.
    middle_initial = models.CharField(max_length=5, blank=True)
    date_of_birth = models.DateField(null=True, blank=True)

    def __str__(self):
        return f'{self.user.email} · {self.get_age_tier_display()}'

    def save(self, *args, **kwargs):
        # Signals write history and notification intent inside this transaction.
        with transaction.atomic():
            if self.pk:
                type(self).objects.select_for_update().filter(pk=self.pk).exists()
            return super().save(*args, **kwargs)


class PlayerAssessmentSnapshot(models.Model):
    """Immutable evidence captured whenever a standing assessment changes."""

    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='assessment_snapshots',
        limit_choices_to={'role': Roles.PLAYER},
    )
    assessed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='player_assessment_snapshots',
        limit_choices_to={'role': Roles.COACH},
    )
    position = models.CharField(max_length=8, blank=True)
    pace = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    shooting = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    passing = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    dribbling = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    defending = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    physical = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    diving = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    handling = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    kicking = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    reflexes = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    speed = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    positioning = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    coach_notes = models.TextField(blank=True, default='')

    reason = models.CharField(
        max_length=24,
        choices=AssessmentReason.choices,
        default=AssessmentReason.GENERAL_REVIEW,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(
                fields=['player', '-created_at'],
                name='academy_assess_player_date_idx',
            ),
        ]

    @classmethod
    def from_profile(cls, profile, *, assessed_by=None, reason=None):
        return cls.objects.create(
            player=profile.user,
            assessed_by=assessed_by,
            position=profile.position,
            pace=profile.pace,
            shooting=profile.shooting,
            passing=profile.passing,
            dribbling=profile.dribbling,
            defending=profile.defending,
            physical=profile.physical,
            diving=profile.diving,
            handling=profile.handling,
            kicking=profile.kicking,
            reflexes=profile.reflexes,
            speed=profile.speed,
            positioning=profile.positioning,
            coach_notes=profile.coach_notes,
            reason=reason or AssessmentReason.GENERAL_REVIEW,
        )

    def __str__(self):
        return f'{self.player.email} assessment ({self.created_at:%Y-%m-%d})'


class PlayerDevelopmentAssessment(models.Model):
    """Immutable five-domain evidence captured for one coach assessment.

    This is intentionally separate from PlayerAssessmentSnapshot. The latter
    is the historical FUT-style 0-99 contract; keeping separate tables makes
    it impossible to mistake legacy baseline values for framework scores.
    """

    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='development_assessments',
        limit_choices_to={'role': Roles.PLAYER},
    )
    assessed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='player_development_assessments',
        limit_choices_to={'role': Roles.COACH},
    )
    position = models.CharField(max_length=8, blank=True)
    age_tier = models.CharField(max_length=20, choices=AgeTier.choices)
    age_at_assessment = models.PositiveSmallIntegerField()
    framework_version = models.PositiveSmallIntegerField()
    scores = models.JSONField(default=dict)
    strengths = models.TextField()
    development_targets = models.TextField()
    coach_notes = models.TextField(blank=True, default='')
    reason = models.CharField(
        max_length=24,
        choices=AssessmentReason.choices,
        default=AssessmentReason.GENERAL_REVIEW,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(
                fields=['player', '-created_at'],
                name='academy_dev_player_date_idx',
            ),
        ]

    @classmethod
    def from_profile(cls, profile, *, assessed_by, reason):
        return cls.objects.create(
            player=profile.user,
            assessed_by=assessed_by,
            position=profile.position,
            age_tier=profile.age_tier,
            age_at_assessment=profile.age,
            framework_version=profile.development_framework_version,
            scores=copy.deepcopy(profile.development_scores),
            strengths=profile.development_strengths,
            development_targets=profile.development_targets,
            coach_notes=profile.coach_notes,
            reason=reason,
        )

    def __str__(self):
        return f'{self.player.email} development assessment ({self.created_at:%Y-%m-%d})'


class PlayerStatsAssessment(models.Model):
    """Append-only gamified 0–99 assessment; never a development assessment."""

    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='player_stats_assessments',
        limit_choices_to={'role': Roles.PLAYER},
    )
    assessed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='assessed_player_stats_assessments',
        limit_choices_to={'role': Roles.COACH},
    )
    position = models.CharField(max_length=8)
    role_group = models.CharField(max_length=20)
    catalog_version = models.PositiveSmallIntegerField(default=1)
    scores = models.JSONField()
    overall = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(0), MaxValueValidator(99)]
    )
    reason = models.CharField(max_length=100)
    coach_notes = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(
                fields=['player', 'role_group', 'catalog_version', '-created_at'],
                name='academy_stats_compat_idx',
            )
        ]

    def save(self, *args, **kwargs):
        if self.pk:
            raise ValidationError('Player Stats assessments are immutable.')
        return super().save(*args, **kwargs)


class PlayerPrivacyPin(models.Model):
    """Salted privacy PIN state for a player account.

    This PIN is a household privacy gate, not an authentication credential.
    The hash is generated with Django's Argon2-first password hasher; plaintext
    PINs are never persisted, logged, or returned by the API.
    """

    player = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='privacy_pin',
        limit_choices_to={'role': Roles.PLAYER},
    )
    pin_hash = models.CharField(max_length=128, blank=True, default='')
    failed_attempts = models.PositiveSmallIntegerField(default=0)
    locked_until = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Player privacy PIN'
        verbose_name_plural = 'Player privacy PINs'

    def __str__(self):
        return f'{self.player.email} privacy PIN'


class PlayerEligibility(PlayerProfile):
    """Admin-only proxy: a narrow eligibility-review screen, distinct from
    the full PlayerProfile (ratings/position/etc. stay hidden here)."""

    class Meta:
        proxy = True
        verbose_name = 'Academic Eligibility'
        verbose_name_plural = 'Academic Eligibility'


class EligibilityHistory(models.Model):
    """Append-only audit trail of a player's academic eligibility transitions.

    One row per change, written by the PlayerProfile save-cycle signal (see
    signals.py) so *every* write path — Django admin, console, a future
    School Staff API — is captured with no per-view wiring. Never updated or
    deleted: the trail is the record.

    Only the status enum is stored, never a grade — same status-flags-only rule
    the eligibility field itself follows.
    """

    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='eligibility_history',
        limit_choices_to={'role': Roles.PLAYER},
    )
    # Who made the change, when known. Model signals have no request context, so
    # the acting user is stashed on the instance by the write path (the admin's
    # save_model, a view) and read here; null when a path doesn't set it.
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='eligibility_changes_made',
    )
    # Blank for the very first status a player is given (no prior value).
    old_status = models.CharField(
        max_length=20,
        choices=Eligibility.choices,
        blank=True,
    )
    new_status = models.CharField(
        max_length=20,
        choices=Eligibility.choices,
    )
    changed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-changed_at', '-id']
        verbose_name = 'Eligibility history'
        verbose_name_plural = 'Eligibility history'

    def __str__(self):
        return (
            f'{self.player.email}: {self.old_status or "—"} → '
            f'{self.new_status} ({self.changed_at:%Y-%m-%d})'
        )
