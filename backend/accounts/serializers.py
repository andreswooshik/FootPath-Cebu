from rest_framework import serializers

from .models import GuardianLink, Roles, User

CREATABLE_ROLES = [
    Roles.COACH,
    Roles.PLAYER,
    Roles.SCHOOL_STAFF,
    Roles.GUARDIAN,
]


class UserSerializer(serializers.ModelSerializer):
    role_display = serializers.CharField(
        source='get_role_display', read_only=True
    )

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
            'is_active',
        ]


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
