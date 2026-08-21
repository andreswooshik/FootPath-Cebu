from datetime import date, timedelta
from types import SimpleNamespace
from unittest.mock import patch

from django.core.exceptions import ValidationError
from django.core.management import call_command
from django.forms import modelform_factory
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APITestCase

from accounts.models import Club, GuardianLink, Roles, User

from .models import (
    AgeTier,
    Attendance,
    AttendanceStatus,
    PlayerProfile,
    SessionFocus,
    TrainingSession,
)
from .serializers import TrainingSessionSerializer
from .views import _in_same_club


def _user(email, role, club=None):
    return User.objects.create(
        username=email,
        email=email,
        role=role,
        club=club,
        firebase_uid=f'uid-{email}',
    )


def _player(email, club):
    user = _user(email, Roles.PLAYER, club)
    PlayerProfile.objects.create(
        user=user,
        age=14,
        age_tier=AgeTier.DEVELOPMENT,
        position='CM',
    )
    return user


class SeedCommandPlayerInvariantTests(TestCase):
    @patch('accounts.management.commands.seed_users.ensure_initialized')
    @patch('accounts.management.commands.seed_users.firebase_auth.create_user')
    def test_seed_users_is_idempotent_and_creates_a_complete_player(
        self, create_firebase_user, _ensure_initialized,
    ):
        create_firebase_user.side_effect = lambda **kwargs: SimpleNamespace(
            uid=f'uid-{kwargs["email"]}'
        )

        call_command('seed_users', verbosity=0)
        call_command('seed_users', verbosity=0)

        player = User.objects.get(email='player@footpathcebu.test')
        self.assertEqual(player.role, Roles.PLAYER)
        self.assertIsNotNone(player.club_id)
        self.assertTrue(player.club.is_active)
        self.assertEqual(
            PlayerProfile.objects.filter(user=player).count(), 1
        )
        for member in User.objects.exclude(role=Roles.ADMIN):
            self.assertIsNotNone(member.club_id)
            self.assertTrue(member.club.is_active)

    def test_seed_academy_repairs_legacy_seed_rows_and_is_idempotent(self):
        coach = _user('coach@footpathcebu.test', Roles.COACH)
        login_player = _user('player@footpathcebu.test', Roles.PLAYER)
        guardian = _user('guardian@footpathcebu.test', Roles.GUARDIAN)

        call_command('seed_academy', verbosity=0)
        call_command('seed_academy', verbosity=0)

        players = User.objects.filter(role=Roles.PLAYER)
        self.assertGreater(players.count(), 1)
        for player in players.select_related('club'):
            self.assertIsNotNone(player.club_id)
            self.assertTrue(player.club.is_active)
            self.assertEqual(
                PlayerProfile.objects.filter(user=player).count(), 1
            )
        coach.refresh_from_db()
        login_player.refresh_from_db()
        guardian.refresh_from_db()
        self.assertEqual(coach.club_id, login_player.club_id)
        self.assertEqual(guardian.club_id, login_player.club_id)
        self.assertTrue(GuardianLink.objects.filter(
            guardian=guardian, player=login_player,
        ).exists())


class SquadProgressScopeTests(APITestCase):
    def setUp(self):
        self.club_a = Club.objects.create(
            name='Progress A', slug='progress-a', is_active=True,
        )
        self.club_b = Club.objects.create(
            name='Progress B', slug='progress-b', is_active=True,
        )
        self.admin = _user('progress-admin@test.test', Roles.ADMIN)
        self.coach = _user(
            'progress-coach@test.test', Roles.COACH, self.club_a,
        )
        self.player_a = _player('progress-a@test.test', self.club_a)
        self.player_b = _player('progress-b@test.test', self.club_b)
        session_a = TrainingSession.objects.create(
            title='Progress session A',
            date=date.today(),
            age_tiers=[AgeTier.DEVELOPMENT],
            focus=SessionFocus.TECHNICAL,
            club=self.club_a,
        )
        session_b = TrainingSession.objects.create(
            title='Progress session B',
            date=date.today(),
            age_tiers=[AgeTier.DEVELOPMENT],
            focus=SessionFocus.TECHNICAL,
            club=self.club_b,
        )
        Attendance.objects.create(
            player=self.player_a,
            session=session_a,
            status=AttendanceStatus.PRESENT,
            effort=80,
        )
        Attendance.objects.create(
            player=self.player_b,
            session=session_b,
            status=AttendanceStatus.PRESENT,
            effort=90,
        )

    def test_super_admin_sees_progress_from_all_clubs(self):
        self.client.force_authenticate(self.admin)

        response = self.client.get(reverse('progress-squad'))

        self.assertEqual(response.status_code, 200)
        rows = {row['id']: row for row in response.data}
        self.assertEqual(
            set(rows), {str(self.player_a.id), str(self.player_b.id)}
        )
        self.assertEqual(rows[str(self.player_a.id)]['avgEffort'], 80)
        self.assertEqual(rows[str(self.player_b.id)]['avgEffort'], 90)

    def test_coach_remains_scoped_to_own_club(self):
        self.client.force_authenticate(self.coach)

        response = self.client.get(reverse('progress-squad'))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            {row['id'] for row in response.data}, {str(self.player_a.id)}
        )


