from copy import deepcopy
from io import StringIO
from unittest.mock import Mock, patch
from uuid import uuid4

from django.core.management import call_command
from django.db import IntegrityError
from django.urls import reverse
from firebase_admin import auth as firebase_auth
from rest_framework.test import APITestCase

from academy.models import AuditLog, PlayerProfile
from .models import Club, FirebaseProvisioningCleanup, GuardianLink, PlayerRegistration, Roles, User


class CoordinatorPlayerRegistrationTests(APITestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Registration Club', slug='registration')
        self.coordinator = User.objects.create(username='coordinator', role=Roles.COORDINATOR, club=self.club)
        self.guardian = User.objects.create(username='guardian', email='existing@example.com',
            first_name='Maria', last_name='Santos', role=Roles.GUARDIAN, club=self.club,
            mobile_number='+639171234567')
        self.client.force_authenticate(self.coordinator)
        self.url = reverse('coordinator-player-registration')
        self.guardian_data = {'firstName': ' Ana ', 'lastName': ' Cruz ',
            'email': 'NEW@EXAMPLE.COM', 'mobileNumber': '0918 123 4567'}
        self.payload = {'requestId': str(uuid4()), 'existingGuardianId': self.guardian.pk,
            'player': {'firstName': 'Juan', 'lastName': 'Cruz', 'dateOfBirth': '2012-03-02', 'email': ''}}
        self.init = patch('accounts.services.ensure_initialized').start()
        self.lookup = patch('accounts.services.firebase_auth.get_user_by_email',
            side_effect=firebase_auth.UserNotFoundError('not found')).start()
        self.create = patch('accounts.services.firebase_auth.create_user',
            side_effect=lambda **kwargs: Mock(uid=f'uid-{kwargs["email"]}')).start()
        self.delete = patch('accounts.services.firebase_auth.delete_user').start()
        self.addCleanup(patch.stopall)

    def new_guardian_payload(self):
        payload = deepcopy(self.payload)
        payload.pop('existingGuardianId')
        payload['newGuardian'] = deepcopy(self.guardian_data)
        return payload

    def test_existing_guardian_is_reused_and_can_have_multiple_players(self):
        for _ in range(2):
            self.payload['requestId'] = str(uuid4())
            response = self.client.post(self.url, self.payload, format='json')
            self.assertEqual(response.status_code, 201, response.data)
            self.assertEqual(response.data['guardianId'], str(self.guardian.pk))
            self.assertFalse(response.data['guardianCreated'])
            self.assertEqual(response.data['coordinatorId'], str(self.coordinator.pk))
            self.assertTrue(PlayerProfile.objects.filter(user_id=response.data['playerId']).exists())
        self.assertEqual(User.objects.filter(role=Roles.GUARDIAN).count(), 1)
        self.assertEqual(GuardianLink.objects.filter(guardian=self.guardian).count(), 2)
        self.create.assert_not_called()

    def test_new_guardian_player_and_link_are_created_together(self):
        payload = self.new_guardian_payload()
        payload['player']['email'] = 'player@example.com'
        response = self.client.post(self.url, payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        guardian = User.objects.get(pk=response.data['guardianId'])
        self.assertEqual(guardian.first_name, 'Ana')
        self.assertEqual(guardian.email, 'new@example.com')
        self.assertEqual(guardian.mobile_number, '+639181234567')
        self.assertEqual(guardian.club, self.club)
        self.assertFalse(guardian.has_usable_password())
        self.assertTrue(GuardianLink.objects.filter(guardian=guardian, player_id=response.data['playerId']).exists())
        self.assertEqual(len(response.data['guardianTemporaryPassword']), 12)
        self.assertEqual(len(response.data['playerTemporaryPassword']), 12)
        self.assertEqual(response['Cache-Control'], 'no-store')
        self.assertEqual(self.create.call_count, 2)
        self.assertTrue(AuditLog.objects.filter(action='player.registered').exists())

    def test_guardian_check_is_read_only_and_duplicate_email_is_selectable(self):
        before = User.objects.count()
        response = self.client.post(reverse('coordinator-guardian-check'), self.guardian_data, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(User.objects.count(), before)
        self.create.assert_not_called()
        data = {**self.guardian_data, 'email': 'EXISTING@example.com'}
        response = self.client.post(reverse('coordinator-guardian-check'), data, format='json')
        self.assertEqual(response.status_code, 409)
        self.assertEqual(str(response.data['existingGuardianId']), str(self.guardian.pk))

    def test_duplicate_mobile_is_detected_after_normalization(self):
        data = {**self.guardian_data, 'mobileNumber': '0917-123-4567'}
        response = self.client.post(reverse('coordinator-guardian-check'), data, format='json')
        self.assertEqual(response.status_code, 409)
        self.create.assert_not_called()

    def test_duplicate_is_rechecked_on_final_submit(self):
        payload = self.new_guardian_payload()
        payload['newGuardian']['email'] = self.guardian.email
        response = self.client.post(self.url, payload, format='json')
        self.assertEqual(response.status_code, 409)
        self.assertFalse(PlayerRegistration.objects.exists())
        self.create.assert_not_called()

    def test_invalid_guardian_data_never_creates_accounts(self):
        for key, value in [('firstName', '  '), ('lastName', ''), ('email', 'invalid'), ('mobileNumber', '1234')]:
            payload = self.new_guardian_payload()
            payload['newGuardian'][key] = value
            response = self.client.post(self.url, payload, format='json')
            self.assertEqual(response.status_code, 400, key)
        self.assertFalse(PlayerRegistration.objects.exists())
        self.create.assert_not_called()

    def test_future_date_and_ambiguous_guardian_selection_are_rejected(self):
        self.payload['player']['dateOfBirth'] = '2999-01-01'
        self.assertEqual(self.client.post(self.url, self.payload, format='json').status_code, 400)
        payload = self.new_guardian_payload()
        payload['existingGuardianId'] = self.guardian.pk
        self.assertEqual(self.client.post(self.url, payload, format='json').status_code, 400)
        self.create.assert_not_called()

    def test_retries_return_same_ids_without_duplicate_records_or_password_storage(self):
        payload = self.new_guardian_payload()
        first = self.client.post(self.url, payload, format='json')
        second = self.client.post(self.url, payload, format='json')
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertTrue(second.data['replayed'])
        self.assertEqual(first.data['playerId'], second.data['playerId'])
        self.assertIsNone(second.data['guardianTemporaryPassword'])
        self.assertEqual(GuardianLink.objects.count(), 1)
        self.assertEqual(PlayerRegistration.objects.count(), 1)
        self.create.assert_called_once()
        payload['player']['firstName'] = 'Changed'
        self.assertEqual(self.client.post(self.url, payload, format='json').status_code, 409)

    def test_player_profile_failure_rolls_back_guardian_and_both_identities(self):
        payload = self.new_guardian_payload()
        payload['player']['email'] = 'player@example.com'
        with patch('academy.models.PlayerProfile.objects.create', side_effect=IntegrityError('failed')):
            response = self.client.post(self.url, payload, format='json')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(User.objects.count(), 2)
        self.assertFalse(GuardianLink.objects.exists())
        self.assertFalse(PlayerRegistration.objects.exists())
        self.assertEqual({c.args[0] for c in self.delete.call_args_list}, {'uid-new@example.com', 'uid-player@example.com'})

    def test_link_failure_rolls_back_player_but_does_not_delete_existing_guardian(self):
        self.payload['player']['email'] = 'player@example.com'
        with patch('accounts.services.GuardianLink.objects.create', side_effect=IntegrityError('failed')):
            response = self.client.post(self.url, self.payload, format='json')
        self.assertEqual(response.status_code, 503)
        self.assertTrue(User.objects.filter(pk=self.guardian.pk).exists())
        self.assertFalse(PlayerProfile.objects.exists())
        self.delete.assert_called_once_with('uid-player@example.com')

    def test_late_database_failure_rolls_back_and_cleans_up(self):
        with patch('accounts.registration_service.PlayerRegistration.objects.create', side_effect=IntegrityError('failed')):
            response = self.client.post(self.url, self.new_guardian_payload(), format='json')
        self.assertEqual(response.status_code, 503)
        self.assertEqual(User.objects.count(), 2)
        self.assertFalse(GuardianLink.objects.exists())
        self.delete.assert_called_once_with('uid-new@example.com')

    def test_cleanup_outage_is_queued_and_retry_command_clears_it(self):
        self.delete.side_effect = RuntimeError('offline')
        with patch('academy.models.PlayerProfile.objects.create', side_effect=IntegrityError('failed')):
            self.client.post(self.url, self.new_guardian_payload(), format='json')
        self.assertEqual(FirebaseProvisioningCleanup.objects.count(), 1)
        self.assertFalse(GuardianLink.objects.exists())
        self.delete.side_effect = None
        with patch('accounts.management.commands.retry_provisioning_cleanup.ensure_initialized'):
            call_command('retry_provisioning_cleanup', stdout=StringIO())
        self.assertFalse(FirebaseProvisioningCleanup.objects.exists())

    def test_cross_club_inactive_and_wrong_role_guardians_are_rejected(self):
        other_club = Club.objects.create(name='Other', slug='other')
        other = User.objects.create(username='other', role=Roles.GUARDIAN, club=other_club)
        for user_id in (other.pk, self.coordinator.pk, 999999):
            self.payload['existingGuardianId'] = user_id
            self.assertEqual(self.client.post(self.url, self.payload, format='json').status_code, 400)
        self.guardian.is_active = False
        self.guardian.save()
        self.payload['existingGuardianId'] = self.guardian.pk
        self.assertEqual(self.client.post(self.url, self.payload, format='json').status_code, 400)

    def test_other_roles_and_inactive_clubs_cannot_register(self):
        self.client.force_authenticate(self.guardian)
        self.assertEqual(self.client.post(self.url, self.payload, format='json').status_code, 403)
        self.client.force_authenticate(self.coordinator)
        self.club.is_active = False
        self.club.save()
        self.coordinator.refresh_from_db()
        self.assertEqual(self.client.post(self.url, self.payload, format='json').status_code, 403)

    def test_directory_exposes_only_own_club_guardians_and_mobile_number(self):
        other_club = Club.objects.create(name='Other', slug='other')
        User.objects.create(username='other', role=Roles.GUARDIAN, club=other_club)
        response = self.client.get(reverse('club-member-directory'), {'role': 'GUARDIAN'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['mobileNumber'], '+639171234567')
