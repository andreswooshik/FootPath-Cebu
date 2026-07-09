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

from .models import Roles, User

ALL_ROLES = [
    Roles.ADMIN,
    Roles.COACH,
    Roles.PLAYER,
    Roles.SCHOOL_STAFF,
    Roles.GUARDIAN,
]


def make_user(role):
    email = f'{role.lower()}@footpathcebu.test'
    return User.objects.create(
        username=email,
        email=email,
        role=role,
        firebase_uid=f'uid-{role.lower()}',
    )


class RolePermissionTests(APITestCase):
    """force_authenticate bypasses Firebase and tests the permission layer."""

    def setUp(self):
        self.users = {role: make_user(role) for role in ALL_ROLES}

    def test_admin_users_endpoint_allows_only_admin(self):
        url = reverse('admin-users')
        for role in [
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


class FirebaseAuthMappingTests(APITestCase):
    """Exercise FirebaseAuthentication with the token verification mocked."""

    @patch('accounts.authentication.ensure_initialized')
    @patch('accounts.authentication.firebase_auth.verify_id_token')
    def test_valid_token_maps_to_provisioned_user(self, mock_verify, _mock_init):
        make_user(Roles.COACH)  # firebase_uid = 'uid-coach'
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
