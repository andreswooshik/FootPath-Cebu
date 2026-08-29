"""Serializers emitting the exact camelCase wire contract the Flutter entities
parse (footpath_cebu/lib/domain/entities/). Field names and casing here are the
API contract — do not rename without changing the client `fromJson` factories.
"""
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from rest_framework import serializers

from accounts.models import Roles, User

from .models import (
    AgeTier,
    AgeTierSetting,
    Attendance,
    AttendanceStatus,
    Dispute,
    DisputeCategory,
    DisputeResponse,
    DisputeStatus,
    Eligibility,
    EligibilityHistory,
    FootballMatch,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    InjuryStatusUpdateRequest,
    InjuryUpdateReviewStatus,
    MatchVenue,
    NotificationRecord,
    PLAYER_POSITION_CODES,
    PlayerMatchPerformance,
    PlayerProfile,
    SessionConfirmation,
    SessionFocus,
    TrainingSession,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
)
from .tournament_rosters import roster_eligibility
from .storage import signed_photo_url, signed_tournament_document_url


def _display_name(user):
    """A user's readable name: 'First Last', falling back to the email stem."""
    if user is None:
        return None
    full = f'{user.first_name} {user.last_name}'.strip()
    return full or user.email.split('@')[0] or f'Player {user.id}'


class PlayerSerializer(serializers.ModelSerializer):
    """Matches Player.fromJson: id, name, age, classYear, ageTier, position,
    ratings{...}, eligibility, photoUrl."""

    # Player id == the underlying User id, so /api/attendance/?player=<id> and
    # GuardianLink (guardian->player user) all key off the same value.
    id = serializers.CharField(source='user.id', read_only=True)
    name = serializers.SerializerMethodField()
    classYear = serializers.CharField(source='class_year')
    ageTier = serializers.CharField(source='age_tier')
    ratings = serializers.SerializerMethodField()
    photoUrl = serializers.SerializerMethodField()
    coachNotes = serializers.CharField(source='coach_notes', read_only=True)
    academicEligibilityApplicable = serializers.SerializerMethodField()

    class Meta:
        model = PlayerProfile
        fields = [
            'id', 'name', 'age', 'classYear', 'ageTier', 'position',
            'ratings', 'eligibility', 'academicEligibilityApplicable',
            'photoUrl', 'coachNotes',
        ]

    def get_name(self, obj):
        full = f'{obj.user.first_name} {obj.user.last_name}'.strip()
        return full or obj.user.email.split('@')[0] or f'Player {obj.user_id}'

    def get_ratings(self, obj):
        return {
            'pace': obj.pace,
            'shooting': obj.shooting,
            'passing': obj.passing,
            'dribbling': obj.dribbling,
            'defending': obj.defending,
            'physical': obj.physical,
            'diving': obj.diving,
            'handling': obj.handling,
            'kicking': obj.kicking,
            'reflexes': obj.reflexes,
            'speed': obj.speed,
            'positioning': obj.positioning,
        }

    def get_photoUrl(self, obj):
        return signed_photo_url(obj.photo_path) if obj.photo_path else None

    def get_academicEligibilityApplicable(self, obj):
        club = obj.user.club
        return club is None or club.allows_academic_eligibility


class PlayerSelectorSerializer(serializers.ModelSerializer):
    """Non-sensitive player shape used before a household PIN is entered."""

    id = serializers.CharField(source='user.id', read_only=True)
    name = serializers.SerializerMethodField()
    ageTier = serializers.CharField(source='age_tier', read_only=True)

    class Meta:
        model = PlayerProfile
        fields = ['id', 'name', 'ageTier']

    def get_name(self, obj):
        return _display_name(obj.user)


