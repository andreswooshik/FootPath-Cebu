"""Short-lived grants for household player privacy."""

from django.core import signing
from rest_framework.exceptions import PermissionDenied

_SALT = 'footpath.player-unlock.v1'
_MAX_AGE_SECONDS = 10 * 60


def issue_player_unlock(user_id, player_id):
    return signing.dumps(
        {'user': str(user_id), 'player': str(player_id)},
        salt=_SALT,
    )


def require_player_unlock(request, player_id):
    raw_token = request.headers.get('X-Player-Unlock', '')
    try:
        claims = signing.loads(raw_token, salt=_SALT, max_age=_MAX_AGE_SECONDS)
    except signing.BadSignature as exc:
        raise PermissionDenied('Player profile unlock required.') from exc

    if (
        claims.get('user') != str(request.user.id)
        or claims.get('player') != str(player_id)
    ):
        raise PermissionDenied('Player profile unlock required.')

