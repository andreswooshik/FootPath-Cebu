"""Serializers emitting the exact camelCase wire contract the Flutter entities
parse (footpath_cebu/lib/domain/entities/). Field names and casing here are the
API contract — do not rename without changing the client `fromJson` factories.
"""
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from rest_framework import serializers

from accounts.models import Roles, User

from .assessment_framework import (
    AssessmentFrameworkError,
    domain_scores,
    validate_scores,
)
from .models import (
    AgeTier,
    AgeTierSetting,
    AssessmentReason,
    Attendance,
    AttendanceStatus,
    Dispute,
    DisputeCategory,
    DisputeResponse,
    DisputeStatus,
    Eligibility,
    EligibilityHistory,
    FixtureStatus,
    FootballMatch,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    InjuryStatusUpdateRequest,
    InjuryUpdateReviewStatus,
    MatchCategory,
    MatchVenue,
    NotificationRecord,
    PLAYER_POSITION_CODES,
    PlayerMatchPerformance,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerStatsAssessment,
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
from .player_stats import catalog_for, normalized_scores, overall
from .tournament_rosters import roster_eligibility
from .storage import (
    signed_photo_url,
    signed_tournament_document_url,
)


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
    developmentAssessment = serializers.SerializerMethodField()

    class Meta:
        model = PlayerProfile
        fields = [
            'id', 'name', 'age', 'classYear', 'ageTier', 'position',
            'ratings', 'eligibility', 'academicEligibilityApplicable',
            'photoUrl', 'coachNotes', 'developmentAssessment',
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

    def get_developmentAssessment(self, obj):
        if (
            obj.development_framework_version is None
            or not obj.development_scores
        ):
            return None
        return {
            'frameworkVersion': obj.development_framework_version,
            'ratings': obj.development_scores,
            'domainScores': domain_scores(obj.development_scores),
            'strengths': obj.development_strengths,
            'developmentTargets': obj.development_targets,
            'assessedAt': serializers.DateTimeField().to_representation(
                obj.development_assessed_at
            ),
        }


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
    assessmentReason = serializers.ChoiceField(
        choices=AssessmentReason.choices,
        required=False,
        write_only=True,
    )

    class Meta:
        model = PlayerProfile
        fields = [
            'pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical',
            'diving', 'handling', 'kicking', 'reflexes', 'speed', 'positioning',
            'coachNotes',
            'assessmentReason',
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
            if 'assessmentReason' in data:
                flattened['assessmentReason'] = data['assessmentReason']
            data = flattened
        return super().to_internal_value(data)

    def update(self, instance, validated_data):
        validated_data.pop('assessmentReason', None)
        return super().update(instance, validated_data)


class PlayerAssessmentSnapshotSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    playerId = serializers.CharField(source='player_id', read_only=True)
    assessedByRole = serializers.SerializerMethodField()
    coachNotes = serializers.CharField(source='coach_notes', read_only=True)
    assessmentReason = serializers.CharField(source='reason', read_only=True)
    createdAt = serializers.DateTimeField(source='created_at', read_only=True)
    ratings = serializers.SerializerMethodField()
    overall = serializers.SerializerMethodField()

    class Meta:
        model = PlayerAssessmentSnapshot
        fields = [
            'id', 'playerId', 'assessedByRole', 'position', 'ratings',
            'overall', 'coachNotes', 'assessmentReason', 'createdAt',
        ]

    def get_assessedByRole(self, obj):
        return obj.assessed_by.get_role_display() if obj.assessed_by_id else None

    def get_ratings(self, obj):
        return {
            field: getattr(obj, field)
            for field in (
                'pace', 'shooting', 'passing', 'dribbling', 'defending',
                'physical', 'diving', 'handling', 'kicking', 'reflexes',
                'speed', 'positioning',
            )
        }

    def get_overall(self, obj):
        names = (
            ('diving', 'handling', 'kicking', 'reflexes', 'speed', 'positioning')
            if obj.position == 'GK'
            else ('pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical')
        )
        return round(sum(getattr(obj, name) for name in names) / len(names))


class DevelopmentAssessmentWriteSerializer(serializers.Serializer):
    frameworkVersion = serializers.IntegerField(min_value=1)
    developmentRatings = serializers.JSONField()
    strengths = serializers.CharField(max_length=1000, allow_blank=False)
    developmentTargets = serializers.CharField(max_length=1000, allow_blank=False)
    coachNotes = serializers.CharField(
        required=False,
        allow_blank=True,
        max_length=2000,
    )
    assessmentReason = serializers.ChoiceField(
        choices=AssessmentReason.choices,
    )

    def validate(self, attrs):
        if attrs['assessmentReason'] == AssessmentReason.BASELINE:
            raise serializers.ValidationError({
                'assessmentReason': 'Baseline is reserved for migrated legacy records.',
            })
        profile = self.context['profile']
        try:
            attrs['developmentRatings'] = validate_scores(
                attrs['developmentRatings'],
                age_tier=profile.age_tier,
                position=profile.position,
                version=attrs['frameworkVersion'],
            )
        except AssessmentFrameworkError as error:
            raise serializers.ValidationError(error.errors) from error
        return attrs


class PlayerDevelopmentAssessmentSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    playerId = serializers.CharField(source='player_id', read_only=True)
    assessedByRole = serializers.SerializerMethodField()
    ageTier = serializers.CharField(source='age_tier', read_only=True)
    ageAtAssessment = serializers.IntegerField(
        source='age_at_assessment',
        read_only=True,
    )
    frameworkVersion = serializers.IntegerField(
        source='framework_version',
        read_only=True,
    )
    ratings = serializers.JSONField(source='scores', read_only=True)
    domainScores = serializers.SerializerMethodField()
    developmentTargets = serializers.CharField(
        source='development_targets',
        read_only=True,
    )
    coachNotes = serializers.CharField(source='coach_notes', read_only=True)
    assessmentReason = serializers.CharField(source='reason', read_only=True)
    createdAt = serializers.DateTimeField(source='created_at', read_only=True)

    class Meta:
        model = PlayerDevelopmentAssessment
        fields = [
            'id', 'playerId', 'assessedByRole', 'position', 'ageTier',
            'ageAtAssessment', 'frameworkVersion', 'ratings', 'domainScores',
            'strengths', 'developmentTargets', 'coachNotes',
            'assessmentReason', 'createdAt',
        ]

    def get_assessedByRole(self, obj):
        return obj.assessed_by.get_role_display() if obj.assessed_by_id else None

    def get_domainScores(self, obj):
        return domain_scores(obj.scores)


class PlayerStatsAssessmentWriteSerializer(serializers.Serializer):
    """The client submits only raw inputs; all comparisons are server-owned."""
    catalogVersion = serializers.IntegerField(min_value=1)
    scores = serializers.JSONField()
    reason = serializers.CharField(min_length=1, max_length=100)
    coachNotes = serializers.CharField(min_length=1, max_length=4000)

    def validate(self, attrs):
        attrs['reason'] = attrs['reason'].strip()
        attrs['coachNotes'] = attrs['coachNotes'].strip()
        if not attrs['reason']:
            raise serializers.ValidationError({'reason': 'Choose an assessment reason.'})
        if not attrs['coachNotes']:
            raise serializers.ValidationError({'coachNotes': 'Coach notes are required.'})
        profile = self.context['profile']
        try:
            catalog_for(profile.position, attrs['catalogVersion'])
            attrs['scores'] = normalized_scores(
                profile.position, attrs['scores'], attrs['catalogVersion']
            )
        except DjangoValidationError as error:
            raise serializers.ValidationError(error.message_dict) from error
        return attrs


class PlayerStatsAssessmentSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    playerId = serializers.CharField(source='player_id', read_only=True)
    assessedBy = serializers.SerializerMethodField()
    roleGroup = serializers.CharField(source='role_group', read_only=True)
    catalogVersion = serializers.IntegerField(source='catalog_version', read_only=True)
    coachNotes = serializers.CharField(source='coach_notes', read_only=True)
    createdAt = serializers.DateTimeField(source='created_at', read_only=True)

    class Meta:
        model = PlayerStatsAssessment
        fields = ['id', 'playerId', 'assessedBy', 'position', 'roleGroup',
                  'catalogVersion', 'scores', 'overall', 'reason', 'coachNotes', 'createdAt']

    def get_assessedBy(self, obj):
        if not obj.assessed_by_id:
            return None
        return obj.assessed_by.get_full_name() or obj.assessed_by.email


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



__all__ = [name for name in globals() if not name.startswith('__')]
