"""Role-based access control tests.

These exercise the Day-1 authorization guarantees end-to-end at the request
layer: every admin endpoint rejects non-admin roles, the profile endpoint
requires authentication, health is public, and a verified Firebase token maps
to the correct provisioned user. Firebase verification is mocked so the suite
runs in CI without real credentials.
"""

from unittest.mock import patch

from django.urls import reverse
from rest_framework.test import APITestCase

from .models import Club, Roles, User

ALL_ROLES = [
    Roles.ADMIN,
    Roles.COORDINATOR,
    Roles.COACH,
    Roles.PLAYER,
    Roles.SCHOOL_STAFF,
    Roles.GUARDIAN,
]


def make_user(role):
    email = f'{role.lower()}@footpathcebu.test'
    club = None
    if role != Roles.ADMIN:
        club, _ = Club.objects.get_or_create(
            slug='accounts-test-club',
            defaults={
                'name': 'Accounts Test Club',
                'is_school_affiliated': True,
                'school_name': 'Test School',
            },
        )
    return User.objects.create(
        username=email,
        email=email,
        role=role,
        firebase_uid=f'uid-{role.lower()}',
        club=club,
    )


class RolePermissionTests(APITestCase):
    """force_authenticate bypasses Firebase and tests the permission layer."""

    def setUp(self):
        self.users = {role: make_user(role) for role in ALL_ROLES}

    def test_admin_users_endpoint_allows_only_admin(self):
        url = reverse('admin-users')
        for role in [
            Roles.COORDINATOR,
            Roles.COACH,
            Roles.PLAYER,
            Roles.SCHOOL_STAFF,
            Roles.GUARDIAN,
        ]:
            self.client.force_authenticate(self.users[role])
            self.assertEqual(
                self.client.get(url).status_code, 403, msg=f'{role} should be denied'
            )
        self.client.force_authenticate(self.users[Roles.ADMIN])
        self.assertEqual(self.client.get(url).status_code, 200)

    def test_guardian_links_endpoint_allows_only_admin(self):
        url = reverse('admin-guardian-links')
        self.client.force_authenticate(self.users[Roles.COACH])
        self.assertEqual(self.client.get(url).status_code, 403)
        self.client.force_authenticate(self.users[Roles.ADMIN])
        self.assertEqual(self.client.get(url).status_code, 200)

    def test_me_requires_authentication(self):
        url = reverse('auth-me')
        # Unauthenticated is rejected.
        self.assertIn(self.client.get(url).status_code, (401, 403))
        # Any authenticated role can read their own profile, with correct role.
        self.client.force_authenticate(self.users[Roles.PLAYER])
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['role'], Roles.PLAYER)

    def test_health_is_public(self):
        response = self.client.get(reverse('health'))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['status'], 'ok')


