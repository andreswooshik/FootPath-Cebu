"""Academy domain models — player profiles, training sessions, attendance.

Identity and roles live in `accounts` (see ADR 0001); this app holds the
football-domain data keyed to those users. Wire values (uppercase enums like
FOUNDATION / PRESENT) mirror the Flutter entities in
`footpath_cebu/lib/domain/entities/` so the JSON contract needs no translation
layer on the client.
"""
import re
from datetime import date

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from accounts.models import Roles


class AgeTier(models.TextChoices):
    FOUNDATION = 'FOUNDATION', 'Foundation'      # ages 10–12
    DEVELOPMENT = 'DEVELOPMENT', 'Development'    # ages 13–15
    PATHWAY = 'PATHWAY', 'Pathway'               # ages 16–18


class AgeTierSetting(models.Model):
    """Admin-configurable age boundaries for one tier.

    Exactly three rows, seeded by migration — Admin edits the boundaries,
    never the set of tiers: the tier names are a wire contract with the
    client. The boundaries decide a NEW player's initial tier from their date
    of birth; existing players keep their stored tier (see PlayerProfile),
    so retuning a boundary never reshuffles the current roster.
    """

    tier = models.CharField(
        max_length=20, choices=AgeTier.choices, unique=True
    )
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
        age = today.year - date_of_birth.year - (
            (today.month, today.day)
            < (date_of_birth.month, date_of_birth.day)
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


class AttendanceStatus(models.TextChoices):
    PRESENT = 'PRESENT', 'Present'
    ABSENT = 'ABSENT', 'Absent'
    EXCUSED = 'EXCUSED', 'Excused'


class ConfirmationStatus(models.TextChoices):
    CONFIRMED = 'CONFIRMED', 'Confirmed'
    DECLINED = 'DECLINED', 'Declined'


class MatchVenue(models.TextChoices):
    HOME = 'HOME', 'Home'
    AWAY = 'AWAY', 'Away'
    NEUTRAL = 'NEUTRAL', 'Neutral'


class FixtureStatus(models.TextChoices):
    SCHEDULED = 'SCHEDULED', 'Scheduled'
    POSTPONED = 'POSTPONED', 'Postponed'
    CANCELLED = 'CANCELLED', 'Cancelled'
    COMPLETED = 'COMPLETED', 'Completed'


PLAYER_POSITION_CODES = {
    'GK', 'CB', 'LB', 'RB', 'CDM', 'CM', 'CAM', 'LW', 'RW', 'ST',
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
        max_length=20, choices=Eligibility.choices, blank=True,
    )
    new_status = models.CharField(
        max_length=20, choices=Eligibility.choices,
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
            errors[missing_field] = (
                'Start time and end time must be provided together.'
            )
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
                errors[field] = (
                    'Use a 12-hour time such as 04:30 PM.'
                )
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
            raise ValidationError({
                'end_time': 'End time must be later than start time.'
            })
        return normalized['start_time'], normalized['end_time']

    def clean(self):
        super().clean()
        self.start_time, self.end_time = self.validate_time_window(
            self.start_time, self.end_time
        )

    def save(self, *args, **kwargs):
        # ModelForm/admin calls full_clean automatically, but ordinary ORM
        # create/save does not. Enforce the same invariant on both paths.
        self.full_clean()
        return super().save(*args, **kwargs)

    class Meta:
        ordering = ['-date']

    def __str__(self):
        return f'{self.title} ({self.date})'


class FootballMatch(models.Model):
    """One completed match owned by a club.

    Ownership is stamped from the authenticated coach by the API. Keeping the
    match separate from its per-player rows lets one result serve the whole
    squad without duplicating opponent and score data for every player.
    """

    club = models.ForeignKey(
        'accounts.Club',
        on_delete=models.PROTECT,
        related_name='football_matches',
    )
    opponent = models.CharField(max_length=120)
    competition = models.CharField(max_length=120, blank=True)
    played_on = models.DateField()
    venue = models.CharField(
        max_length=10,
        choices=MatchVenue.choices,
        default=MatchVenue.HOME,
    )
    our_score = models.PositiveSmallIntegerField(
        validators=[MaxValueValidator(99)]
    )
    opponent_score = models.PositiveSmallIntegerField(
        validators=[MaxValueValidator(99)]
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='created_football_matches',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        super().clean()
        self.opponent = self.opponent.strip()
        self.competition = self.competition.strip()
        if not self.opponent:
            raise ValidationError({'opponent': 'Opponent is required.'})
        if self.played_on and self.played_on > timezone.localdate():
            raise ValidationError({
                'played_on': 'Match statistics can only be recorded after play.'
            })

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    class Meta:
        ordering = ['-played_on', '-id']
        indexes = [
            models.Index(
                fields=['club', '-played_on'],
                name='academy_match_club_date_idx',
            ),
        ]

    def __str__(self):
        return f'{self.club.name} vs {self.opponent} ({self.played_on})'


class TournamentSchedule(models.Model):
    """A published tournament programme owned by one club.

    ``document_path`` is an opaque server-side storage reference. Clients only
    receive short-lived signed URLs after the API verifies role and tenancy.
    Structured fixtures, rather than the uploaded document, drive the mobile
    schedule and completed-match workflow.
    """

    club = models.ForeignKey(
        'accounts.Club',
        on_delete=models.PROTECT,
        related_name='tournament_schedules',
    )
    title = models.CharField(max_length=120)
    document_path = models.CharField(max_length=500, blank=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='uploaded_tournament_schedules',
    )
    is_published = models.BooleanField(default=True)
    published_at = models.DateTimeField(default=timezone.now)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        super().clean()
        self.title = self.title.strip()
        if not self.title:
            raise ValidationError({'title': 'Tournament title is required.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    class Meta:
        ordering = ['-published_at', '-id']
        indexes = [
            models.Index(
                fields=['club', '-published_at'],
                name='academy_tourn_club_pub_idx',
            ),
        ]

    def __str__(self):
        return f'{self.club.name} · {self.title}'


class TournamentFixture(models.Model):
    """One structured fixture within a published tournament schedule."""

    schedule = models.ForeignKey(
        TournamentSchedule,
        on_delete=models.CASCADE,
        related_name='fixtures',
    )
    stage = models.CharField(max_length=80, blank=True)
    opponent = models.CharField(max_length=120, default='TBD')
    kickoff_at = models.DateTimeField()
    venue = models.CharField(
        max_length=10,
        choices=MatchVenue.choices,
        default=MatchVenue.NEUTRAL,
    )
    location = models.CharField(max_length=160, blank=True)
    status = models.CharField(
        max_length=20,
        choices=FixtureStatus.choices,
        default=FixtureStatus.SCHEDULED,
    )
    completed_match = models.OneToOneField(
        FootballMatch,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='source_fixture',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        super().clean()
        self.stage = self.stage.strip()
        self.opponent = self.opponent.strip() or 'TBD'
        self.location = self.location.strip()
        if self.completed_match_id:
            if self.completed_match.club_id != self.schedule.club_id:
                raise ValidationError(
                    {'completed_match': 'Fixture and match must belong to the same club.'}
                )
            self.status = FixtureStatus.COMPLETED

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    class Meta:
        ordering = ['kickoff_at', 'id']
        indexes = [
            models.Index(
                fields=['schedule', 'kickoff_at'],
                name='academy_fixture_sched_idx',
            ),
        ]

    def __str__(self):
        return f'{self.schedule.title} · {self.opponent}'


class PlayerMatchPerformance(models.Model):
    """A coach-recorded performance for one player in one match.

    Rows are historical and match-scoped. Updating a player's standing profile
    ratings never changes this evidence, which makes genuine trends possible.
    """

    match = models.ForeignKey(
        FootballMatch,
        on_delete=models.CASCADE,
        related_name='performances',
    )
    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='match_performances',
        limit_choices_to={'role': Roles.PLAYER},
    )
    position = models.CharField(max_length=8, blank=True)
    starter = models.BooleanField(default=False)
    minutes_played = models.PositiveSmallIntegerField(
        default=0,
        validators=[MaxValueValidator(180)],
    )
    goals = models.PositiveSmallIntegerField(default=0)
    assists = models.PositiveSmallIntegerField(default=0)
    shots = models.PositiveSmallIntegerField(default=0)
    shots_on_target = models.PositiveSmallIntegerField(default=0)
    passes_attempted = models.PositiveSmallIntegerField(default=0)
    passes_completed = models.PositiveSmallIntegerField(default=0)
    tackles = models.PositiveSmallIntegerField(default=0)
    interceptions = models.PositiveSmallIntegerField(default=0)
    yellow_cards = models.PositiveSmallIntegerField(
        default=0,
        validators=[MaxValueValidator(2)],
    )
    red_cards = models.PositiveSmallIntegerField(
        default=0,
        validators=[MaxValueValidator(1)],
    )
    saves = models.PositiveSmallIntegerField(default=0)
    goals_conceded = models.PositiveSmallIntegerField(default=0)
    clean_sheet = models.BooleanField(default=False)
    coach_rating = models.DecimalField(
        max_digits=3,
        decimal_places=1,
        validators=[MinValueValidator(0), MaxValueValidator(10)],
    )
    notes = models.CharField(max_length=1000, blank=True)
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='recorded_match_performances',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        super().clean()
        errors = {}
        self.position = self.position.strip().upper()
        self.notes = self.notes.strip()
        if self.position and self.position not in PLAYER_POSITION_CODES:
            errors['position'] = 'Unknown player position.'
        if self.player_id and self.player.role != Roles.PLAYER:
            errors['player'] = 'Match performances belong to player accounts.'
        if (
            self.player_id
            and self.match_id
            and self.player.club_id != self.match.club_id
        ):
            errors['player'] = 'Player must belong to the match club.'
        if self.shots_on_target > self.shots:
            errors['shots_on_target'] = (
                'Shots on target cannot exceed total shots.'
            )
        if self.goals > self.shots_on_target:
            errors['goals'] = 'Goals cannot exceed shots on target.'
        if self.passes_completed > self.passes_attempted:
            errors['passes_completed'] = (
                'Completed passes cannot exceed attempted passes.'
            )
        if self.clean_sheet and self.goals_conceded:
            errors['clean_sheet'] = (
                'A clean sheet cannot include goals conceded.'
            )
        if self.position != 'GK' and (
            self.saves or self.goals_conceded or self.clean_sheet
        ):
            errors['position'] = 'Goalkeeper statistics require the GK position.'
        if errors:
            raise ValidationError(errors)

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    class Meta:
        ordering = ['-match__played_on', '-id']
        constraints = [
            models.UniqueConstraint(
                fields=['match', 'player'],
                name='unique_player_match_performance',
            ),
            models.CheckConstraint(
                condition=models.Q(shots_on_target__lte=models.F('shots')),
                name='shots_on_target_lte_shots',
            ),
            models.CheckConstraint(
                condition=models.Q(goals__lte=models.F('shots_on_target')),
                name='goals_lte_shots_on_target',
            ),
            models.CheckConstraint(
                condition=models.Q(
                    passes_completed__lte=models.F('passes_attempted')
                ),
                name='passes_completed_lte_attempted',
            ),
        ]
        indexes = [
            models.Index(
                fields=['player', 'match'],
                name='academy_perf_player_match_idx',
            ),
        ]

    def __str__(self):
        return f'{self.player.email} vs {self.match.opponent}'


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
    # Effort/intensity the coach observed for this one session, 0–100. Session-
    # scoped, unlike the long-lived profile ratings. Null when not recorded
    # (e.g. the player was absent).
    effort = models.PositiveSmallIntegerField(null=True, blank=True)
    # The coach's short remark about this player on this day.
    note = models.CharField(max_length=1000, blank=True)
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
        # The session upsert keys on (player, session); without this nothing
        # stops duplicate rows for the same player on the same session.
        unique_together = ('player', 'session')
        indexes = [
            models.Index(
                fields=['session', 'status'],
                name='academy_att_session_status_idx',
            ),
        ]

    def __str__(self):
        return f'{self.player.email} · {self.status} · {self.updated_at:%Y-%m-%d}'


class SessionConfirmation(models.Model):
    """A player's RSVP for a session — set by the player on the session day.
    Distinct from [Attendance], which the coach records
    during/after: this is intent, that is fact.

    One row per (player, session); confirming again flips the same row's status
    rather than stacking new rows.
    """

    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='session_confirmations',
        limit_choices_to={'role': Roles.PLAYER},
    )
    session = models.ForeignKey(
        TrainingSession,
        on_delete=models.CASCADE,
        related_name='confirmations',
    )
    status = models.CharField(
        max_length=10, choices=ConfirmationStatus.choices,
        default=ConfirmationStatus.CONFIRMED,
    )
    responded_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-responded_at']
        unique_together = ('player', 'session')

    def __str__(self):
        return f'{self.player.email} · {self.status} · {self.session_id}'


class InjuryStatus(models.TextChoices):
    ACTIVE = 'ACTIVE', 'Active'
    RECOVERING = 'RECOVERING', 'Recovering'
    RECOVERED = 'RECOVERED', 'Recovered'


class InjuryRecord(models.Model):
    """A player's self-reported injury. Medical data: the player owns the
    record (full CRUD); coach/admin read, and a guardian may read a linked
    child's records — least-privilege, enforced in the views."""

    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='injury_records',
        limit_choices_to={'role': Roles.PLAYER},
    )
    description = models.CharField(max_length=200)
    body_part = models.CharField(max_length=80, blank=True)
    status = models.CharField(
        max_length=20, choices=InjuryStatus.choices, default=InjuryStatus.ACTIVE
    )
    occurred_on = models.DateField()
    resolved_on = models.DateField(null=True, blank=True)
    notes = models.CharField(max_length=1000, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-occurred_on', '-id']
        indexes = [
            models.Index(
                fields=['player', '-occurred_on'],
                name='academy_injury_player_date_idx',
            ),
        ]

    def __str__(self):
        return f'{self.player.email} · {self.description} · {self.status}'


class DisputeCategory(models.TextChoices):
    ATTENDANCE = 'ATTENDANCE', 'Attendance'
    ASSESSMENT = 'ASSESSMENT', 'Assessment'
    ELIGIBILITY = 'ELIGIBILITY', 'Eligibility'
    CONDUCT = 'CONDUCT', 'Conduct'
    OTHER = 'OTHER', 'Other'


class DisputeStatus(models.TextChoices):
    OPEN = 'OPEN', 'Open'
    UNDER_REVIEW = 'UNDER_REVIEW', 'Under Review'
    RESOLVED = 'RESOLVED', 'Resolved'
    DISMISSED = 'DISMISSED', 'Dismissed'


class Dispute(models.Model):
    """A flagged issue raised by a coach — a status ticket, not a generic
    audit log. The append-only [DisputeResponse] thread is the audit trail:
    responses are never updated or deleted."""

    raised_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name='raised_disputes',
    )
    # The player the dispute concerns, when there is one; a general dispute
    # (e.g. scheduling) has none.
    subject_player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='subject_disputes',
        limit_choices_to={'role': Roles.PLAYER},
    )
    category = models.CharField(
        max_length=20, choices=DisputeCategory.choices,
        default=DisputeCategory.OTHER,
    )
    status = models.CharField(
        max_length=20, choices=DisputeStatus.choices,
        default=DisputeStatus.OPEN,
    )
    summary = models.CharField(max_length=200)
    detail = models.CharField(max_length=2000, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.summary} · {self.status}'


class DisputeResponse(models.Model):
    """One append-only entry in a dispute's thread. May carry a status change,
    which the create view applies to the parent dispute."""

    dispute = models.ForeignKey(
        Dispute, on_delete=models.CASCADE, related_name='responses'
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name='dispute_responses',
    )
    body = models.CharField(max_length=2000)
    status_change_to = models.CharField(
        max_length=20, choices=DisputeStatus.choices, null=True, blank=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f'Re: {self.dispute.summary} ({self.created_at:%Y-%m-%d})'


class AuditLog(models.Model):
    """Append-only record of sensitive changes across the system.

    One row per change, written by the view/service performing it via
    [AuditLog.record]. Complements the two purpose-built trails (the dispute
    response thread and EligibilityHistory) with everything else: account
    lifecycle, guardian links, session scheduling, assessments. Never updated
    or deleted — the admin surface blocks all three verbs.
    """

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='audit_entries',
    )
    # Dotted event name, e.g. 'session.cancelled', 'account.role_changed'.
    action = models.CharField(max_length=40)
    # Human-readable subject ("who/what it happened to"), usually an email or
    # a session title — denormalised on purpose so the row still reads after
    # the target is deleted.
    target = models.CharField(max_length=200, blank=True)
    detail = models.CharField(max_length=500, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']

    def __str__(self):
        return f'{self.action} · {self.target} · {self.created_at:%Y-%m-%d %H:%M}'

    @classmethod
    def record(cls, actor, action, target='', detail=''):
        """Write one entry. Truncates instead of raising — an audit write must
        never fail the change it documents."""
        return cls.objects.create(
            actor=actor if getattr(actor, 'pk', None) else None,
            action=action[:40],
            target=str(target)[:200],
            detail=str(detail)[:500],
        )


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


class NotificationRecord(models.Model):
    """Server-authoritative notification inbox entry for one recipient.

    FCM is only a best-effort delivery channel. Persisting the neutral message
    first gives users history even when permission is denied, a token is
    stale, or Firebase is temporarily unavailable.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notification_records',
    )
    event_type = models.CharField(max_length=40)
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=300)
    data = models.JSONField(default=dict, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(
                fields=['user', 'read_at', '-created_at'],
                name='notif_user_read_created_idx',
            ),
        ]

    def __str__(self):
        return f'{self.user.email} · {self.event_type} · {self.created_at:%Y-%m-%d}'
