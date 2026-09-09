"""Academy domain models extracted from the legacy model module."""

from .model_players import *  # noqa: F401,F403
from .model_training import *  # noqa: F401,F403
from .model_tournaments import *  # noqa: F401,F403

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
    # Quality of the player's performance, intentionally separate from effort.
    performance_score = models.DecimalField(
        max_digits=3,
        decimal_places=1,
        null=True,
        blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(10)],
    )
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
            models.Index(
                fields=['player', '-updated_at'],
                name='academy_att_player_date_idx',
            ),
        ]
        constraints = [
            models.CheckConstraint(
                condition=(
                    models.Q(status=AttendanceStatus.PRESENT)
                    | (
                        models.Q(effort__isnull=True)
                        & models.Q(performance_score__isnull=True)
                    )
                ),
                name='attendance_scores_require_present',
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(effort__isnull=True)
                    | models.Q(effort__gte=0, effort__lte=100)
                ),
                name='attendance_effort_0_100',
            ),
            models.CheckConstraint(
                condition=(
                    models.Q(performance_score__isnull=True)
                    | models.Q(
                        performance_score__gte=0,
                        performance_score__lte=10,
                    )
                ),
                name='attendance_performance_0_10',
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


class InjuryReportStatus(models.TextChoices):
    PENDING = 'PENDING', 'Pending confirmation'
    CONFIRMED = 'CONFIRMED', 'Confirmed'
    REJECTED = 'REJECTED', 'Rejected'
    ARCHIVED = 'ARCHIVED', 'Archived'


class InjuryUpdateReviewStatus(models.TextChoices):
    PENDING = 'PENDING', 'Pending'
    APPROVED = 'APPROVED', 'Approved'
    REJECTED = 'REJECTED', 'Rejected'


class InjuryRecord(models.Model):
    """A private care-team injury report with Coordinator confirmation.

    Players, linked Guardians, Coaches, and Coordinators may report an injury.
    Pending reports remain editable by their reporter; confirmed clinical
    state and archival are controlled by the club Coordinator.
    """

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
    reported_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reported_injuries',
    )
    review_status = models.CharField(
        max_length=20,
        choices=InjuryReportStatus.choices,
        default=InjuryReportStatus.PENDING,
    )
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_injuries',
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.CharField(max_length=500, blank=True)
    archived_at = models.DateTimeField(null=True, blank=True)
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


class InjuryStatusUpdateRequest(models.Model):
    """A care-team recovery update awaiting Coordinator approval."""

    injury = models.ForeignKey(
        InjuryRecord,
        on_delete=models.CASCADE,
        related_name='status_update_requests',
    )
    proposed_status = models.CharField(
        max_length=20,
        choices=InjuryStatus.choices,
    )
    proposed_resolved_on = models.DateField(null=True, blank=True)
    notes = models.CharField(max_length=500, blank=True)
    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name='submitted_injury_status_updates',
    )
    review_status = models.CharField(
        max_length=20,
        choices=InjuryUpdateReviewStatus.choices,
        default=InjuryUpdateReviewStatus.PENDING,
    )
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_injury_status_updates',
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.CharField(max_length=500, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at', '-id']
        constraints = [
            models.UniqueConstraint(
                fields=['injury'],
                condition=models.Q(
                    review_status=InjuryUpdateReviewStatus.PENDING,
                ),
                name='academy_one_pending_injury_update',
            ),
        ]


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


class AuditLogQuerySet(models.QuerySet):
    def update(self, **kwargs):
        raise TypeError('Audit log entries are append-only.')

    def delete(self):
        raise TypeError('Audit log entries are append-only.')


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
    created_at = models.DateTimeField(default=timezone.now, editable=False)
    previous_hash = models.CharField(max_length=64, blank=True, editable=False)
    entry_hash = models.CharField(
        max_length=64, unique=True, editable=False,
    )

    objects = AuditLogQuerySet.as_manager()

    class Meta:
        ordering = ['-created_at', '-id']

    def __str__(self):
        return f'{self.action} · {self.target} · {self.created_at:%Y-%m-%d %H:%M}'

    def save(self, *args, **kwargs):
        if self.pk:
            raise TypeError('Audit log entries are append-only.')
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise TypeError('Audit log entries are append-only.')

    @staticmethod
    def _digest(*, previous_hash, action, target, detail, created_at):
        payload = json.dumps({
            'previous_hash': previous_hash,
            'action': action,
            'target': target,
            'detail': detail,
            'created_at': created_at.isoformat(),
        }, sort_keys=True, separators=(',', ':')).encode('utf-8')
        return hashlib.sha256(payload).hexdigest()

    @classmethod
    def record(cls, actor, action, target='', detail=''):
        """Append one hash-chained entry and emit its proof externally."""
        action = action[:40]
        target = str(target)[:200]
        detail = str(detail)[:500]
        created_at = timezone.now()
        with transaction.atomic():
            if connection.vendor == 'postgresql':
                with connection.cursor() as cursor:
                    cursor.execute('SELECT pg_advisory_xact_lock(%s)', [946271])
            previous = cls.objects.exclude(entry_hash__isnull=True).order_by(
                '-created_at', '-id'
            ).first()
            previous_hash = previous.entry_hash if previous else ''
            entry = cls.objects.create(
                actor=actor if getattr(actor, 'pk', None) else None,
                action=action,
                target=target,
                detail=detail,
                created_at=created_at,
                previous_hash=previous_hash,
                entry_hash=cls._digest(
                    previous_hash=previous_hash,
                    action=action,
                    target=target,
                    detail=detail,
                    created_at=created_at,
                ),
            )
        external_event = json.dumps({
            'event': 'audit_log',
            'id': entry.pk,
            'entry_hash': entry.entry_hash,
            'previous_hash': entry.previous_hash,
            'action': entry.action,
        }, sort_keys=True, separators=(',', ':'))
        transaction.on_commit(lambda: audit_logger.info(external_event))
        return entry

    @classmethod
    def verify_chain(cls):
        """Return ``(is_valid, failing_id)`` for chained entries."""
        previous_hash = ''
        for entry in cls.objects.exclude(entry_hash__isnull=True).order_by(
            'created_at', 'id'
        ):
            expected = cls._digest(
                previous_hash=previous_hash,
                action=entry.action,
                target=entry.target,
                detail=entry.detail,
                created_at=entry.created_at,
            )
            if entry.previous_hash != previous_hash or entry.entry_hash != expected:
                return False, entry.pk
            previous_hash = entry.entry_hash
        return True, None

__all__ = [name for name in globals() if not name.startswith('__')]
