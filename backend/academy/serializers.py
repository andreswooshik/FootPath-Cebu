"""Serializers emitting the exact camelCase wire contract the Flutter entities
parse (footpath_cebu/lib/domain/entities/). Field names and casing here are the
API contract — do not rename without changing the client `fromJson` factories.
"""
from rest_framework import serializers

from .models import (
    AgeTier,
    Attendance,
    Eligibility,
    PlayerProfile,
    SessionFocus,
    TrainingSession,
)
from .storage import signed_photo_url


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

    class Meta:
        model = PlayerProfile
        fields = [
            'id', 'name', 'age', 'classYear', 'ageTier', 'position',
            'ratings', 'eligibility', 'photoUrl',
        ]

    def get_name(self, obj):
        full = f'{obj.user.first_name} {obj.user.last_name}'.strip()
        return full or obj.user.email.split('@')[0]

    def get_ratings(self, obj):
        return {
            'pace': obj.pace,
            'shooting': obj.shooting,
            'passing': obj.passing,
            'dribbling': obj.dribbling,
            'defending': obj.defending,
            'physical': obj.physical,
        }

    def get_photoUrl(self, obj):
        return signed_photo_url(obj.photo_path) if obj.photo_path else None


class AssessmentSerializer(serializers.ModelSerializer):
    """Write side for PUT /api/players/<id>/assessment/ — the six coach-editable
    ratings. Accepts the nested `ratings` object the client sends."""

    pace = serializers.IntegerField(min_value=0, max_value=99)
    shooting = serializers.IntegerField(min_value=0, max_value=99)
    passing = serializers.IntegerField(min_value=0, max_value=99)
    dribbling = serializers.IntegerField(min_value=0, max_value=99)
    defending = serializers.IntegerField(min_value=0, max_value=99)
    physical = serializers.IntegerField(min_value=0, max_value=99)

    class Meta:
        model = PlayerProfile
        fields = ['pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical']

    def to_internal_value(self, data):
        # The client posts {"ratings": {pace: .., ...}}; accept that shape as
        # well as a flat body, so the endpoint is forgiving.
        if 'ratings' in data and isinstance(data['ratings'], dict):
            data = data['ratings']
        return super().to_internal_value(data)


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
        # Present count for this session; 0 when none recorded yet.
        return obj.attendance_records.filter(status='PRESENT').count()

    def validate_ageTiers(self, value):
        valid = set(AgeTier.values)
        cleaned = [t.upper() for t in value]
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


class AttendanceSerializer(serializers.ModelSerializer):
    """Matches Attendance.fromJson: playerId, status, updatedAt, sessionName,
    coachUid."""

    # Hard-cast to String on the client, so coerce the int PK to a string here.
    playerId = serializers.CharField(source='player.id', read_only=True)
    updatedAt = serializers.DateTimeField(source='updated_at', read_only=True)
    sessionName = serializers.SerializerMethodField()
    coachUid = serializers.SerializerMethodField()

    class Meta:
        model = Attendance
        fields = ['playerId', 'status', 'updatedAt', 'sessionName', 'coachUid']

    def get_sessionName(self, obj):
        return obj.session.title if obj.session_id else None

    def get_coachUid(self, obj):
        return obj.recorded_by.firebase_uid if obj.recorded_by_id else None
