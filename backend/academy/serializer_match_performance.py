"""Match-performance and result serializers."""

from .serializer_tournaments import *  # noqa: F401,F403

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


class TournamentResultParticipantWriteSerializer(serializers.Serializer):
    playerId = serializers.IntegerField(min_value=1)
    statistics = PlayerMatchStatisticsWriteSerializer()


class TournamentFixtureResultWriteSerializer(serializers.Serializer):
    ourScore = serializers.IntegerField(min_value=0, max_value=99)
    opponentScore = serializers.IntegerField(min_value=0, max_value=99)
    participants = TournamentResultParticipantWriteSerializer(
        many=True, allow_empty=False,
    )

    def validate_participants(self, value):
        player_ids = [row['playerId'] for row in value]
        if len(player_ids) != len(set(player_ids)):
            raise serializers.ValidationError(
                'A player can participate only once in a fixture result.'
            )
        return value

    def validate(self, attrs):
        attrs = super().validate(attrs)
        total_goals = sum(
            row['statistics'].get('goals', 0)
            for row in attrs['participants']
        )
        if total_goals > attrs['ourScore']:
            raise serializers.ValidationError({
                'participants': 'Recorded player goals exceed the team score.'
            })
        for row in attrs['participants']:
            statistics = row['statistics']
            if statistics.get('goals_conceded', 0) > attrs['opponentScore']:
                raise serializers.ValidationError({
                    'participants': (
                        'A goalkeeper\'s goals conceded cannot exceed the '
                        'opponent score.'
                    )
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
