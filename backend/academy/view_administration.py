"""Domain-focused API views extracted from the legacy view module."""

from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.exceptions import (
    PermissionDenied,
    ValidationError,
)
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academy.model_operations import AuditLog
from academy.model_players import (
    AgeTierSetting,
    PlayerProfile,
)
from academy.serializer_players import PlayerSerializer
from academy.serializer_workflows import (
    AdminCreatePlayerSerializer,
    AgeTierSettingSerializer,
)
from academy.storage import (
    delete_photo,
    invalidate_signed_photo_url,
    sanitized_photo_bytes,
    upload_photo,
    validate_photo_upload,
)
from accounts.models import Roles
from accounts.permissions import IsAdmin
from accounts.serializers import UserSerializer
from accounts.services import (
    ProvisioningError,
    provision_player,
)


class PlayerPhotoUploadView(APIView):
    """Upload a player photo as self, Super Admin, or a same-Club Coach."""

    permission_classes = [IsAuthenticated]
    throttle_scope = 'uploads'

    def post(self, request, player_id):
        profile = get_object_or_404(
            PlayerProfile.objects.select_related('user'),
            user_id=player_id,
        )
        if request.user.role == Roles.PLAYER:
            if request.user.pk != player_id:
                raise PermissionDenied('Players can update only their own photo.')
        elif request.user.role == Roles.COACH:
            if request.user.club_id is None or profile.user.club_id != request.user.club_id:
                raise PermissionDenied('That player is not in your club.')
        elif request.user.role != Roles.ADMIN:
            raise PermissionDenied(
                'Only the Player, a same-Club Coach, or the Super Admin can upload photos.'
            )
        upload = request.FILES.get('photo')
        if upload is None:
            raise ValidationError('A photo file is required (field "photo").')
        try:
            content_type = validate_photo_upload(upload)
            path = upload_photo(
                player_id,
                sanitized_photo_bytes(upload, content_type),
                content_type=content_type,
            )
        except (RuntimeError, ValueError) as exc:
            raise ValidationError(str(exc))
        previous_path = profile.photo_path
        profile.photo_path = path
        profile.save(update_fields=['photo_path'])
        invalidate_signed_photo_url(previous_path)
        invalidate_signed_photo_url(path)
        if previous_path and previous_path != path:
            delete_photo(previous_path)
        AuditLog.record(
            request.user,
            'player.photo_updated',
            target=profile.user.email,
        )
        return Response(PlayerSerializer(profile).data)


class AgeTierSettingsView(APIView):
    """GET/PUT /api/age-tiers/ — the Admin-configurable age band per tier.

    Reads are open to every signed-in role (the bands are academy-wide facts,
    not sensitive). Writes are Admin-only and touch boundaries, never the set
    of tiers: the three tier names are a wire contract with the client.
    Changing a band only affects how FUTURE players are placed — existing
    players keep their stored tier (see PlayerProfile).
    """

    def get(self, request):
        return Response(
            AgeTierSettingSerializer(AgeTierSetting.objects.order_by('min_age'), many=True).data
        )

    def put(self, request):
        if request.user.role != Roles.ADMIN:
            raise PermissionDenied('Only an Admin can configure age tiers.')
        serializer = AgeTierSettingSerializer(data=request.data, many=True)
        serializer.is_valid(raise_exception=True)
        bands = serializer.validated_data
        if not bands:
            raise ValidationError('Provide at least one age tier.')
        submitted_tiers = [band['tier'] for band in bands]
        if len(submitted_tiers) != len(set(submitted_tiers)):
            raise ValidationError('Each age tier may be submitted only once.')

        # Overlapping bands would make tier_for_age order-dependent — reject
        # them here rather than silently picking whichever band sorts first.
        with transaction.atomic():
            stored = {
                setting.tier: setting
                for setting in AgeTierSetting.objects.select_for_update().order_by('tier')
            }
            unknown = sorted(set(submitted_tiers) - set(stored))
            if unknown:
                raise ValidationError(f'Unknown tier(s): {unknown}')

            proposed = {
                tier: {
                    'tier': tier,
                    'min_age': setting.min_age,
                    'max_age': setting.max_age,
                }
                for tier, setting in stored.items()
            }
            for band in bands:
                proposed[band['tier']] = band

            by_min = sorted(proposed.values(), key=lambda band: band['min_age'])
            for previous, current in zip(by_min, by_min[1:]):
                if current['min_age'] <= previous['max_age']:
                    raise ValidationError('Tier age ranges may not overlap.')

            changed = []
            for band in bands:
                setting = stored[band['tier']]
                setting.min_age = band['min_age']
                setting.max_age = band['max_age']
                changed.append(setting)
            AgeTierSetting.objects.bulk_update(changed, ['min_age', 'max_age'])
        return self.get(request)


class AdminCreatePlayerView(APIView):
    """POST /api/admin/players/ — the console's dedicated Add Player flow.

    Unlike the generic /api/admin/users/ endpoint, this creates the User AND
    its PlayerProfile (with the required identity fields) in one atomic call,
    and optionally links a guardian in the same step — this is now the only
    way a player account comes into existence (the admin-site "Player
    profiles" screen is hidden; see academy/admin.py).
    """

    permission_classes = [IsAdmin]

    def post(self, request):
        serializer = AdminCreatePlayerSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        guardian = data['guardian_id']
        if not guardian.is_active:
            raise ValidationError('The selected guardian must be active.')

        try:
            user, profile, temp_password, note = provision_player(
                first_name=data['first_name'],
                last_name=data['last_name'],
                middle_initial=data['middle_initial'],
                date_of_birth=data['date_of_birth'],
                club=guardian.club,
                guardian=guardian,
            )
        except ProvisioningError as exc:
            raise ValidationError(str(exc))
        AuditLog.record(
            request.user,
            'account.created',
            target=user.email or user.get_full_name() or user.username,
            detail='PLAYER',
        )

        return Response(
            {
                'user': UserSerializer(user).data,
                'player': PlayerSerializer(profile).data,
                'temporary_password': temp_password,
                'note': note,
            },
            status=status.HTTP_201_CREATED,
        )
