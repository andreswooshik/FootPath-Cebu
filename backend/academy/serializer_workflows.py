"""Academy serializers extracted from the legacy serializer module."""

from .serializer_players import *  # noqa: F401,F403

from .serializer_training import *  # noqa: F401,F403

class InjuryStatusUpdateRequestSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    proposedStatus = serializers.CharField(source='proposed_status')
    proposedResolvedOn = serializers.DateField(
        source='proposed_resolved_on', required=False, allow_null=True,
    )
    reviewStatus = serializers.CharField(source='review_status', read_only=True)
    submittedByName = serializers.SerializerMethodField()
    submittedByRole = serializers.CharField(
        source='submitted_by.role', read_only=True, allow_null=True,
    )
    rejectionReason = serializers.CharField(
        source='rejection_reason', read_only=True,
    )
    createdAt = serializers.DateTimeField(source='created_at', read_only=True)

    class Meta:
        model = InjuryStatusUpdateRequest
        fields = [
            'id', 'proposedStatus', 'proposedResolvedOn', 'notes',
            'reviewStatus', 'submittedByName', 'submittedByRole',
            'rejectionReason', 'createdAt',
        ]
        extra_kwargs = {
            'notes': {'required': False, 'allow_blank': True, 'max_length': 500},
        }

    def get_submittedByName(self, obj):
        return _display_name(obj.submitted_by)

    def validate_proposedStatus(self, value):
        cleaned = str(value).upper()
        if cleaned not in (InjuryStatus.RECOVERING, InjuryStatus.RECOVERED):
            raise serializers.ValidationError(
                'Choose Recovering or Recovered.'
            )
        return cleaned

    def validate(self, attrs):
        attrs = super().validate(attrs)
        proposed = attrs.get('proposed_status')
        resolved = attrs.get('proposed_resolved_on')
        if proposed == InjuryStatus.RECOVERED and resolved is None:
            raise serializers.ValidationError({
                'proposedResolvedOn': 'A recovery date is required.'
            })
        if proposed != InjuryStatus.RECOVERED and resolved is not None:
            raise serializers.ValidationError({
                'proposedResolvedOn': (
                    'Only a Recovered update can include a recovery date.'
                )
            })
        if resolved and resolved > timezone.localdate():
            raise serializers.ValidationError({
                'proposedResolvedOn': 'The recovery date cannot be in the future.'
            })
        return attrs


