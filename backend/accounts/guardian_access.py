"""Single fail-closed policy for every guardian-to-player authorization."""

from django.db import models

from .models import GuardianLink, Roles


def valid_guardian_links(*, guardian=None, player_id=None):
    queryset = GuardianLink.objects.filter(
        guardian__role=Roles.GUARDIAN,
        guardian__is_active=True,
        guardian__club__is_active=True,
        player__role=Roles.PLAYER,
        player__is_active=True,
        player__club__is_active=True,
    ).filter(guardian__club_id=models.F('player__club_id'))
    if guardian is not None:
        if (
            guardian.role != Roles.GUARDIAN
            or not guardian.is_active
            or guardian.club_id is None
        ):
            return queryset.none()
        queryset = queryset.filter(guardian=guardian)
    if player_id is not None:
        queryset = queryset.filter(player_id=player_id)
    return queryset


def guardian_can_access_player(guardian, player_id):
    return valid_guardian_links(
        guardian=guardian,
        player_id=player_id,
    ).exists()
