"""Academy domain models extracted from the legacy model module."""

from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import (
    MaxValueValidator,
    MinValueValidator,
)
from django.db import models
from django.utils import timezone

from academy.model_players import (
    PLAYER_POSITION_CODES,
    FixtureStatus,
    MatchCategory,
    MatchVenue,
)
from accounts.models import Roles


class FootballMatch(models.Model):
    """One completed match owned by a club.

    Ownership is stamped from the authenticated Coordinator by the API. Keeping the
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
    category = models.CharField(
        max_length=20,
        choices=MatchCategory.choices,
        default=MatchCategory.OTHER,
    )
    our_score = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
    opponent_score = models.PositiveSmallIntegerField(validators=[MaxValueValidator(99)])
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
            raise ValidationError(
                {'played_on': 'Match statistics can only be recorded after play.'}
            )

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
            models.Index(
                fields=['club', 'category', '-played_on'],
                name='academy_match_category_idx',
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
    venue = models.CharField(max_length=160, blank=True)
    starts_on = models.DateField(default=timezone.localdate)
    document_path = models.CharField(max_length=500, blank=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='uploaded_tournament_schedules',
    )
    is_published = models.BooleanField(default=False)
    published_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        super().clean()
        self.title = self.title.strip()
        self.venue = self.venue.strip()
        if not self.title:
            raise ValidationError({'title': 'Tournament title is required.'})

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    class Meta:
        ordering = ['-starts_on', '-id']
        indexes = [
            models.Index(
                fields=['club', '-published_at'],
                name='academy_tourn_club_pub_idx',
            ),
        ]

    def __str__(self):
        return f'{self.club.name} · {self.title}'

    @property
    def lifecycle_status(self):
        """Return the shared web/mobile tournament lifecycle label.

        Draft and Published are explicit. In Progress and Completed are
        derived from the authoritative fixture rows so the two clients cannot
        disagree about a second, independently-stored status value.
        """
        if not self.is_published:
            return 'DRAFT'
        fixture_states = list(self.fixtures.values_list('status', flat=True))
        has_completed = FixtureStatus.COMPLETED in fixture_states
        active_states = [value for value in fixture_states if value != FixtureStatus.CANCELLED]
        if active_states and all(value == FixtureStatus.COMPLETED for value in active_states):
            return 'COMPLETED'
        if has_completed or self.starts_on <= timezone.localdate():
            return 'IN_PROGRESS'
        return 'PUBLISHED'

    def publication_errors(self):
        """Return lifecycle validation shared by the portal and REST API."""
        errors = {}
        if not self.title.strip():
            errors['title'] = 'Tournament name is required.'
        if self.starts_on is None:
            errors['startsOn'] = 'Tournament start date is required.'
        if not self.venue.strip():
            errors['venue'] = 'Main venue is required.'
        if not self.age_brackets.exists():
            errors['ageBrackets'] = 'Add at least one age bracket before publishing.'
        elif self.age_brackets.filter(academy_tiers=[]).exists():
            errors['ageBrackets'] = 'Associate every age bracket with at least one academy tier.'
        fixtures = list(self.fixtures.select_related('age_bracket'))
        if not fixtures:
            errors['fixtures'] = 'Add at least one fixture before publishing.'
            return errors
        incomplete = [
            fixture
            for fixture in fixtures
            if fixture.age_bracket_id is None
            or not fixture.stage.strip()
            or not fixture.location.strip()
            or fixture.ends_at is None
        ]
        if incomplete:
            errors['fixtures'] = (
                'Every fixture needs an age bracket, stage, kickoff, venue, '
                'and location before publishing.'
            )
        if not any(
            fixture.status in (FixtureStatus.SCHEDULED, FixtureStatus.POSTPONED)
            for fixture in fixtures
        ):
            errors['fixtures'] = 'At least one scheduled or postponed fixture is required.'
        return errors


class TournamentAgeBracket(models.Model):
    """One flexible U-age division announced for a tournament."""

    schedule = models.ForeignKey(
        TournamentSchedule,
        on_delete=models.CASCADE,
        related_name='age_brackets',
    )
    max_age = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(3), MaxValueValidator(21)],
    )
    scheduled_at = models.DateTimeField(null=True, blank=True)
    academy_tiers = models.JSONField(default=list)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def label(self):
        return f'U{self.max_age}'

    class Meta:
        ordering = ['max_age', 'id']
        constraints = [
            models.UniqueConstraint(
                fields=['schedule', 'max_age'],
                name='academy_unique_tournament_age_bracket',
            ),
        ]
        indexes = [
            models.Index(
                fields=['schedule', 'max_age'],
                name='academy_tourn_bracket_idx',
            ),
        ]

    def __str__(self):
        return f'{self.schedule.title} - {self.label}'


class TournamentSquadStatus(models.TextChoices):
    DRAFT = 'DRAFT', 'Draft'
    PUBLISHED = 'PUBLISHED', 'Published'


class TournamentSquad(models.Model):
    """The club's shared Coach-managed roster for one age bracket."""

    bracket = models.OneToOneField(
        TournamentAgeBracket,
        on_delete=models.CASCADE,
        related_name='squad',
    )
    status = models.CharField(
        max_length=20,
        choices=TournamentSquadStatus.choices,
        default=TournamentSquadStatus.DRAFT,
    )
    published_at = models.DateTimeField(null=True, blank=True)
    updated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='updated_tournament_squads',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'{self.bracket} - {self.get_status_display()}'


