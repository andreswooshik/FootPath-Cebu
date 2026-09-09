"""Academy serializers extracted from the legacy serializer module."""

from .serializer_players import *  # noqa: F401,F403

class TrainingSessionSerializer(serializers.ModelSerializer):
    """Matches TrainingSession.fromJson/toJson: id, title, ageTiers, date,
    startTime, endTime, location, focus, attendeeCount."""

    id = serializers.CharField(read_only=True)
    ageTiers = serializers.ListField(
        source='age_tiers', child=serializers.CharField(), required=False,
    )
    startTime = serializers.CharField(source='start_time', required=False, allow_blank=True)
    endTime = serializers.CharField(source='end_time', required=False, allow_blank=True)
    attendeeCount = serializers.SerializerMethodField()
    cancellationReason = serializers.CharField(
        source='cancellation_reason', read_only=True,
    )
    conflictingTournamentId = serializers.CharField(
        source='conflicting_tournament_id', read_only=True, allow_null=True,
    )
    conflictingFixtureId = serializers.CharField(
        source='conflicting_fixture_id', read_only=True, allow_null=True,
    )
    cancelledAt = serializers.DateTimeField(
        source='cancelled_at', read_only=True, allow_null=True,
    )
    primaryFocus = serializers.CharField(source='focus', required=False)
    additionalFocuses = serializers.ListField(
        source='additional_focuses', child=serializers.CharField(), required=False,
    )
    sessionObjectives = serializers.CharField(source='session_objectives', required=False, allow_blank=True, max_length=2000)
    equipmentRequirements = serializers.CharField(source='equipment_requirements', required=False, allow_blank=True, max_length=2000)
    coachInstructions = serializers.CharField(source='coach_instructions', required=False, allow_blank=True, max_length=2000)
    eligiblePlayerCount = serializers.SerializerMethodField()

    class Meta:
        model = TrainingSession
        fields = [
            'id', 'title', 'ageTiers', 'date', 'startTime', 'endTime',
            'location', 'focus', 'primaryFocus', 'additionalFocuses',
            'sessionObjectives', 'equipmentRequirements', 'coachInstructions',
            'status', 'cancellationReason',
            'conflictingTournamentId', 'conflictingFixtureId', 'cancelledAt',
            'attendeeCount', 'eligiblePlayerCount',
        ]
        read_only_fields = ['status']

    def get_attendeeCount(self, obj):
        # The list view annotates this value, avoiding one query per session.
        return getattr(obj, 'present_attendee_count', 0)

    def get_eligiblePlayerCount(self, obj):
        return PlayerProfile.objects.filter(age_tier__in=obj.age_tiers, user__club_id=obj.club_id).count()

    def validate(self, attrs):
        attrs = super().validate(attrs)
        current_start = self.instance.start_time if self.instance else ''
        current_end = self.instance.end_time if self.instance else ''
        try:
            start_time, end_time = TrainingSession.validate_time_window(
                attrs.get('start_time', current_start),
                attrs.get('end_time', current_end),
            )
        except DjangoValidationError as exc:
            field_names = {
                'start_time': 'startTime',
                'end_time': 'endTime',
            }
            raise serializers.ValidationError({
                field_names.get(field, field): messages
                for field, messages in exc.message_dict.items()
            }) from exc
        attrs['start_time'] = start_time
        attrs['end_time'] = end_time
        date = attrs.get('date', self.instance.date if self.instance else None)
        if date == timezone.localdate() and start_time:
            draft = TrainingSession(date=date, start_time=start_time, end_time=end_time)
            start, _end = draft.interval()
            if start <= timezone.now():
                raise serializers.ValidationError({'startTime': 'The session start time must be in the future.'})
        focuses = attrs.get('additional_focuses', self.instance.additional_focuses if self.instance else [])
        valid = set(SessionFocus.values)
        focuses = list(dict.fromkeys(str(value).upper() for value in focuses))
        if any(value not in valid for value in focuses):
            raise serializers.ValidationError({'additionalFocuses': 'Unknown session focus.'})
        primary = attrs.get('focus', self.instance.focus if self.instance else None)
        attrs['additional_focuses'] = [value for value in focuses if value != primary]
        return attrs

    def validate_ageTiers(self, value):
        valid = set(AgeTier.values)
        cleaned = list(dict.fromkeys(t.upper() for t in value))
        bad = [t for t in cleaned if t not in valid]
        if bad:
            raise serializers.ValidationError(f'Unknown age tier(s): {bad}')
        if not cleaned:
            raise serializers.ValidationError('Select at least one age tier.')
        return cleaned

    def validate_focus(self, value):
        v = str(value).upper()
        if v not in set(SessionFocus.values):
            raise serializers.ValidationError(f'Unknown focus: {value}')
        return v

    def validate_date(self, value):
        if value < timezone.localdate():
            raise serializers.ValidationError(
                'The session date cannot be in the past.'
            )
        return value


