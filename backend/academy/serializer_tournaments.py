"""Academy serializers extracted from the legacy serializer module."""

from .serializer_players import *  # noqa: F401,F403

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
    category = serializers.ChoiceField(
        choices=MatchCategory.choices,
        required=False,
        default=MatchCategory.OTHER,
    )

    class Meta:
        model = FootballMatch
        fields = [
            'id', 'opponent', 'competition', 'playedOn', 'venue',
            'ourScore', 'opponentScore', 'fixtureId', 'recordSource',
            'ageBracketId', 'ageBracketLabel', 'category',
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
    endsAt = serializers.DateTimeField(
        source='effective_ends_at', read_only=True,
    )
    matchId = serializers.CharField(
        source='completed_match_id', read_only=True, allow_null=True,
    )
    ageBracketId = serializers.CharField(
        source='age_bracket_id', read_only=True, allow_null=True,
    )
    ageBracketLabel = serializers.CharField(
        source='age_bracket.label', read_only=True, allow_null=True,
    )
    result = serializers.SerializerMethodField()

    class Meta:
        model = TournamentFixture
        fields = [
            'id', 'scheduleId', 'tournament', 'stage', 'opponent',
            'kickoffAt', 'endsAt', 'venue', 'location', 'status', 'matchId',
            'ageBracketId', 'ageBracketLabel',
            'result',
        ]

    def get_result(self, obj):
        match = obj.completed_match
        if match is None:
            return None
        return {
            'ourScore': match.our_score,
            'opponentScore': match.opponent_score,
            'outcome': (
                'WIN' if match.our_score > match.opponent_score
                else 'LOSS' if match.our_score < match.opponent_score
                else 'DRAW'
            ),
            'match': FootballMatchSerializer(match).data,
        }


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
    academyTiers = serializers.ListField(
        source='academy_tiers', child=serializers.CharField(), read_only=True,
    )

    class Meta:
        model = TournamentAgeBracket
        fields = [
            'id', 'maxAge', 'label', 'academyTiers', 'scheduledAt', 'squad',
        ]

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
    hasDocument = serializers.SerializerMethodField()
    lifecycleStatus = serializers.CharField(
        source='lifecycle_status', read_only=True,
    )
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
            'id', 'title', 'venue', 'startsOn', 'isPublished', 'documentUrl',
            'hasDocument', 'lifecycleStatus', 'publishedAt', 'updatedAt',
            'ageBrackets', 'fixtures',
        ]

    def get_documentUrl(self, obj):
        return signed_tournament_document_url(obj.document_path)

    def get_hasDocument(self, obj):
        return bool(obj.document_path)


class TournamentScheduleWriteSerializer(serializers.ModelSerializer):
    startsOn = serializers.DateField(source='starts_on')
    venue = serializers.CharField(max_length=160, trim_whitespace=True)

    class Meta:
        model = TournamentSchedule
        fields = ['title', 'venue', 'startsOn']

    def validate_title(self, value):
        cleaned = value.strip()
        if not cleaned:
            raise serializers.ValidationError('Tournament name is required.')
        return cleaned

    def validate_venue(self, value):
        cleaned = value.strip()
        if not cleaned:
            raise serializers.ValidationError('Main venue is required.')
        return cleaned


class TournamentFixtureWriteSerializer(serializers.ModelSerializer):
    ageBracketId = serializers.IntegerField(source='age_bracket_id')
    kickoffAt = serializers.DateTimeField(source='kickoff_at')
    endsAt = serializers.DateTimeField(source='ends_at')
    stage = serializers.CharField(max_length=80, trim_whitespace=True)
    opponent = serializers.CharField(
        max_length=120, trim_whitespace=True, required=False, default='TBD',
    )
    location = serializers.CharField(max_length=160, trim_whitespace=True)

    class Meta:
        model = TournamentFixture
        fields = [
            'ageBracketId', 'stage', 'opponent', 'kickoffAt', 'endsAt', 'venue',
            'location', 'status',
        ]

    def validate_ageBracketId(self, value):
        schedule = self.context['schedule']
        if not TournamentAgeBracket.objects.filter(
            pk=value, schedule=schedule,
        ).exists():
            raise serializers.ValidationError(
                'Select an age bracket from this tournament.'
            )
        return value

    def validate_stage(self, value):
        if not value:
            raise serializers.ValidationError('Stage or round is required.')
        return value

    def validate_opponent(self, value):
        return value or 'TBD'

    def validate_location(self, value):
        if not value:
            raise serializers.ValidationError(
                'Location, pitch, or stadium is required.'
            )
        return value

    def validate_status(self, value):
        if value == FixtureStatus.COMPLETED:
            raise serializers.ValidationError(
                'Use Record Result to complete a fixture.'
            )
        return value

    def validate(self, attrs):
        attrs = super().validate(attrs)
        kickoff = attrs.get(
            'kickoff_at', getattr(self.instance, 'kickoff_at', None),
        )
        ends_at = attrs.get('ends_at', getattr(self.instance, 'ends_at', None))
        if kickoff and ends_at and ends_at <= kickoff:
            raise serializers.ValidationError({
                'endsAt': 'Expected end time must be later than kickoff.'
            })
        return attrs


class TournamentAgeBracketWriteSerializer(serializers.ModelSerializer):
    maxAge = serializers.IntegerField(
        source='max_age', min_value=3, max_value=21,
    )
    scheduledAt = serializers.DateTimeField(
        source='scheduled_at', required=False, allow_null=True,
    )
    academyTiers = serializers.ListField(
        source='academy_tiers',
        child=serializers.ChoiceField(choices=AgeTier.choices),
        required=False,
    )

    class Meta:
        model = TournamentAgeBracket
        fields = ['maxAge', 'academyTiers', 'scheduledAt']

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
        tiers = attrs.get(
            'academy_tiers', getattr(self.instance, 'academy_tiers', None),
        )
        canonical = {
            12: [AgeTier.FOUNDATION],
            15: [AgeTier.DEVELOPMENT],
            18: [AgeTier.PATHWAY],
        }.get(max_age)
        if tiers is None and canonical is not None:
            attrs['academy_tiers'] = canonical
            tiers = canonical
        if not tiers:
            raise serializers.ValidationError({
                'academyTiers': (
                    'Select at least one academy tier for this bracket.'
                )
            })
        attrs['academy_tiers'] = list(dict.fromkeys(tiers))
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

__all__ = [name for name in globals() if not name.startswith('__')]