class TournamentSquadEntry(models.Model):
    """One player selected for a bracket, with an optional event position."""

    squad = models.ForeignKey(
        TournamentSquad,
        on_delete=models.CASCADE,
        related_name='entries',
    )
    player = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='tournament_squad_entries',
        limit_choices_to={'role': Roles.PLAYER},
    )
    position = models.CharField(max_length=8, blank=True)
    added_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='added_tournament_squad_entries',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        super().clean()
        self.position = self.position.strip().upper()
        if self.position and self.position not in PLAYER_POSITION_CODES:
            raise ValidationError({'position': 'Unknown player position.'})
        if self.player_id and self.squad_id:
            if self.player.role != Roles.PLAYER:
                raise ValidationError({'player': 'Squad members must be players.'})
            if self.player.club_id != self.squad.bracket.schedule.club_id:
                raise ValidationError(
                    {'player': 'Squad members must belong to the tournament club.'}
                )

    def save(self, *args, **kwargs):
        self.full_clean()
        return super().save(*args, **kwargs)

    class Meta:
        ordering = ['player__last_name', 'player__first_name', 'player_id']
        constraints = [
            models.UniqueConstraint(
                fields=['squad', 'player'],
                name='academy_unique_tournament_squad_player',
            ),
        ]
        indexes = [
            models.Index(
                fields=['squad', 'player'],
                name='academy_tourn_squad_player_idx',
            ),
        ]

    def __str__(self):
        return f'{self.squad.bracket} - {self.player.email}'


class TournamentFixture(models.Model):
    """One structured fixture within a published tournament schedule."""

    schedule = models.ForeignKey(
        TournamentSchedule,
        on_delete=models.CASCADE,
        related_name='fixtures',
    )
    age_bracket = models.ForeignKey(
        TournamentAgeBracket,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='fixtures',
    )
    stage = models.CharField(max_length=80, blank=True)
    opponent = models.CharField(max_length=120, default='TBD')
    kickoff_at = models.DateTimeField()
    ends_at = models.DateTimeField(null=True, blank=True)
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
        if (
            self.age_bracket_id
            and self.schedule_id
            and self.age_bracket.schedule_id != self.schedule_id
        ):
            raise ValidationError({'age_bracket': 'Age bracket must belong to this tournament.'})
        if self.ends_at and self.kickoff_at and self.ends_at <= self.kickoff_at:
            raise ValidationError({'ends_at': 'Expected end time must be later than kickoff.'})
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

    @property
    def effective_ends_at(self):
        return self.ends_at or self.kickoff_at + timedelta(hours=2)

    @property
    def can_record_result(self):
        if (
            self.completed_match_id
            or self.status != FixtureStatus.SCHEDULED
            or not self.schedule.is_published
            or self.opponent.strip().upper() == 'TBD'
        ):
            return False
        kickoff = self.kickoff_at
        kickoff_date = (
            timezone.localtime(kickoff).date() if timezone.is_aware(kickoff) else kickoff.date()
        )
        return kickoff_date <= timezone.localdate()