class AttendanceSerializer(serializers.ModelSerializer):
    """Matches Attendance.fromJson: playerId, sessionId, status, effort, note,
    updatedAt, sessionName, coachUid."""

    # Hard-cast to String on the client, so coerce the int PK to a string here.
    playerId = serializers.CharField(source='player.id', read_only=True)
    sessionId = serializers.SerializerMethodField()
    updatedAt = serializers.DateTimeField(source='updated_at', read_only=True)
    sessionName = serializers.SerializerMethodField()
    coachUid = serializers.SerializerMethodField()
    note = serializers.SerializerMethodField()
    performanceScore = serializers.DecimalField(
        source='performance_score',
        max_digits=3,
        decimal_places=1,
        coerce_to_string=False,
        allow_null=True,
        read_only=True,
    )
    sessionFocus = serializers.CharField(
        source='session.focus', read_only=True, allow_null=True,
    )
    sessionDate = serializers.DateField(
        source='session.date', read_only=True, allow_null=True,
    )

    class Meta:
        model = Attendance
        fields = [
            'playerId', 'sessionId', 'status', 'effort', 'performanceScore', 'note',
            'updatedAt', 'sessionName', 'sessionFocus', 'sessionDate', 'coachUid',
        ]

    def get_sessionId(self, obj):
        return str(obj.session_id) if obj.session_id else None

    def get_sessionName(self, obj):
        return obj.session.title if obj.session_id else None

    def get_coachUid(self, obj):
        return obj.recorded_by.firebase_uid if obj.recorded_by_id else None

    def get_note(self, obj):
        # The client treats note as nullable; a blank stored note is "no note".
        return obj.note or None


class SessionConfirmationSerializer(serializers.ModelSerializer):
    """Matches SessionConfirmation.fromJson: sessionId, playerId, status,
    respondedAt. Read-only shape — writes go through the view, which sets the
    player from the request and upserts on (player, session)."""

    # Hard-cast to String on the client, so coerce the int PKs to strings.
    playerId = serializers.CharField(source='player.id', read_only=True)
    sessionId = serializers.CharField(source='session.id', read_only=True)
    respondedAt = serializers.DateTimeField(source='responded_at', read_only=True)

    class Meta:
        model = SessionConfirmation
        fields = ['sessionId', 'playerId', 'status', 'respondedAt']


class EligibilityHistorySerializer(serializers.ModelSerializer):
    """Read shape for GET /api/players/<id>/eligibility-history/. Matches the
    Flutter EligibilityChange.fromJson: id, oldStatus, newStatus, changedAt,
    changedBy.

    `changedBy` is privacy-aware: School Staff / Admin see the individual who
    made the change; a Player or Guardian sees only the *role* that made it —
    families get the full timeline and accountability, never a staff member's
    personal identity. A change with no known actor reads as 'System'.
    """

    id = serializers.CharField(read_only=True)
    oldStatus = serializers.CharField(source='old_status')
    newStatus = serializers.CharField(source='new_status')
    changedAt = serializers.DateTimeField(source='changed_at')
    changedBy = serializers.SerializerMethodField()

    class Meta:
        model = EligibilityHistory
        fields = ['id', 'oldStatus', 'newStatus', 'changedAt', 'changedBy']

    def get_changedBy(self, obj):
        actor = obj.changed_by
        if actor is None:
            return 'System'
        request = self.context.get('request')
        viewer = getattr(request, 'user', None)
        privileged = viewer is not None and viewer.role in (
            Roles.SCHOOL_STAFF, Roles.ADMIN,
        )
        # Staff/Admin see the person; Player/Guardian see only the role.
        return _display_name(actor) if privileged else actor.get_role_display()
