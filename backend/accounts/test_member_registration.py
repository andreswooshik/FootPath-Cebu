from unittest.mock import Mock, patch
from uuid import uuid4

from django.urls import reverse
from firebase_admin import auth as firebase_auth
from rest_framework.test import APITestCase

from academy.models import AuditLog, PlayerProfile
from .models import Club, GuardianLink, Roles, User


class CoordinatorMemberRegistrationTests(APITestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Member Club', slug='member-club')
        self.coordinator = User.objects.create(
            username='coordinator', role=Roles.COORDINATOR, club=self.club
        )
        self.client.force_authenticate(self.coordinator)
        self.url = reverse('coordinator-member-registration')
        self.payload = {
            'requestId': str(uuid4()),
            'role': Roles.GUARDIAN,
            'firstName': ' Maria ',
            'middleInitial': 'd.',
            'lastName': ' Santos ',
            'email': 'MARIA@EXAMPLE.COM',
            'mobileNumber': '0917 123 4567',
        }
        patch('accounts.services.ensure_initialized').start()
        patch(
            'accounts.services.firebase_auth.get_user_by_email',
            side_effect=firebase_auth.UserNotFoundError('not found'),
        ).start()
        self.create = patch(
            'accounts.services.firebase_auth.create_user',
            side_effect=lambda **kwargs: Mock(uid=f'uid-{kwargs["email"]}'),
        ).start()
        self.delete = patch('accounts.services.firebase_auth.delete_user').start()
        self.addCleanup(patch.stopall)

    def test_coordinator_creates_guardian_with_normalized_identity(self):
        response = self.client.post(self.url, self.payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        guardian = User.objects.get(pk=response.data['memberId'])
        self.assertEqual(guardian.role, Roles.GUARDIAN)
        self.assertEqual(guardian.first_name, 'Maria')
        self.assertEqual(guardian.middle_initial, 'D')
        self.assertEqual(guardian.last_name, 'Santos')
        self.assertEqual(guardian.email, 'maria@example.com')
        self.assertEqual(guardian.mobile_number, '+639171234567')
        self.assertEqual(response.data['mobileNumber'], '+639171234567')
        self.assertEqual(guardian.club, self.club)
        self.assertIsNotNone(response.data['temporaryPassword'])
        self.assertEqual(response['Cache-Control'], 'no-store')
        self.assertTrue(AuditLog.objects.filter(action='account.created').exists())

    def test_coordinator_creates_coach_without_gaining_other_roles(self):
        payload = {**self.payload, 'role': Roles.COACH, 'email': 'coach@example.com'}
        response = self.client.post(self.url, payload, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        coach = User.objects.get(pk=response.data['memberId'])
        self.assertEqual(coach.role, Roles.COACH)
        self.assertEqual(coach.club, self.club)

    def test_created_guardian_id_links_a_player_through_the_player_endpoint(self):
        guardian_response = self.client.post(self.url, self.payload, format='json')
        self.assertEqual(guardian_response.status_code, 201, guardian_response.data)

        player_response = self.client.post(
            reverse('coordinator-player-registration'),
            {
                'requestId': str(uuid4()),
                'existingGuardianId': guardian_response.data['memberId'],
                'player': {
                    'firstName': 'John',
                    'lastName': 'Santos',
                    'dateOfBirth': '2012-03-02',
                },
            },
            format='json',
        )

        self.assertEqual(player_response.status_code, 201, player_response.data)
        self.assertEqual(
            player_response.data['guardianId'],
            guardian_response.data['memberId'],
        )
        self.assertTrue(
            PlayerProfile.objects.filter(user_id=player_response.data['playerId']).exists()
        )
        self.assertTrue(
            GuardianLink.objects.filter(
                guardian_id=guardian_response.data['memberId'],
                player_id=player_response.data['playerId'],
            ).exists()
        )
        self.create.assert_called_once()

    def test_required_email_role_and_middle_initial_format_are_enforced(self):
        for key, value in (
            ('email', ''),
            ('middleInitial', 'DX'),
            ('role', Roles.PLAYER),
            ('role', Roles.COORDINATOR),
        ):
            response = self.client.post(self.url, {**self.payload, key: value}, format='json')
            self.assertEqual(response.status_code, 400, (key, response.data))
        self.assertFalse(User.objects.filter(email='maria@example.com').exists())
        self.create.assert_not_called()

    def test_middle_initial_is_optional_for_guardian_and_coach(self):
        for index, role in enumerate((Roles.GUARDIAN, Roles.COACH)):
            payload = {
                **self.payload,
                'requestId': str(uuid4()),
                'role': role,
                'email': f'optional-{index}@example.com',
                'mobileNumber': f'0917123456{index}',
            }
            if index == 0:
                payload.pop('middleInitial')
            else:
                payload['middleInitial'] = ''

            response = self.client.post(self.url, payload, format='json')
            self.assertEqual(response.status_code, 201, response.data)
            self.assertEqual(User.objects.get(pk=response.data['memberId']).middle_initial, '')

    def test_duplicate_email_and_mobile_are_rejected_before_firebase(self):
        User.objects.create(
            username='existing@example.com',
            email='existing@example.com',
            mobile_number='+639171234567',
            role=Roles.GUARDIAN,
            club=self.club,
        )
        for changes in (
            {'email': 'existing@example.com', 'mobileNumber': '09181112222'},
            {'email': 'other@example.com', 'mobileNumber': '09171234567'},
        ):
            response = self.client.post(self.url, {**self.payload, **changes}, format='json')
            self.assertEqual(response.status_code, 400, response.data)
        self.create.assert_not_called()

    def test_repeated_submission_is_idempotent(self):
        first = self.client.post(self.url, self.payload, format='json')
        second = self.client.post(self.url, self.payload, format='json')
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.data['memberId'], second.data['memberId'])
        self.assertTrue(second.data['replayed'])
        self.assertIsNone(second.data['temporaryPassword'])
        self.create.assert_called_once()

        changed = {**self.payload, 'firstName': 'Changed'}
        self.assertEqual(self.client.post(self.url, changed, format='json').status_code, 409)

    def test_non_coordinator_and_inactive_club_are_denied(self):
        coach = User.objects.create(username='coach', role=Roles.COACH, club=self.club)
        self.client.force_authenticate(coach)
        self.assertEqual(self.client.post(self.url, self.payload, format='json').status_code, 403)
        self.client.force_authenticate(self.coordinator)
        self.club.is_active = False
        self.club.save(update_fields=['is_active'])
        self.coordinator.refresh_from_db()
        self.assertEqual(self.client.post(self.url, self.payload, format='json').status_code, 403)