class NullClubTenantIsolationTests(APITestCase):
    def setUp(self):
        self.admin = _user('null-admin@test.test', Roles.ADMIN)
        self.coach = _user('null-coach@test.test', Roles.COACH)
        self.player = _player('null-player@test.test', club=None)
        self.session = TrainingSession.objects.create(
            title='Legacy null-club session',
            date=date.today(),
            age_tiers=[AgeTier.DEVELOPMENT],
        )

    def test_null_requester_club_never_matches_null_target_club(self):
        self.assertFalse(_in_same_club(self.coach, self.player.pk))

        self.client.force_authenticate(self.coach)
        response = self.client.get(
            reverse('player-detail', args=[self.player.pk])
        )

        self.assertEqual(response.status_code, 403)

    def test_null_club_coach_cannot_manage_or_list_legacy_null_session(self):
        self.client.force_authenticate(self.coach)

        listed = self.client.get(reverse('training-sessions'))
        updated = self.client.put(
            reverse('training-session-detail', args=[self.session.pk]),
            {},
            format='json',
        )

        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.data, [])
        self.assertEqual(updated.status_code, 403)

    def test_super_admin_keeps_intentional_cross_club_read_access(self):
        self.client.force_authenticate(self.admin)

        player = self.client.get(
            reverse('player-detail', args=[self.player.pk])
        )
        sessions = self.client.get(reverse('training-sessions'))

        self.assertEqual(player.status_code, 200)
        self.assertEqual(sessions.status_code, 200)
        self.assertIn(
            str(self.session.pk), {row['id'] for row in sessions.data}
        )


class TrainingSessionTimeValidationTests(TestCase):
    def _payload(self, **overrides):
        payload = {
            'title': 'Time validation',
            'date': str(date.today() + timedelta(days=1)),
            'startTime': '04:30 PM',
            'endTime': '06:00 PM',
            'location': 'Cebu',
            'focus': SessionFocus.TECHNICAL,
            'ageTiers': [AgeTier.DEVELOPMENT],
        }
        payload.update(overrides)
        return payload

    def test_serializer_accepts_and_normalizes_supported_12_hour_time(self):
        serializer = TrainingSessionSerializer(data=self._payload(
            startTime='4:30 pm', endTime='6:00 PM',
        ))

        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(serializer.validated_data['start_time'], '04:30 PM')
        self.assertEqual(serializer.validated_data['end_time'], '06:00 PM')

    def test_serializer_requires_start_and_end_as_a_pair(self):
        serializer = TrainingSessionSerializer(data=self._payload(endTime=''))

        self.assertFalse(serializer.is_valid())
        self.assertIn('endTime', serializer.errors)

    def test_serializer_rejects_malformed_and_inverted_times(self):
        malformed = TrainingSessionSerializer(data=self._payload(
            startTime='16:30',
        ))
        inverted = TrainingSessionSerializer(data=self._payload(
            startTime='06:00 PM', endTime='04:30 PM',
        ))
        equal = TrainingSessionSerializer(data=self._payload(
            startTime='06:00 PM', endTime='06:00 PM',
        ))

        self.assertFalse(malformed.is_valid())
        self.assertIn('startTime', malformed.errors)
        self.assertFalse(inverted.is_valid())
        self.assertIn('endTime', inverted.errors)
        self.assertFalse(equal.is_valid())
        self.assertIn('endTime', equal.errors)

    def test_partial_update_validates_against_existing_other_time(self):
        session = TrainingSession.objects.create(
            title='Existing time window',
            date=date.today(),
            start_time='04:30 PM',
            end_time='06:00 PM',
            age_tiers=[AgeTier.DEVELOPMENT],
        )
        serializer = TrainingSessionSerializer(
            session, data={'startTime': '07:00 PM'}, partial=True,
        )

        self.assertFalse(serializer.is_valid())
        self.assertIn('endTime', serializer.errors)

    def test_direct_orm_create_enforces_time_order(self):
        with self.assertRaises(ValidationError) as raised:
            TrainingSession.objects.create(
                title='Invalid ORM time window',
                date=date.today(),
                start_time='06:00 PM',
                end_time='04:30 PM',
                age_tiers=[AgeTier.DEVELOPMENT],
            )
        self.assertIn('end_time', raised.exception.message_dict)

    def test_model_form_enforces_time_order_for_admin_style_writes(self):
        form_class = modelform_factory(
            TrainingSession,
            fields=['title', 'date', 'start_time', 'end_time'],
        )
        form = form_class(data={
            'title': 'Invalid form time window',
            'date': str(date.today()),
            'start_time': '06:00 PM',
            'end_time': '04:30 PM',
        })

        self.assertFalse(form.is_valid())
        self.assertIn('end_time', form.errors)
