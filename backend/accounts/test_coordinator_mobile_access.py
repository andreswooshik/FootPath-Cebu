from types import SimpleNamespace
from unittest.mock import patch

from django.test import TestCase
from django.urls import reverse
from firebase_admin import auth as firebase_auth

from .models import Club, Roles, User
from .services import ProvisioningError, enable_coordinator_mobile_access


class CoordinatorMobileAccessServiceTests(TestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Mobile Access FC', slug='mobile-access-fc')
        self.coordinator = User.objects.create_user(
            username='coordinator@access.test',
            email='coordinator@access.test',
            password='Portal!Pass2026',
            role=Roles.COORDINATOR,
            club=self.club,
        )

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_creates_enabled_firebase_identity_with_same_password(
        self, get_user, create_user, ensure_initialized,
    ):
        get_user.side_effect = firebase_auth.UserNotFoundError('not found')
        create_user.return_value = SimpleNamespace(uid='coordinator-firebase-uid')

        created = enable_coordinator_mobile_access(
            self.coordinator,
            password='Portal!Pass2026',
        )

        self.assertTrue(created)
        self.coordinator.refresh_from_db()
        self.assertEqual(self.coordinator.firebase_uid, 'coordinator-firebase-uid')
        self.assertTrue(self.coordinator.check_password('Portal!Pass2026'))
        create_user.assert_called_once_with(
            email='coordinator@access.test',
            password='Portal!Pass2026',
            disabled=False,
        )
        ensure_initialized.assert_called_once()

    def test_rejects_wrong_current_password_before_firebase(self):
        with patch('accounts.services.ensure_initialized') as initialize:
            with self.assertRaisesMessage(ProvisioningError, 'incorrect'):
                enable_coordinator_mobile_access(
                    self.coordinator,
                    password='Wrong!Pass2026',
                )
        initialize.assert_not_called()


class CoordinatorMobileAccessPortalTests(TestCase):
    def setUp(self):
        club = Club.objects.create(name='Portal Mobile FC', slug='portal-mobile-fc')
        self.coordinator = User.objects.create_user(
            username='coordinator@portal-mobile.test',
            email='coordinator@portal-mobile.test',
            password='Portal!Pass2026',
            role=Roles.COORDINATOR,
            club=club,
        )
        self.client.force_login(self.coordinator)

    @patch('portal.views.enable_coordinator_mobile_access', return_value=True)
    def test_coordinator_enables_mobile_access_from_portal(self, enable):
        response = self.client.post(
            reverse('portal:mobile-access'),
            {'current_password': 'Portal!Pass2026'},
        )
        self.assertRedirects(response, reverse('portal:mobile-access'))
        enable.assert_called_once_with(
            self.coordinator,
            password='Portal!Pass2026',
        )

    @patch('portal.views.sync_coordinator_mobile_password', return_value=True)
    def test_password_change_updates_mobile_before_django(self, sync):
        response = self.client.post(reverse('portal:password-change'), {
            'old_password': 'Portal!Pass2026',
            'new_password1': 'Updated!Pass2027',
            'new_password2': 'Updated!Pass2027',
        })
        self.assertRedirects(response, reverse('portal:dashboard'))
        sync.assert_called_once_with(
            self.coordinator,
            password='Updated!Pass2027',
        )
        self.coordinator.refresh_from_db()
        self.assertTrue(self.coordinator.check_password('Updated!Pass2027'))