class InjuryRecordSerializer(serializers.ModelSerializer):
    """Private injury report plus server-derived workflow capabilities."""

    id = serializers.CharField(read_only=True)
    # Read-only in serializer writes; the view validates a requested target
    # before assigning the subject player from the authenticated role.
    playerId = serializers.CharField(source='player.id', read_only=True)
    playerName = serializers.SerializerMethodField()
    bodyPart = serializers.CharField(
        source='body_part', required=False, allow_blank=True, max_length=80,
    )
    occurredOn = serializers.DateField(source='occurred_on')
    resolvedOn = serializers.DateField(
        source='resolved_on', required=False, allow_null=True,
    )
    notes = serializers.CharField(
        required=False, allow_blank=True, max_length=1000,
    )
    createdAt = serializers.DateTimeField(source='created_at', read_only=True)
    updatedAt = serializers.DateTimeField(source='updated_at', read_only=True)
    reviewStatus = serializers.CharField(source='review_status', read_only=True)
    reporterName = serializers.SerializerMethodField()
    reporterRole = serializers.CharField(
        source='reported_by.role', read_only=True, allow_null=True,
    )
    rejectionReason = serializers.CharField(
        source='rejection_reason', read_only=True,
    )
    reviewedAt = serializers.DateTimeField(source='reviewed_at', read_only=True)
    archivedAt = serializers.DateTimeField(source='archived_at', read_only=True)
    pendingStatusUpdate = serializers.SerializerMethodField()
    canEditPending = serializers.SerializerMethodField()
    canReview = serializers.SerializerMethodField()
    canEditConfirmed = serializers.SerializerMethodField()
    canArchive = serializers.SerializerMethodField()
    canRequestStatusUpdate = serializers.SerializerMethodField()

    class Meta:
        model = InjuryRecord
        fields = [
            'id', 'playerId', 'playerName', 'description', 'bodyPart', 'status',
            'occurredOn', 'resolvedOn', 'notes', 'reviewStatus',
            'reporterName', 'reporterRole', 'rejectionReason', 'reviewedAt',
            'archivedAt', 'pendingStatusUpdate', 'canEditPending', 'canReview',
            'canEditConfirmed', 'canArchive', 'canRequestStatusUpdate',
            'createdAt', 'updatedAt',
        ]

    def get_playerName(self, obj):
        return _display_name(obj.player)

    def get_reporterName(self, obj):
        return _display_name(obj.reported_by)

    def _viewer(self):
        return getattr(self.context.get('request'), 'user', None)

    def _is_coordinator(self, obj):
        viewer = self._viewer()
        return bool(
            viewer
            and viewer.role == Roles.COORDINATOR
            and viewer.club_id is not None
            and viewer.club_id == obj.player.club_id
        )

    def get_pendingStatusUpdate(self, obj):
        pending = next(
            (
                item for item in obj.status_update_requests.all()
                if item.review_status == InjuryUpdateReviewStatus.PENDING
            ),
            None,
        )
        return (
            InjuryStatusUpdateRequestSerializer(pending).data
            if pending else None
        )

    def get_canEditPending(self, obj):
        viewer = self._viewer()
        return bool(
            obj.review_status == InjuryReportStatus.PENDING
            and viewer
            and (obj.reported_by_id == viewer.id or self._is_coordinator(obj))
        )

    def get_canReview(self, obj):
        return bool(
            obj.review_status == InjuryReportStatus.PENDING
            and self._is_coordinator(obj)
        )

    def get_canEditConfirmed(self, obj):
        return bool(
            obj.review_status == InjuryReportStatus.CONFIRMED
            and self._is_coordinator(obj)
        )

    def get_canArchive(self, obj):
        return bool(
            obj.review_status == InjuryReportStatus.CONFIRMED
            and obj.status == InjuryStatus.RECOVERED
            and self._is_coordinator(obj)
        )

    def get_canRequestStatusUpdate(self, obj):
        viewer = self._viewer()
        return bool(
            viewer
            and viewer.role in (Roles.PLAYER, Roles.GUARDIAN, Roles.COACH)
            and obj.review_status == InjuryReportStatus.CONFIRMED
            and obj.status in (InjuryStatus.ACTIVE, InjuryStatus.RECOVERING)
            and self.get_pendingStatusUpdate(obj) is None
        )

    def validate_status(self, value):
        v = str(value).upper()
        if v not in set(InjuryStatus.values):
            raise serializers.ValidationError(f'Unknown status: {value}')
        return v

    def validate(self, attrs):
        attrs = super().validate(attrs)
        occurred = attrs.get(
            'occurred_on', self.instance.occurred_on if self.instance else None,
        )
        resolved = attrs.get(
            'resolved_on', self.instance.resolved_on if self.instance else None,
        )
        injury_status = attrs.get(
            'status', self.instance.status if self.instance else InjuryStatus.ACTIVE,
        )
        if occurred and occurred > timezone.localdate():
            raise serializers.ValidationError({
                'occurredOn': 'The injury date cannot be in the future.'
            })
        if resolved and occurred and resolved < occurred:
            raise serializers.ValidationError({
                'resolvedOn': 'The recovery date cannot precede the injury.'
            })
        if injury_status == InjuryStatus.RECOVERED and resolved is None:
            raise serializers.ValidationError({
                'resolvedOn': 'A recovered injury needs a recovery date.'
            })
        if injury_status != InjuryStatus.RECOVERED and resolved is not None:
            raise serializers.ValidationError({
                'resolvedOn': 'Only a recovered injury can have a recovery date.'
            })
        return attrs


class DisputeResponseSerializer(serializers.ModelSerializer):
    """Read shape for one thread entry. Matches DisputeResponse.fromJson:
    id, authorName, authorRole, body, statusChangeTo, createdAt."""

    id = serializers.CharField(read_only=True)
    authorName = serializers.SerializerMethodField()
    authorRole = serializers.SerializerMethodField()
    statusChangeTo = serializers.CharField(
        source='status_change_to', read_only=True,
    )
    createdAt = serializers.DateTimeField(source='created_at', read_only=True)

    class Meta:
        model = DisputeResponse
        fields = ['id', 'authorName', 'authorRole', 'body', 'statusChangeTo',
                  'createdAt']

    def get_authorName(self, obj):
        return _display_name(obj.author)

    def get_authorRole(self, obj):
        return obj.author.role if obj.author_id else None


class DisputeSerializer(serializers.ModelSerializer):
    """Read shape for a dispute + its full thread. Matches Dispute.fromJson:
    id, raisedByName, subjectPlayerId, subjectPlayerName, category, status,
    summary, detail, createdAt, updatedAt, responses."""

    id = serializers.CharField(read_only=True)
    raisedByName = serializers.SerializerMethodField()
    subjectPlayerId = serializers.SerializerMethodField()
    subjectPlayerName = serializers.SerializerMethodField()
    createdAt = serializers.DateTimeField(source='created_at', read_only=True)
    updatedAt = serializers.DateTimeField(source='updated_at', read_only=True)
    responses = DisputeResponseSerializer(many=True, read_only=True)

    class Meta:
        model = Dispute
        fields = [
            'id', 'raisedByName', 'subjectPlayerId', 'subjectPlayerName',
            'category', 'status', 'summary', 'detail', 'createdAt',
            'updatedAt', 'responses',
        ]

    def get_raisedByName(self, obj):
        return _display_name(obj.raised_by)

    def get_subjectPlayerId(self, obj):
        return str(obj.subject_player_id) if obj.subject_player_id else None

    def get_subjectPlayerName(self, obj):
        return _display_name(obj.subject_player)