class AdminUserLifecycleTests(APITestCase):
    """PATCH /api/admin/users/<pk>/ — role switching and (de)activation."""

    def setUp(self):
        self.admin = make_user(Roles.ADMIN)
        self.coach = make_user(Roles.COACH)
        self.client.force_authenticate(self.admin)

    def _url(self, user):
        return reverse('admin-user-detail', args=[user.id])

    def test_non_admin_is_denied(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.patch(
            self._url(self.coach), {'is_active': False}, format='json'
        )
        self.assertEqual(resp.status_code, 403)

    def test_deactivate_and_reactivate(self):
        resp = self.client.patch(
            self._url(self.coach), {'is_active': False}, format='json'
        )
        self.assertEqual(resp.status_code, 200)
        self.coach.refresh_from_db()
        self.assertFalse(self.coach.is_active)

        resp = self.client.patch(
            self._url(self.coach), {'is_active': True}, format='json'
        )
        self.assertEqual(resp.status_code, 200)
        self.coach.refresh_from_db()
        self.assertTrue(self.coach.is_active)

    @patch('accounts.authentication.ensure_initialized')
    @patch('accounts.authentication.firebase_auth.verify_id_token')
    def test_deactivated_user_is_locked_out_of_the_api(
        self, mock_verify, _mock_init
    ):
        """The authentication layer filters is_active — deactivation takes
        effect on the very next request, not at next login."""
        self.coach.is_active = False
        self.coach.save(update_fields=['is_active'])
        mock_verify.return_value = {'uid': self.coach.firebase_uid}

        self.client.force_authenticate(None)
        self.client.credentials(HTTP_AUTHORIZATION='Bearer fake-token')
        resp = self.client.get(reverse('auth-me'))
        self.assertIn(resp.status_code, (401, 403))

    def test_coach_becomes_school_staff_with_a_portal_password(self):
        resp = self.client.patch(
            self._url(self.coach), {'role': Roles.SCHOOL_STAFF}, format='json'
        )
        self.assertEqual(resp.status_code, 200)
        self.coach.refresh_from_db()
        self.assertEqual(self.coach.role, Roles.SCHOOL_STAFF)
        # A web role needs a Django session password, issued and relayed once.
        temp = resp.data['temporary_password']
        self.assertTrue(temp)
        self.assertTrue(self.coach.check_password(temp))

    @patch('accounts.services.link_or_create_firebase_user', return_value=None)
    def test_school_staff_becomes_coach_via_firebase(self, mock_link):
        staff = make_user(Roles.SCHOOL_STAFF)
        resp = self.client.patch(
            self._url(staff), {'role': Roles.COACH}, format='json'
        )
        self.assertEqual(resp.status_code, 200)
        staff.refresh_from_db()
        self.assertEqual(staff.role, Roles.COACH)
        mock_link.assert_called_once()

    def test_player_role_is_locked(self):
        player = make_user(Roles.PLAYER)
        resp = self.client.patch(
            self._url(player), {'role': Roles.COACH}, format='json'
        )
        self.assertEqual(resp.status_code, 400)
        player.refresh_from_db()
        self.assertEqual(player.role, Roles.PLAYER)

    def test_guardian_with_links_is_blocked(self):
        from .models import GuardianLink

        guardian = make_user(Roles.GUARDIAN)
        player = make_user(Roles.PLAYER)
        GuardianLink.objects.create(guardian=guardian, player=player)
        resp = self.client.patch(
            self._url(guardian), {'role': Roles.COACH}, format='json'
        )
        self.assertEqual(resp.status_code, 400)

    def test_lifecycle_changes_are_audited(self):
        from academy.models import AuditLog

        self.client.patch(
            self._url(self.coach), {'role': Roles.SCHOOL_STAFF}, format='json'
        )
        self.client.patch(
            self._url(self.coach), {'is_active': False}, format='json'
        )
        self.assertTrue(
            AuditLog.objects.filter(
                action='account.role_changed', actor=self.admin,
                target=self.coach.email,
            ).exists()
        )
        self.assertTrue(
            AuditLog.objects.filter(action='account.deactivated').exists()
        )

    def test_admin_accounts_are_out_of_reach(self):
        other_admin = User.objects.create(
            username='root@footpathcebu.test', email='root@footpathcebu.test',
            role=Roles.ADMIN, firebase_uid='uid-root',
        )
        resp = self.client.patch(
            self._url(other_admin), {'is_active': False}, format='json'
        )
        self.assertEqual(resp.status_code, 404)


class FirebaseAuthMappingTests(APITestCase):
    """Exercise FirebaseAuthentication with the token verification mocked."""

    @patch('accounts.authentication.ensure_initialized')
    @patch('accounts.authentication.firebase_auth.verify_id_token')
    def test_valid_token_maps_to_provisioned_user(self, mock_verify, _mock_init):
        club = Club.objects.create(name='Auth Test Club', slug='auth-test-club')
        user = make_user(Roles.COACH)
        user.club = club
        user.save(update_fields=['club'])
        mock_verify.return_value = {'uid': 'uid-coach'}

        self.client.credentials(HTTP_AUTHORIZATION='Bearer fake-token')
        response = self.client.get(reverse('auth-me'))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['firebase_uid'], 'uid-coach')
        self.assertEqual(response.data['role'], Roles.COACH)

    @patch('accounts.authentication.ensure_initialized')
    @patch('accounts.authentication.firebase_auth.verify_id_token')
    def test_valid_token_without_local_account_is_rejected(
        self, mock_verify, _mock_init
    ):
        # A real Firebase user who was never provisioned by an Admin.
        mock_verify.return_value = {'uid': 'ghost-uid'}

        self.client.credentials(HTTP_AUTHORIZATION='Bearer fake-token')
        response = self.client.get(reverse('auth-me'))

        self.assertIn(response.status_code, (401, 403))
