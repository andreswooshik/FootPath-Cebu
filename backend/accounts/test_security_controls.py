from unittest.mock import patch

from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework.test import APITestCase

from .guardian_access import guardian_can_access_player
from .models import Club, GuardianLink, Roles, User
from .throttling import AuthenticatedUserRateThrottle
from .views import MeView


class GuardianLinkInvariantTests(TestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Safe Club', slug='safe-club')
        self.guardian = User.objects.create_user(
            username='guardian@safe.test',
            role=Roles.GUARDIAN,
            club=self.club,
        )
        self.player = User.objects.create_user(
            username='player@safe.test',
            role=Roles.PLAYER,
            club=self.club,
        )

    def test_direct_orm_create_runs_model_validation(self):
        self.guardian.is_active = False
        self.guardian.save(update_fields=['is_active'])
        with self.assertRaises(ValidationError):
            GuardianLink.objects.create(
                guardian=self.guardian,
                player=self.player,
            )

    def test_legacy_invalid_link_does_not_authorize_access(self):
        GuardianLink.objects.create(guardian=self.guardian, player=self.player)
        User.objects.filter(pk=self.guardian.pk).update(role=Roles.COACH)
        self.guardian.refresh_from_db()
        self.assertFalse(guardian_can_access_player(self.guardian, self.player.pk))


_THROTTLE_SETTINGS = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'accounts.authentication.FirebaseAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'DEFAULT_THROTTLE_CLASSES': [
        'accounts.throttling.AuthenticatedUserRateThrottle',
        'rest_framework.throttling.ScopedRateThrottle',
    ],
    'DEFAULT_THROTTLE_RATES': {
        'user': '2/minute',
        'pin': '100/minute',
        'uploads': '100/minute',
        'account_admin': '100/minute',
    },
}


@override_settings(REST_FRAMEWORK=_THROTTLE_SETTINGS)
class AuthenticatedApiThrottleTests(APITestCase):
    def setUp(self):
        cache.clear()
        club = Club.objects.create(name='Throttle Club', slug='throttle-club')
        self.user = User.objects.create_user(
            username='throttle@safe.test',
            role=Roles.COACH,
            club=club,
        )
        self.client.force_authenticate(self.user)

    def test_authenticated_requests_have_a_global_budget(self):
        class TwoPerMinuteThrottle(AuthenticatedUserRateThrottle):
            rate = '2/minute'

        with patch.object(MeView, 'throttle_classes', [TwoPerMinuteThrottle]):
            self.assertEqual(self.client.get(reverse('auth-me')).status_code, 200)
            self.assertEqual(self.client.get(reverse('auth-me')).status_code, 200)
            self.assertEqual(self.client.get(reverse('auth-me')).status_code, 429)
