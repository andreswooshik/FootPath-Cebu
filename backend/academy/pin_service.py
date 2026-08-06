"""Application service for player privacy PINs.

PIN policy is centralized here so the API, portal, and future clients share
the same validation, hashing, and lockout behavior.
"""

import re
from datetime import timedelta

from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from django.utils import timezone

from .models import PlayerPrivacyPin

MIN_PIN_LENGTH = 4
MAX_PIN_LENGTH = 6
MAX_FAILED_ATTEMPTS = 5
LOCKOUT_MINUTES = 15
_PIN_PATTERN = re.compile(r'^\d{4,6}$')


class PinError(Exception):
    """Base class for expected privacy PIN failures."""


class InvalidPin(PinError):
    pass


class InvalidCurrentPin(PinError):
    pass


class PinNotSet(PinError):
    pass


class PinLocked(PinError):
    def __init__(self, locked_until):
        super().__init__('The PIN is temporarily locked.')
        self.locked_until = locked_until


def validate_pin(pin):
    pin = str(pin or '').strip()
    if not _PIN_PATTERN.fullmatch(pin):
        raise ValueError(
            f'PIN must contain {MIN_PIN_LENGTH} to {MAX_PIN_LENGTH} digits.'
        )
    return pin


def _state_for_update(player):
    state, _ = PlayerPrivacyPin.objects.select_for_update().get_or_create(
        player=player
    )
    return state


def has_pin(player):
    return bool(
        PlayerPrivacyPin.objects.filter(player=player)
        .values_list('pin_hash', flat=True)
        .first()
    )


def pin_status(player):
    state = PlayerPrivacyPin.objects.filter(player=player).first()
    locked = bool(state and state.locked_until and state.locked_until > timezone.now())
    return {
        'hasPin': bool(state and state.pin_hash),
        'locked': locked,
        'lockedUntil': state.locked_until.isoformat() if locked else None,
    }


@transaction.atomic
def set_pin(player, pin, current_pin=None):
    """Create or change a player's PIN; changing requires the old PIN."""
    pin = validate_pin(pin)
    state = _state_for_update(player)
    if state.pin_hash:
        if current_pin is None or not check_password(
            str(current_pin).strip(), state.pin_hash
        ):
            raise InvalidCurrentPin('The current PIN is incorrect.')
    state.pin_hash = make_password(pin)
    state.failed_attempts = 0
    state.locked_until = None
    state.save(update_fields=['pin_hash', 'failed_attempts', 'locked_until', 'updated_at'])


def verify_pin(player, pin):
    """Verify a PIN and apply a bounded temporary lockout on failures."""
    locked_until = None
    with transaction.atomic():
        state = _state_for_update(player)
        now = timezone.now()
        if not state.pin_hash:
            raise PinNotSet('No PIN has been set.')
        if state.locked_until and state.locked_until > now:
            raise PinLocked(state.locked_until)
        if check_password(str(pin or '').strip(), state.pin_hash):
            state.failed_attempts = 0
            state.locked_until = None
            state.save(update_fields=['failed_attempts', 'locked_until', 'updated_at'])
            return True

        state.failed_attempts += 1
        if state.failed_attempts >= MAX_FAILED_ATTEMPTS:
            state.locked_until = now + timedelta(minutes=LOCKOUT_MINUTES)
            state.failed_attempts = 0
            locked_until = state.locked_until
        state.save(update_fields=['failed_attempts', 'locked_until', 'updated_at'])

    # Raise after the atomic block so failed-attempt state is committed rather
    # than rolled back by the expected exception.
    if locked_until:
        raise PinLocked(locked_until)
    raise InvalidPin('The PIN is incorrect.')


@transaction.atomic
def reset_pin(player):
    """Clear a player's PIN and any lockout counters."""
    state = _state_for_update(player)
    state.pin_hash = ''
    state.failed_attempts = 0
    state.locked_until = None
    state.save(update_fields=['pin_hash', 'failed_attempts', 'locked_until', 'updated_at'])
