"""Tests for account provisioning and Firebase auto-sync.

Three layers are covered:

1. The service layer — `link_or_create_firebase_user` and `provision_user`.
2. The Django-admin auto-sync — `CustomUserAdmin.save_model` provisions a
   Firebase identity when an Admin creates an app account in /admin/.
3. The admin provisioning API — POST /api/admin/users/, which the console
   dashboard's "Create Account" form calls.

The Firebase Admin SDK is mocked throughout so the suite runs in CI without
service-account credentials or network access. Every test that would create a
Firebase account patches `firebase_auth.get_user_by_email` /
`firebase_auth.create_user` and `ensure_initialized`.
"""

from unittest.mock import Mock, patch

from django.contrib.admin.sites import site
from django.test import TestCase
from django.urls import reverse
from firebase_admin import auth as firebase_auth
from rest_framework.test import APITestCase

from .admin import CustomUserAdmin
from .models import Club, Roles, User
from .services import (
    ProvisioningError,
    link_or_create_firebase_user,
    provision_user,
)


class _FakeForm:
    """Stand-in for the admin add form — only `cleaned_data` is read."""

    def __init__(self, **cleaned_data):
        self.cleaned_data = cleaned_data


class LinkOrCreateFirebaseUserTests(TestCase):
    """Unit tests for the reusable `link_or_create_firebase_user` helper."""

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_creates_new_firebase_account_with_given_password(
        self, mock_get, mock_create, _init
    ):
        mock_get.side_effect = firebase_auth.UserNotFoundError('not found')
        mock_create.return_value = Mock(uid='new-uid')

        user = User(username='a@x.test', email='a@x.test', role=Roles.PLAYER)
        temp = link_or_create_firebase_user(user, password='TypedPass123!')

        self.assertEqual(user.firebase_uid, 'new-uid')
        self.assertEqual(temp, 'TypedPass123!')
        self.assertFalse(user.has_usable_password())  # app auth via Firebase only
        mock_create.assert_called_once_with(
            email='a@x.test', password='TypedPass123!'
        )

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_generates_password_when_none_supplied(
        self, mock_get, mock_create, _init
    ):
        mock_get.side_effect = firebase_auth.UserNotFoundError('not found')
        mock_create.return_value = Mock(uid='new-uid')

        user = User(username='a@x.test', email='a@x.test', role=Roles.PLAYER)
        temp = link_or_create_firebase_user(user)

        self.assertIsNotNone(temp)
        self.assertGreaterEqual(len(temp), 12)
        # The generated password is the one handed to Firebase.
        mock_create.assert_called_once_with(email='a@x.test', password=temp)

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_links_existing_firebase_account_without_creating(
        self, mock_get, mock_create, _init
    ):
        mock_get.return_value = Mock(uid='existing-uid')  # account already there

        user = User(username='a@x.test', email='a@x.test', role=Roles.PLAYER)
        temp = link_or_create_firebase_user(user, password='ignored')

        self.assertEqual(user.firebase_uid, 'existing-uid')
        self.assertIsNone(temp)  # existing account -> no new password
        mock_create.assert_not_called()

    def test_requires_an_email(self):
        user = User(username='noemail', email='', role=Roles.PLAYER)
        with self.assertRaises(ProvisioningError):
            link_or_create_firebase_user(user)


class ProvisionUserTests(TestCase):
    """Unit tests for `provision_user` (used by the admin API)."""

    def setUp(self):
        self.club = Club.objects.create(
            name='Provisioning Club', slug='provisioning-club',
            is_school_affiliated=True, school_name='Provisioning School',
        )

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_creates_local_row_and_returns_temp_password(
        self, mock_get, mock_create, _init
    ):
        mock_get.side_effect = firebase_auth.UserNotFoundError('not found')
        mock_create.return_value = Mock(uid='fb-uid-1')

        user, temp, note = provision_user(
            email='new@x.test', first_name='New', last_name='Player',
            role=Roles.COACH, club=self.club,
        )

        self.assertTrue(User.objects.filter(email='new@x.test').exists())
        self.assertEqual(user.firebase_uid, 'fb-uid-1')
        self.assertEqual(user.role, Roles.COACH)
        self.assertIsNotNone(temp)
        self.assertIn('New Firebase', note)

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_rejects_duplicate_email(self, mock_get, mock_create, _init):
        User.objects.create(
            username='dupe@x.test', email='dupe@x.test',
            role=Roles.COACH, firebase_uid='existing', club=self.club,
        )
        with self.assertRaises(ProvisioningError):
            provision_user(
                email='dupe@x.test', first_name='D', last_name='U',
                role=Roles.COACH, club=self.club,
            )
        mock_create.assert_not_called()  # never touches Firebase on a dupe

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.delete_user')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_deletes_new_firebase_account_when_db_save_fails(
        self, mock_get, mock_create, mock_delete, _init
    ):
        # We CREATE a Firebase account, then the DB write blows up.
        mock_get.side_effect = firebase_auth.UserNotFoundError('not found')
        mock_create.return_value = Mock(uid='orphan-uid')

        with patch.object(User, 'save', side_effect=RuntimeError('db down')):
            with self.assertRaises(RuntimeError):
                provision_user(
                    email='fail@x.test', first_name='F', last_name='X',
                    role=Roles.COACH, club=self.club,
                )

        # Compensation ran: the orphan Firebase account was deleted.
        mock_delete.assert_called_once_with('orphan-uid')
        self.assertFalse(User.objects.filter(email='fail@x.test').exists())

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.delete_user')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_does_not_delete_adopted_account_when_db_save_fails(
        self, mock_get, mock_create, mock_delete, _init
    ):
        # We ADOPT an existing Firebase account; a DB failure must NOT delete it.
        mock_get.return_value = Mock(uid='existing-uid')

        with patch.object(User, 'save', side_effect=RuntimeError('db down')):
            with self.assertRaises(RuntimeError):
                provision_user(
                    email='adopt@x.test', first_name='A', last_name='D',
                    role=Roles.COACH, club=self.club,
                )

        mock_create.assert_not_called()
        mock_delete.assert_not_called()  # never delete an account we didn't make