class AssessmentSerializer(serializers.ModelSerializer):
    """Write side for PUT /api/players/<id>/assessment/ — the twelve
    coach-editable ratings (outfield six + goalkeeper six) plus the coach's
    qualitative note. Accepts the nested `ratings` object the client sends.
    The view saves with partial=True, so a client that posts only the outfield
    six leaves the stored GK values untouched rather than zeroing them."""

    pace = serializers.IntegerField(min_value=0, max_value=99)
    shooting = serializers.IntegerField(min_value=0, max_value=99)
    passing = serializers.IntegerField(min_value=0, max_value=99)
    dribbling = serializers.IntegerField(min_value=0, max_value=99)
    defending = serializers.IntegerField(min_value=0, max_value=99)
    physical = serializers.IntegerField(min_value=0, max_value=99)
    diving = serializers.IntegerField(min_value=0, max_value=99)
    handling = serializers.IntegerField(min_value=0, max_value=99)
    kicking = serializers.IntegerField(min_value=0, max_value=99)
    reflexes = serializers.IntegerField(min_value=0, max_value=99)
    speed = serializers.IntegerField(min_value=0, max_value=99)
    positioning = serializers.IntegerField(min_value=0, max_value=99)
    # Optional so an older client that posts only ratings still succeeds; when
    # omitted the existing note is left untouched rather than blanked.
    coachNotes = serializers.CharField(
        source='coach_notes', required=False, allow_blank=True, max_length=2000,
    )

    class Meta:
        model = PlayerProfile
        fields = [
            'pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical',
            'diving', 'handling', 'kicking', 'reflexes', 'speed', 'positioning',
            'coachNotes',
        ]

    def to_internal_value(self, data):
        # The client posts {"ratings": {pace: .., ...}, "coachNotes": ".."};
        # flatten that into the shape the field declarations expect, while still
        # accepting an already-flat body so the endpoint stays forgiving.
        if 'ratings' in data and isinstance(data['ratings'], dict):
            flattened = dict(data['ratings'])
            # Carry the sibling note across — flattening to `ratings` alone is
            # exactly how the note used to get dropped.
            if 'coachNotes' in data:
                flattened['coachNotes'] = data['coachNotes']
            data = flattened
        return super().to_internal_value(data)


class PlayerPositionSerializer(serializers.ModelSerializer):
    """Write side for PUT /api/players/<id>/position/ — the coach assigns or
    changes a player's position. Matches the ten codes PlayerPositionInfo.wire
    emits on the client (GK/CB/LB/RB/CDM/CM/CAM/LW/RW/ST)."""

    class Meta:
        model = PlayerProfile
        fields = ['position']

    def validate_position(self, value):
        v = str(value).upper()
        if v not in PLAYER_POSITION_CODES:
            raise serializers.ValidationError(f'Unknown position: {value}')
        return v


class FootballMatchSerializer(serializers.ModelSerializer):
    """Read/write contract for a completed club match.

    Club and creator are intentionally absent from writable fields; views stamp
    both from the authenticated Coordinator so a request cannot cross tenant bounds.
    """

    id = serializers.CharField(read_only=True)
    playedOn = serializers.DateField(source='played_on')
    ourScore = serializers.IntegerField(
        source='our_score', min_value=0, max_value=99,
    )
    opponentScore = serializers.IntegerField(
        source='opponent_score', min_value=0, max_value=99,
    )
    fixtureId = serializers.SerializerMethodField()
    recordSource = serializers.SerializerMethodField()
    ageBracketId = serializers.SerializerMethodField()
    ageBracketLabel = serializers.SerializerMethodField()

    class Meta:
        model = FootballMatch
        fields = [
            'id', 'opponent', 'competition', 'playedOn', 'venue',
            'ourScore', 'opponentScore', 'fixtureId', 'recordSource',
            'ageBracketId', 'ageBracketLabel',
        ]

    def validate_opponent(self, value):
        cleaned = value.strip()
        if not cleaned:
            raise serializers.ValidationError('Opponent is required.')
        return cleaned

    def validate_competition(self, value):
        return value.strip()

    def validate_playedOn(self, value):
        if value > timezone.localdate():
            raise serializers.ValidationError(
                'Match statistics can only be recorded after play.'
            )
        return value

    def validate_venue(self, value):
        cleaned = str(value).upper()
        if cleaned not in set(MatchVenue.values):
            raise serializers.ValidationError(f'Unknown venue: {value}')
        return cleaned

    def get_fixtureId(self, obj):
        try:
            return str(obj.source_fixture.id)
        except TournamentFixture.DoesNotExist:
            return None

    def get_recordSource(self, obj):
        return 'SCHEDULED' if self.get_fixtureId(obj) is not None else 'AD_HOC'

    def get_ageBracketId(self, obj):
        try:
            bracket_id = obj.source_fixture.age_bracket_id
        except TournamentFixture.DoesNotExist:
            return None
        return str(bracket_id) if bracket_id is not None else None

    def get_ageBracketLabel(self, obj):
        try:
            bracket = obj.source_fixture.age_bracket
        except TournamentFixture.DoesNotExist:
            return None
        return bracket.label if bracket is not None else None


