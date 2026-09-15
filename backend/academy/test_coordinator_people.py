from datetime import date
from unittest.mock import patch
from uuid import uuid4

from django.urls import reverse
from rest_framework.test import APITestCase

from accounts.models import (
    Club,
    FirebaseProvisioningCleanup,
    GuardianLink,
    PlayerRegistration,
    Roles,
    User,
)
from academy.models import AuditLog, PlayerProfile
from academy.model_tournaments import (
    TournamentAgeBracket,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
)


class CoordinatorPeopleTests(APITestCase):
    def setUp(self):
        self.club = Club.objects.create(name='People Club', slug='people-club')
        self.other_club = Club.objects.create(name='Other Club', slug='other-club')
        self.coordinator = self.user('coordinator', Roles.COORDINATOR)
        self.guardian = self.user(
            'guardian',
            Roles.GUARDIAN,
            first_name='Maria',
            middle_initial='D',
            last_name='Santos',
            email='maria@example.com',
            mobile_number='+639171234567',
            firebase_uid='firebase-guardian',
        )
        self.player = self.player_user(
            'john-player',
            first_name='John',
            last_name='Santos',
            middle_initial='P',
        )
        self.sibling = self.player_user(
            'mark-player',
            first_name='Mark',
            last_name='Santos',
        )
        GuardianLink.objects.create(guardian=self.guardian, player=self.player)
        GuardianLink.objects.create(guardian=self.guardian, player=self.sibling)
        self.client.force_authenticate(self.coordinator)
        self.firebase_init = patch('academy.view_people.ensure_initialized').start()
        self.firebase_delete = patch('academy.view_people.firebase_auth.delete_user').start()
        self.addCleanup(patch.stopall)

    def user(self, username, role, club=None, **kwargs):
        return User.objects.create(
            username=username,
            role=role,
            club=club or self.club,
            **kwargs,
        )

    def player_user(self, username, *, club=None, middle_initial='', **kwargs):
        player = self.user(username, Roles.PLAYER, club=club, **kwargs)
        PlayerProfile.objects.create(
            user=player,
            middle_initial=middle_initial,
            date_of_birth=date(2012, 5, 4),
            age=14,
            class_year='Class of 2030',
            age_tier='DEVELOPMENT',
            position='ST',
        )
        return player

    def url(self, role, person):
        return reverse(
            'coordinator-person-detail',
            kwargs={'role': role, 'person_id': person.pk},
        )

    def test_details_use_relationship_ids_for_player_and_guardian(self):
        player_response = self.client.get(self.url('players', self.player))
        self.assertEqual(player_response.status_code, 200, player_response.data)
        self.assertEqual(player_response.data['middleInitial'], 'P')
        self.assertEqual(player_response.data['dateOfBirth'], '2012-05-04')
        self.assertEqual(player_response.data['position'], 'ST')
        self.assertEqual(
            [row['id'] for row in player_response.data['linkedPeople']],
            [str(self.guardian.pk)],
        )

        guardian_response = self.client.get(self.url('guardians', self.guardian))
        self.assertEqual(guardian_response.status_code, 200, guardian_response.data)
        self.assertEqual(guardian_response.data['middleInitial'], 'D')
        self.assertCountEqual(
            [row['id'] for row in guardian_response.data['linkedPeople']],
            [str(self.player.pk), str(self.sibling.pk)],
        )

    def test_coach_details_show_existing_contact_fields(self):
        coach = self.user(
            'coach',
            Roles.COACH,
            first_name='Carlo',
            last_name='Reyes',
            email='coach@example.com',
            mobile_number='+639181234567',
        )
        response = self.client.get(self.url('coaches', coach))
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['name'], 'Carlo Reyes')
        self.assertEqual(response.data['email'], 'coach@example.com')
        self.assertEqual(response.data['linkedPeople'], [])

    def test_details_and_delete_are_coordinator_and_club_scoped(self):
        outsider = self.player_user(
            'outsider-player',
            club=self.other_club,
            first_name='Outside',
            last_name='Player',
        )
        self.assertEqual(self.client.get(self.url('players', outsider)).status_code, 404)

        self.client.force_authenticate(self.guardian)
        self.assertEqual(self.client.get(self.url('players', self.player)).status_code, 403)
        self.assertEqual(self.client.delete(self.url('players', self.player)).status_code, 403)

    @patch('academy.view_people.delete_photo')
    def test_deleting_player_removes_entire_profile_and_related_records(
        self, delete_photo
    ):
        player_id = self.player.pk
        self.player.player_profile.photo_path = 'player-photos/john.jpg'
        self.player.player_profile.save(update_fields=['photo_path'])
        receipt = PlayerRegistration.objects.create(
            coordinator=self.coordinator,
            request_key=uuid4(),
            payload_hash='hash',
            player=self.player,
            guardian=self.guardian,
            guardian_created=False,
        )
        schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Deletion Cup',
        )
        bracket = TournamentAgeBracket.objects.create(
            schedule=schedule,
            max_age=18,
            academy_tiers=['DEVELOPMENT'],
        )
        squad = TournamentSquad.objects.create(bracket=bracket)
        squad_entry = TournamentSquadEntry.objects.create(
            squad=squad,
            player=self.player,
            added_by=self.coordinator,
        )
        response = self.client.delete(self.url('players', self.player))
        self.assertEqual(response.status_code, 204, response.data)

        self.guardian.refresh_from_db()
        self.sibling.refresh_from_db()
        self.assertFalse(User.objects.filter(pk=player_id).exists())
        self.assertTrue(self.guardian.is_active)
        self.assertTrue(self.sibling.is_active)
        self.assertFalse(PlayerProfile.objects.filter(user_id=player_id).exists())
        self.assertFalse(PlayerRegistration.objects.filter(pk=receipt.pk).exists())
        self.assertFalse(TournamentSquadEntry.objects.filter(pk=squad_entry.pk).exists())
        self.assertFalse(GuardianLink.objects.filter(player_id=player_id).exists())
        delete_photo.assert_called_once_with('player-photos/john.jpg')
        self.assertTrue(
            GuardianLink.objects.filter(guardian=self.guardian, player=self.sibling).exists()
        )
        self.firebase_delete.assert_not_called()
        self.assertTrue(
            AuditLog.objects.filter(action='player.deleted', target=str(player_id)).exists()
        )

    def test_deleting_last_player_does_not_delete_guardian(self):
        GuardianLink.objects.filter(player=self.sibling).delete()
        response = self.client.delete(self.url('players', self.player))
        self.assertEqual(response.status_code, 204)
        self.guardian.refresh_from_db()
        self.assertTrue(self.guardian.is_active)
        self.assertTrue(User.objects.filter(pk=self.guardian.pk).exists())

    def test_guardian_deletion_is_blocked_while_players_are_linked(self):
        response = self.client.delete(self.url('guardians', self.guardian))
        self.assertEqual(response.status_code, 409, response.data)
        self.assertEqual(response.data['code'], 'guardian_has_linked_players')
        self.assertEqual(response.data['linkedPlayerCount'], 2)
        self.guardian.refresh_from_db()
        self.assertTrue(self.guardian.is_active)
        self.assertEqual(self.guardian.firebase_uid, 'firebase-guardian')
        self.firebase_delete.assert_not_called()

    def test_unlinked_guardian_is_retired_and_firebase_identity_deleted(self):
        GuardianLink.objects.filter(guardian=self.guardian).delete()
        response = self.client.delete(self.url('guardians', self.guardian))
        self.assertEqual(response.status_code, 204, response.data)
        self.guardian.refresh_from_db()
        self.assertFalse(self.guardian.is_active)
        self.assertIsNone(self.guardian.firebase_uid)
        self.firebase_delete.assert_called_once_with('firebase-guardian')

    def test_firebase_failure_is_queued_after_local_access_is_revoked(self):
        GuardianLink.objects.filter(guardian=self.guardian).delete()
        self.firebase_delete.side_effect = RuntimeError('Firebase unavailable')
        response = self.client.delete(self.url('guardians', self.guardian))
        self.assertEqual(response.status_code, 204, response.data)
        self.guardian.refresh_from_db()
        self.assertFalse(self.guardian.is_active)
        self.assertTrue(
            FirebaseProvisioningCleanup.objects.filter(
                firebase_uid='firebase-guardian'
            ).exists()
        )

    def test_coach_retirement_removes_it_from_directory(self):
        coach = self.user(
            'coach-delete',
            Roles.COACH,
            email='delete-coach@example.com',
            firebase_uid='firebase-coach',
        )
        response = self.client.delete(self.url('coaches', coach))
        self.assertEqual(response.status_code, 204, response.data)
        coach.refresh_from_db()
        self.assertFalse(coach.is_active)
        self.assertIsNone(coach.firebase_uid)
        self.firebase_delete.assert_called_once_with('firebase-coach')

        directory = self.client.get('/api/club-members/?role=COACH')
        self.assertEqual(directory.status_code, 200, directory.data)
        self.assertNotIn(str(coach.pk), [row['id'] for row in directory.data])

    def test_retired_player_disappears_from_roster_and_guardian_details(self):
        self.assertEqual(self.client.delete(self.url('players', self.player)).status_code, 204)
        roster = self.client.get('/api/players/')
        self.assertEqual(roster.status_code, 200, roster.data)
        self.assertNotIn(str(self.player.pk), [row['id'] for row in roster.data])

        guardian = self.client.get(self.url('guardians', self.guardian))
        self.assertEqual(guardian.status_code, 200, guardian.data)
        self.assertNotIn(
            str(self.player.pk),
            [row['id'] for row in guardian.data['linkedPeople']],
        )