class DisputeCreateSerializer(serializers.Serializer):
    """Write side of POST /api/disputes/ — the coach's flag. `raised_by` is
    the request user, never client-supplied."""

    subjectPlayerId = serializers.IntegerField(required=False, allow_null=True)
    category = serializers.CharField()
    summary = serializers.CharField(max_length=200)
    detail = serializers.CharField(
        max_length=2000, required=False, allow_blank=True,
    )

    def validate_category(self, value):
        v = str(value).upper()
        if v not in set(DisputeCategory.values):
            raise serializers.ValidationError(f'Unknown category: {value}')
        return v

    def validate_subjectPlayerId(self, value):
        if value is None:
            return None
        if not User.objects.filter(pk=value, role=Roles.PLAYER).exists():
            raise serializers.ValidationError(f'Unknown player id: {value}')
        return value


class DisputeResponseCreateSerializer(serializers.Serializer):
    """Write side of POST /api/disputes/<pk>/responses/. `author` is the
    request user; `statusChangeTo`, when present, moves the parent dispute."""

    body = serializers.CharField(max_length=2000)
    statusChangeTo = serializers.CharField(
        required=False, allow_null=True, allow_blank=True,
    )

    def validate_statusChangeTo(self, value):
        if not value:
            return None
        v = str(value).upper()
        if v not in set(DisputeStatus.values):
            raise serializers.ValidationError(f'Unknown status: {value}')
        return v


class SessionAttendanceRecordSerializer(serializers.Serializer):
    """Write side of POST /api/attendance/session/<id>/ — one record in the
    `records` array the coach's roll-call screen submits."""

    playerId = serializers.IntegerField()
    status = serializers.CharField()
    effort = serializers.IntegerField(
        min_value=0, max_value=100, required=False, allow_null=True,
    )
    performanceScore = serializers.DecimalField(
        max_digits=3,
        decimal_places=1,
        min_value=0,
        max_value=10,
        required=False,
        allow_null=True,
    )
    note = serializers.CharField(
        max_length=1000, required=False, allow_blank=True,
    )

    def validate_playerId(self, value):
        if not User.objects.filter(pk=value, role=Roles.PLAYER).exists():
            raise serializers.ValidationError(f'Unknown player id: {value}')
        return value

    def validate_status(self, value):
        v = str(value).upper()
        if v not in set(AttendanceStatus.values):
            raise serializers.ValidationError(f'Unknown status: {value}')
        return v

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if attrs['status'] != AttendanceStatus.PRESENT:
            attrs['effort'] = None
            attrs['performanceScore'] = None
        return attrs


class NotificationRecordSerializer(serializers.ModelSerializer):
    """Neutral, current-user-only inbox contract consumed by Flutter."""

    type = serializers.CharField(source='event_type', read_only=True)
    isRead = serializers.SerializerMethodField()
    createdAt = serializers.DateTimeField(source='created_at', read_only=True)

    class Meta:
        model = NotificationRecord
        fields = ['id', 'type', 'title', 'body', 'data', 'isRead', 'createdAt']

    def get_isRead(self, obj):
        return obj.read_at is not None


class AdminCreatePlayerSerializer(serializers.Serializer):
    """Write side of POST /api/admin/players/ — the console's dedicated Add
    Player flow. Unlike accounts.AdminCreateUserSerializer, name fields here
    are genuinely required (no allow_blank): this is the only path that
    creates both the User and its PlayerProfile together. A guardian is required;
    email is optional for guardian-managed players."""

    email = serializers.EmailField(required=False, allow_blank=True)
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(max_length=150)
    middle_initial = serializers.CharField(max_length=5)
    date_of_birth = serializers.DateField()
    guardian_id = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.filter(role=Roles.GUARDIAN),
        required=True,
    )


class AgeTierSettingSerializer(serializers.ModelSerializer):
    """One tier's age band for GET/PUT /api/age-tiers/. The tier value is the
    row's identity — the PUT view matches rows by it, so it is validated but
    never used to create or rename tiers."""

    tier = serializers.ChoiceField(choices=AgeTier.choices)
    minAge = serializers.IntegerField(
        source='min_age', min_value=1, max_value=99
    )
    maxAge = serializers.IntegerField(
        source='max_age', min_value=1, max_value=99
    )

    class Meta:
        model = AgeTierSetting
        fields = ['tier', 'minAge', 'maxAge']

    def validate(self, attrs):
        if attrs['min_age'] > attrs['max_age']:
            raise serializers.ValidationError(
                'min age must not exceed max age.'
            )
        return attrs