class TournamentFixtureSerializer(serializers.ModelSerializer):
    scheduleId = serializers.CharField(source='schedule_id', read_only=True)
    tournament = serializers.CharField(source='schedule.title', read_only=True)
    kickoffAt = serializers.DateTimeField(source='kickoff_at', read_only=True)
    matchId = serializers.CharField(
        source='completed_match_id', read_only=True, allow_null=True,
    )
    ageBracketId = serializers.CharField(
        source='age_bracket_id', read_only=True, allow_null=True,
    )
    ageBracketLabel = serializers.CharField(
        source='age_bracket.label', read_only=True, allow_null=True,
    )

    class Meta:
        model = TournamentFixture
        fields = [
            'id', 'scheduleId', 'tournament', 'stage', 'opponent',
            'kickoffAt', 'venue', 'location', 'status', 'matchId',
            'ageBracketId', 'ageBracketLabel',
        ]


class TournamentSquadEntrySerializer(serializers.ModelSerializer):
    playerId = serializers.CharField(source='player_id', read_only=True)
    playerName = serializers.SerializerMethodField()
    tournamentPosition = serializers.CharField(source='position', read_only=True)
    availability = serializers.SerializerMethodField()
    availabilityReason = serializers.SerializerMethodField()

    class Meta:
        model = TournamentSquadEntry
        fields = [
            'id', 'playerId', 'playerName', 'tournamentPosition',
            'availability', 'availabilityReason',
        ]

    def get_playerName(self, obj):
        return _display_name(obj.player)

    def _eligibility(self, obj):
        return roster_eligibility(obj.player, obj.squad.bracket)

    def get_availability(self, obj):
        return self._eligibility(obj).state

    def get_availabilityReason(self, obj):
        return self._eligibility(obj).reason

    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get('request')
        role = getattr(getattr(request, 'user', None), 'role', None)
        if role not in (Roles.COACH, Roles.COORDINATOR, Roles.ADMIN):
            data.pop('availability', None)
            data.pop('availabilityReason', None)
        return data


class TournamentSquadSerializer(serializers.ModelSerializer):
    bracketId = serializers.CharField(source='bracket_id', read_only=True)
    publishedAt = serializers.DateTimeField(
        source='published_at', read_only=True, allow_null=True,
    )
    entries = TournamentSquadEntrySerializer(many=True, read_only=True)

    class Meta:
        model = TournamentSquad
        fields = ['id', 'bracketId', 'status', 'publishedAt', 'entries']


class TournamentAgeBracketSerializer(serializers.ModelSerializer):
    maxAge = serializers.IntegerField(source='max_age', read_only=True)
    scheduledAt = serializers.DateTimeField(
        source='scheduled_at', read_only=True, allow_null=True,
    )
    label = serializers.CharField(read_only=True)
    squad = serializers.SerializerMethodField()

    class Meta:
        model = TournamentAgeBracket
        fields = ['id', 'maxAge', 'label', 'scheduledAt', 'squad']

    def get_squad(self, obj):
        try:
            squad = obj.squad
        except TournamentSquad.DoesNotExist:
            return None
        request = self.context.get('request')
        role = getattr(getattr(request, 'user', None), 'role', None)
        manager = role in (Roles.COACH, Roles.COORDINATOR, Roles.ADMIN)
        if squad.status != TournamentSquadStatus.PUBLISHED and not manager:
            return None
        return TournamentSquadSerializer(squad, context=self.context).data


class TournamentScheduleSerializer(serializers.ModelSerializer):
    documentUrl = serializers.SerializerMethodField()
    startsOn = serializers.DateField(source='starts_on', read_only=True)
    isPublished = serializers.BooleanField(source='is_published', read_only=True)
    publishedAt = serializers.DateTimeField(
        source='published_at', read_only=True, allow_null=True,
    )
    updatedAt = serializers.DateTimeField(source='updated_at', read_only=True)
    fixtures = TournamentFixtureSerializer(many=True, read_only=True)
    ageBrackets = TournamentAgeBracketSerializer(
        source='age_brackets', many=True, read_only=True,
    )

    class Meta:
        model = TournamentSchedule
        fields = [
            'id', 'title', 'startsOn', 'isPublished', 'documentUrl',
            'publishedAt', 'updatedAt', 'ageBrackets', 'fixtures',
        ]

    def get_documentUrl(self, obj):
        return signed_tournament_document_url(obj.document_path)


