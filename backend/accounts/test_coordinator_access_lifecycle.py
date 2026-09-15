from unittest.mock import Mock, patch

from django.test import TestCase
from django.urls import reverse
from firebase_admin import auth as firebase_auth

from .models import Club, Roles, User
from .services import provision_club_coordinator


class CoordinatorAccessLifecycleTests(TestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Access FC', slug='access-fc')

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_pending_registration_creates_disabled_mobile_identity(
        self,
        get_user,
        create_user,
        initialize,
    ):
        get_user.side_effect = firebase_auth.UserNotFoundError('not found')
        create_user.return_value = Mock(uid='pending-coordinator-uid')

        coordinator, _ = provision_club_coordinator(
            email='coordinator@access.test',
            first_name='Cora',
            last_name='Diaz',
            club=self.club,
            password='Portal!Pass2026',
            is_active=False,
        )

        self.assertFalse(coordinator.is_active)
        self.assertEqual(coordinator.firebase_uid, 'pending-coordinator-uid')
        self.assertTrue(coordinator.check_password('Portal!Pass2026'))
        create_user.assert_called_once_with(
            email='coordinator@access.test',
            password='Portal!Pass2026',
            disabled=True,
        )
        initialize.assert_called_once()

    def test_manual_mobile_access_page_is_removed(self):
        self.assertEqual(self.client.get('/portal/mobile-access/').status_code, 404)

    @patch('portal.views.sync_coordinator_firebase_password', return_value=True)
    def test_password_change_updates_firebase_before_django(self, sync):
        coordinator = User.objects.create_user(
            username='coordinator@password.test',
            email='coordinator@password.test',
            password='Portal!Pass2026',
            role=Roles.COORDINATOR,
            club=self.club,
            firebase_uid='coordinator-password-uid',
        )
        self.client.force_login(coordinator)

        response = self.client.post(
            reverse('portal:password-change'),
            {
                'old_password': 'Portal!Pass2026',
                'new_password1': 'Updated!Pass2027',
                'new_password2': 'Updated!Pass2027',
            },
        )

        self.assertRedirects(response, reverse('portal:dashboard'))
        sync.assert_called_once_with(
            coordinator,
            password='Updated!Pass2027',
        )
        coordinator.refresh_from_db()
        self.assertTrue(coordinator.check_password('Updated!Pass2027'))
