from rest_framework import serializers
from django.utils.text import slugify

from academy.storage import signed_photo_url

from .models import Club, ClubTypes, GuardianLink, Roles, User

CREATABLE_ROLES = [
    Roles.COACH,
    Roles.SCHOOL_STAFF,
    Roles.GUARDIAN,
]


class UserSerializer(serializers.ModelSerializer):
    role_display = serializers.CharField(
        source='get_role_display', read_only=True
    )
    club_id = serializers.IntegerField(read_only=True)
    club_name = serializers.CharField(source='club.name', read_only=True)
    club_type = serializers.CharField(source='club.club_type', read_only=True)
    photo_url = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id',
            'firebase_uid',
            'email',
            'first_name',
            'last_name',
            'role',
            'role_display',
            'club_id',
            'club_name',
            'club_type',
            'photo_url',
            'is_active',
        ]

    def get_photo_url(self, obj):
        return (
            signed_photo_url(obj.profile_photo_path)
            if obj.profile_photo_path else None
        )


class AdminUpdateUserSerializer(serializers.Serializer):
    """PATCH /api/admin/users/<pk>/ — post-creation lifecycle: switch the role
    or (de)activate. Both optional; an omitted field stays untouched. The
    role/auth-mode rules live in accounts.services.change_role."""

    role = serializers.ChoiceField(
        choices=[Roles.COACH, Roles.SCHOOL_STAFF, Roles.GUARDIAN],
        required=False,
    )
    is_active = serializers.BooleanField(required=False)


class AdminCreateUserSerializer(serializers.Serializer):
    email = serializers.EmailField()
    first_name = serializers.CharField(max_length=150, allow_blank=True)
    last_name = serializers.CharField(max_length=150, allow_blank=True)
    role = serializers.ChoiceField(choices=[(r.value, r.label) for r in CREATABLE_ROLES])
    club_id = serializers.PrimaryKeyRelatedField(
        source='club', queryset=Club.objects.filter(is_active=True)
    )

    def validate(self, attrs):
        if (
            attrs['role'] == Roles.SCHOOL_STAFF
            and not attrs['club'].allows_school_staff
        ):
            raise serializers.ValidationError({
                'role': 'School Staff can be assigned only to a School club.'
            })
        return attrs


class AdminClubSerializer(serializers.ModelSerializer):
    """Super Admin club CRUD using the existing affiliation fields."""

    club_type = serializers.ChoiceField(choices=ClubTypes.choices)

    class Meta:
        model = Club
        fields = [
            'id', 'name', 'slug', 'club_type', 'is_active', 'school_name',
            'head_coach_name', 'coach_license', 'cvfa_membership', 'created_at',
        ]
        read_only_fields = ['slug', 'created_at']

    def validate(self, attrs):
        current_type = (
            self.instance.club_type if self.instance else ClubTypes.INDEPENDENT
        )
        club_type = attrs.get('club_type', current_type)
        school_name = attrs.get(
            'school_name', self.instance.school_name if self.instance else ''
        )
        if club_type == ClubTypes.SCHOOL and not school_name.strip():
            raise serializers.ValidationError({
                'school_name': 'School name is required for a School club.'
            })
        return attrs

    @staticmethod
    def _unique_slug(name, *, instance=None):
        base = slugify(name) or 'club'
        candidate = base
        counter = 2
        queryset = Club.objects.all()
        if instance is not None:
            queryset = queryset.exclude(pk=instance.pk)
        while queryset.filter(slug=candidate).exists():
            candidate = f'{base}-{counter}'
            counter += 1
        return candidate

    def create(self, validated_data):
        club_type = validated_data.pop('club_type')
        validated_data['is_school_affiliated'] = club_type == ClubTypes.SCHOOL
        validated_data['slug'] = self._unique_slug(validated_data['name'])
        if club_type == ClubTypes.INDEPENDENT:
            validated_data['school_name'] = ''
        return super().create(validated_data)

    def update(self, instance, validated_data):
        club_type = validated_data.pop('club_type', instance.club_type)
        validated_data['is_school_affiliated'] = club_type == ClubTypes.SCHOOL
        if 'name' in validated_data and validated_data['name'] != instance.name:
            validated_data['slug'] = self._unique_slug(
                validated_data['name'], instance=instance
            )
        if club_type == ClubTypes.INDEPENDENT:
            validated_data['school_name'] = ''
        return super().update(instance, validated_data)


class AdminCoordinatorCreateSerializer(serializers.Serializer):
    email = serializers.EmailField()
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(max_length=150)
    club_id = serializers.PrimaryKeyRelatedField(
        source='club', queryset=Club.objects.filter(is_active=True)
    )
    password = serializers.CharField(
        required=False, allow_blank=False, min_length=8, write_only=True
    )
    is_active = serializers.BooleanField(default=True)

    def validate_club_id(self, club):
        if User.objects.filter(club=club, role=Roles.COORDINATOR).exists():
            raise serializers.ValidationError('This club already has a coordinator.')
        return club


class GuardianLinkSerializer(serializers.ModelSerializer):
    guardian = UserSerializer(read_only=True)
    player = UserSerializer(read_only=True)
    guardian_id = serializers.PrimaryKeyRelatedField(
        source='guardian',
        queryset=User.objects.filter(role=Roles.GUARDIAN),
        write_only=True,
    )
    player_id = serializers.PrimaryKeyRelatedField(
        source='player',
        queryset=User.objects.filter(role=Roles.PLAYER),
        write_only=True,
    )

    class Meta:
        model = GuardianLink
        fields = ['id', 'guardian', 'player', 'guardian_id', 'player_id', 'created_at']

    def validate(self, attrs):
        guardian = attrs['guardian']
        player = attrs['player']
        if not guardian.is_active or not player.is_active:
            raise serializers.ValidationError(
                'Guardian and player accounts must both be active.'
            )
        if guardian.club_id is None or guardian.club_id != player.club_id:
            raise serializers.ValidationError(
                'Guardian and player must belong to the same club.'
            )
        return attrs