class TournamentScheduleWriteSerializer(serializers.ModelSerializer):
    startsOn = serializers.DateField(source='starts_on')

    class Meta:
        model = TournamentSchedule
        fields = ['title', 'startsOn']


class TournamentAgeBracketWriteSerializer(serializers.ModelSerializer):
    maxAge = serializers.IntegerField(
        source='max_age', min_value=3, max_value=25,
    )
    scheduledAt = serializers.DateTimeField(
        source='scheduled_at', required=False, allow_null=True,
    )

    class Meta:
        model = TournamentAgeBracket
        fields = ['maxAge', 'scheduledAt']

    def validate(self, attrs):
        schedule = self.context['schedule']
        max_age = attrs.get('max_age', getattr(self.instance, 'max_age', None))
        duplicates = TournamentAgeBracket.objects.filter(
            schedule=schedule, max_age=max_age,
        )
        if self.instance is not None:
            duplicates = duplicates.exclude(pk=self.instance.pk)
        if duplicates.exists():
            raise serializers.ValidationError({
                'maxAge': f'{schedule.title} already has a U{max_age} bracket.'
            })
        return attrs


class TournamentSquadEntryWriteSerializer(serializers.Serializer):
    playerId = serializers.IntegerField(min_value=1)
    position = serializers.CharField(
        required=False, allow_blank=True, max_length=8,
    )

    def validate_position(self, value):
        cleaned = value.strip().upper()
        if cleaned and cleaned not in PLAYER_POSITION_CODES:
            raise serializers.ValidationError('Unknown player position.')
        return cleaned


class TournamentSquadWriteSerializer(serializers.Serializer):
    entries = TournamentSquadEntryWriteSerializer(many=True)

    def validate_entries(self, value):
        player_ids = [row['playerId'] for row in value]
        if len(player_ids) != len(set(player_ids)):
            raise serializers.ValidationError(
                'A player can appear only once in an age-bracket roster.'
            )
        return value


class PlayerMatchPerformanceSerializer(serializers.ModelSerializer):
    """Read contract for one player's statistics in one match."""

    id = serializers.CharField(read_only=True)
    playerId = serializers.CharField(source='player.id', read_only=True)
    playerName = serializers.SerializerMethodField()
    match = FootballMatchSerializer(read_only=True)
    minutesPlayed = serializers.IntegerField(source='minutes_played')
    shotsOnTarget = serializers.IntegerField(source='shots_on_target')
    passesAttempted = serializers.IntegerField(source='passes_attempted')
    passesCompleted = serializers.IntegerField(source='passes_completed')
    yellowCards = serializers.IntegerField(source='yellow_cards')
    redCards = serializers.IntegerField(source='red_cards')
    goalsConceded = serializers.IntegerField(source='goals_conceded')
    cleanSheet = serializers.BooleanField(source='clean_sheet')
    coachRating = serializers.DecimalField(
        source='coach_rating', max_digits=3, decimal_places=1,
        coerce_to_string=False, allow_null=True,
    )
    ratingStatus = serializers.SerializerMethodField()
    squadException = serializers.SerializerMethodField()
    squadOverrideReason = serializers.CharField(
        source='squad_override_reason', read_only=True,
    )
    squadOverrideAt = serializers.DateTimeField(
        source='squad_override_at', read_only=True, allow_null=True,
    )

    class Meta:
        model = PlayerMatchPerformance
        fields = [
            'id', 'playerId', 'playerName', 'match', 'position', 'starter',
            'minutesPlayed', 'goals', 'assists', 'shots', 'shotsOnTarget',
            'passesAttempted', 'passesCompleted', 'tackles', 'interceptions',
            'yellowCards', 'redCards', 'saves', 'goalsConceded', 'cleanSheet',
            'coachRating', 'notes', 'ratingStatus',
            'squadException', 'squadOverrideReason', 'squadOverrideAt',
        ]

    def get_playerName(self, obj):
        return _display_name(obj.player)

    def get_ratingStatus(self, obj):
        return 'RATED' if obj.coach_rating is not None else 'AWAITING_RATING'

    def get_squadException(self, obj):
        return bool(obj.squad_override_reason)

    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get('request')
        role = getattr(getattr(request, 'user', None), 'role', None)
        if role == Roles.COORDINATOR:
            data.pop('coachRating', None)
            data.pop('notes', None)
        if role not in (Roles.COORDINATOR, Roles.ADMIN):
            data.pop('squadOverrideReason', None)
            data.pop('squadOverrideAt', None)
        return data


