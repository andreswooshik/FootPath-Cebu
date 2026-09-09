"""Per-player match-performance model."""

from .model_tournaments import *  # noqa: F401,F403

class PlayerMatchPerformance(models.Model):
    """Role-separated statistics and evaluation for one player/match.

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
        null=True,
        blank=True,
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
    rated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='rated_match_performances',
    )
    rated_at = models.DateTimeField(null=True, blank=True)
    squad_override_reason = models.CharField(max_length=500, blank=True)
    squad_override_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='approved_match_squad_overrides',
    )
    squad_override_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        super().clean()
        errors = {}
        self.position = self.position.strip().upper()
        self.notes = self.notes.strip()
        self.squad_override_reason = self.squad_override_reason.strip()
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
            models.CheckConstraint(
                condition=(
                    models.Q(
                        squad_override_reason='',
                        squad_override_at__isnull=True,
                    )
                    | (
                        ~models.Q(squad_override_reason='')
                        & models.Q(squad_override_at__isnull=False)
                    )
                ),
                name='squad_override_reason_requires_timestamp',
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