class AdminAutoSyncTests(TestCase):
    """`CustomUserAdmin.save_model` auto-provisions Firebase for new accounts.

    `message_user` is patched away (it needs the messages middleware); these
    tests care only about whether the Firebase sync ran and linked a uid.
    """

    def setUp(self):
        self.admin = CustomUserAdmin(User, site)
        self.club = Club.objects.create(
            name='Admin Form Club', slug='admin-form-club',
            is_school_affiliated=True, school_name='Admin Form School',
        )

    @patch.object(CustomUserAdmin, 'message_user')
    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_new_app_user_is_synced_to_firebase(
        self, mock_get, mock_create, _init, _msg
    ):
        mock_get.side_effect = firebase_auth.UserNotFoundError('not found')
        mock_create.return_value = Mock(uid='synced-uid')

        obj = User(
            username='p@x.test', email='p@x.test', role=Roles.COACH,
            club=self.club,
        )
        self.admin.save_model(
            Mock(), obj, _FakeForm(password1='TypedPass123!'), change=False
        )

        obj.refresh_from_db()
        self.assertEqual(obj.firebase_uid, 'synced-uid')
        self.assertFalse(obj.has_usable_password())

    @patch.object(CustomUserAdmin, 'message_user')
    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_superuser_is_not_synced(
        self, mock_get, mock_create, _init, _msg
    ):
        obj = User(
            username='root', email='root@x.test', role=Roles.ADMIN,
            is_staff=True, is_superuser=True,
        )
        self.admin.save_model(
            Mock(), obj, _FakeForm(password1='x'), change=False
        )

        obj.refresh_from_db()
        self.assertIsNone(obj.firebase_uid)  # /admin/ account, session login
        mock_create.assert_not_called()

    @patch.object(CustomUserAdmin, 'message_user')
    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_user_without_email_is_not_synced(
        self, mock_get, mock_create, _init, _msg
    ):
        obj = User(
            username='noemail', email='', role=Roles.COACH, club=self.club,
        )
        self.admin.save_model(
            Mock(), obj, _FakeForm(password1='x'), change=False
        )

        obj.refresh_from_db()
        self.assertIsNone(obj.firebase_uid)
        mock_create.assert_not_called()

    @patch.object(CustomUserAdmin, 'message_user')
    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_editing_existing_user_does_not_resync(
        self, mock_get, mock_create, _init, _msg
    ):
        obj = User.objects.create(
            username='edit@x.test', email='edit@x.test', role=Roles.COACH,
            club=self.club,
        )
        self.admin.save_model(
            Mock(), obj, _FakeForm(), change=True  # change=True -> an edit
        )

        obj.refresh_from_db()
        self.assertIsNone(obj.firebase_uid)
        mock_create.assert_not_called()


class ConsoleProvisioningApiTests(APITestCase):
    """POST /api/admin/users/ — the endpoint the console dashboard calls."""

    def setUp(self):
        self.club = Club.objects.create(
            name='Console Club', slug='console-club',
            is_school_affiliated=True, school_name='Console School',
        )
        self.admin = User.objects.create(
            username='admin@x.test', email='admin@x.test',
            role=Roles.ADMIN, firebase_uid='admin-uid',
        )
        self.coach = User.objects.create(
            username='coach@x.test', email='coach@x.test',
            role=Roles.COACH, firebase_uid='coach-uid', club=self.club,
        )

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_admin_creates_account_with_email(
        self, mock_get, mock_create, _init
    ):
        mock_get.side_effect = firebase_auth.UserNotFoundError('not found')
        mock_create.return_value = Mock(uid='provisioned-uid')

        self.client.force_authenticate(self.admin)
        response = self.client.post(
            reverse('admin-users'),
            {
                'email': 'brandnew@x.test',
                'first_name': 'Brand',
                'last_name': 'New',
                'role': Roles.COACH,
                'club_id': self.club.id,
            },
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['user']['email'], 'brandnew@x.test')
        self.assertIsNotNone(response.data['temporary_password'])
        created = User.objects.get(email='brandnew@x.test')
        self.assertEqual(created.firebase_uid, 'provisioned-uid')
        self.assertEqual(created.role, Roles.COACH)

    def test_non_admin_cannot_create_account(self):
        self.client.force_authenticate(self.coach)
        response = self.client.post(
            reverse('admin-users'),
            {
                'email': 'x@x.test', 'first_name': '', 'last_name': '',
                'role': Roles.COACH, 'club_id': self.club.id,
            },
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_missing_email_is_rejected(self):
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            reverse('admin-users'),
            {
                'first_name': 'No', 'last_name': 'Email',
                'role': Roles.COACH, 'club_id': self.club.id,
            },
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('email', response.data)

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth.create_user')
    @patch('accounts.services.firebase_auth.get_user_by_email')
    def test_duplicate_email_is_rejected(self, mock_get, mock_create, _init):
        User.objects.create(
            username='taken@x.test', email='taken@x.test',
            role=Roles.COACH, firebase_uid='taken-uid', club=self.club,
        )
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            reverse('admin-users'),
            {
                'email': 'taken@x.test', 'first_name': '', 'last_name': '',
                'role': Roles.COACH, 'club_id': self.club.id,
            },
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        mock_create.assert_not_called()