class PlayerMatchStatisticsWriteSerializer(serializers.ModelSerializer):
    """Coordinator-owned objective statistics; match/player come from the URL."""

    minutesPlayed = serializers.IntegerField(
        source='minutes_played', min_value=0, max_value=180,
    )
    shotsOnTarget = serializers.IntegerField(
        source='shots_on_target', min_value=0,
    )
    passesAttempted = serializers.IntegerField(
        source='passes_attempted', min_value=0,
    )
    passesCompleted = serializers.IntegerField(
        source='passes_completed', min_value=0,
    )
    yellowCards = serializers.IntegerField(
        source='yellow_cards', min_value=0, max_value=2,
    )
    redCards = serializers.IntegerField(
        source='red_cards', min_value=0, max_value=1,
    )
    goalsConceded = serializers.IntegerField(
        source='goals_conceded', min_value=0,
    )
    cleanSheet = serializers.BooleanField(source='clean_sheet')
    class Meta:
        model = PlayerMatchPerformance
        fields = [
            'position', 'starter', 'minutesPlayed', 'goals', 'assists',
            'shots', 'shotsOnTarget', 'passesAttempted', 'passesCompleted',
            'tackles', 'interceptions', 'yellowCards', 'redCards', 'saves',
            'goalsConceded', 'cleanSheet',
        ]
        extra_kwargs = {
            'position': {'allow_blank': True, 'required': False},
            'goals': {'min_value': 0},
            'assists': {'min_value': 0},
            'shots': {'min_value': 0},
            'tackles': {'min_value': 0},
            'interceptions': {'min_value': 0},
            'saves': {'min_value': 0},
        }

    def validate_position(self, value):
        cleaned = str(value).strip().upper()
        if cleaned and cleaned not in PLAYER_POSITION_CODES:
            raise serializers.ValidationError(f'Unknown position: {value}')
        return cleaned

    def validate(self, attrs):
        attrs = super().validate(attrs)

        def current(field, default=0):
            if field in attrs:
                return attrs[field]
            if self.instance is not None:
                return getattr(self.instance, field)
            return default

        if current('shots_on_target') > current('shots'):
            raise serializers.ValidationError({
                'shotsOnTarget': 'Shots on target cannot exceed total shots.'
            })
        if current('goals') > current('shots_on_target'):
            raise serializers.ValidationError({
                'goals': 'Goals cannot exceed shots on target.'
            })
        if current('passes_completed') > current('passes_attempted'):
            raise serializers.ValidationError({
                'passesCompleted': (
                    'Completed passes cannot exceed attempted passes.'
                )
            })
        if current('clean_sheet', False) and current('goals_conceded'):
            raise serializers.ValidationError({
                'cleanSheet': 'A clean sheet cannot include goals conceded.'
            })
        position = current('position', '')
        if position != 'GK' and (
            current('saves')
            or current('goals_conceded')
            or current('clean_sheet', False)
        ):
            raise serializers.ValidationError({
                'position': 'Goalkeeper statistics require the GK position.'
            })
        return attrs


class CoachMatchRatingSerializer(serializers.ModelSerializer):
    """Coach-owned subjective evaluation for existing objective statistics."""

    coachRating = serializers.DecimalField(
        source='coach_rating',
        max_digits=3,
        decimal_places=1,
        min_value=0,
        max_value=10,
        coerce_to_string=False,
    )

    class Meta:
        model = PlayerMatchPerformance
        fields = ['coachRating', 'notes']
        extra_kwargs = {
            'notes': {'allow_blank': True, 'required': False, 'max_length': 1000},
        }


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

    class Meta:
        model = TrainingSession
        fields = [
            'id', 'title', 'ageTiers', 'date', 'startTime', 'endTime',
            'location', 'focus', 'attendeeCount',
        ]

    def get_attendeeCount(self, obj):
        # The list view annotates this value, avoiding one query per session.
        return getattr(obj, 'present_attendee_count', 0)

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

    class Meta:
        model = Attendance
        fields = [
            'playerId', 'sessionId', 'status', 'effort', 'note',
            'updatedAt', 'sessionName', 'coachUid',
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
