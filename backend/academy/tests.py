"""Academy API tests — RBAC, object-level authorization (BOLA), the JSON wire
contract the Flutter client parses, and the push-notification fan-out.

Firebase is never contacted: FirebaseAuthentication is bypassed with
force_authenticate, and the FCM SDK is mocked. Mirrors accounts/tests.py.
"""
from datetime import date, timedelta
from unittest.mock import patch

from django.urls import reverse
from rest_framework.test import APITestCase

from accounts.models import GuardianLink, Roles, User

from .models import (
    AgeTier,
    Attendance,
    AttendanceStatus,
    DeviceToken,
    Eligibility,
    PlayerProfile,
    SessionFocus,
    TrainingSession,
)


def make_user(role, email=None):
    email = email or f'{role.lower()}@footpathcebu.test'
    return User.objects.create(
        username=email, email=email, role=role,
        firebase_uid=f'uid-{email}',
    )


def make_player(email, tier=AgeTier.DEVELOPMENT, **kwargs):
    user = make_user(Roles.PLAYER, email=email)
    PlayerProfile.objects.create(
        user=user, age=kwargs.get('age', 15), class_year='Class of 2027',
        age_tier=tier, position=kwargs.get('position', 'CM'),
        pace=80, shooting=80, passing=80, dribbling=80, defending=80, physical=80,
        eligibility=Eligibility.ELIGIBLE,
    )
    return user


class SquadEndpointTests(APITestCase):
    def setUp(self):
        self.coach = make_user(Roles.COACH)
        self.player = make_player('p1@footpathcebu.test')

    def test_coach_can_list_squad(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.get(reverse('players-list'))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 1)

    def test_non_coach_roles_are_denied(self):
        for role in (Roles.PLAYER, Roles.GUARDIAN, Roles.SCHOOL_STAFF):
            self.client.force_authenticate(make_user(role, f'{role}@x.test'))
            self.assertEqual(
                self.client.get(reverse('players-list')).status_code, 403,
                msg=f'{role} should not see the squad',
            )

    def test_player_json_matches_flutter_contract(self):
        """PlayerSerializer must emit exactly the keys Player.fromJson reads."""
        self.client.force_authenticate(self.coach)
        row = self.client.get(reverse('players-list')).data[0]
        self.assertEqual(
            set(row.keys()),
            {'id', 'name', 'age', 'classYear', 'ageTier', 'position',
             'ratings', 'eligibility', 'photoUrl'},
        )
        self.assertEqual(
            set(row['ratings'].keys()),
            {'pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical'},
        )
        # id is a string (client does json['id'].toString(), and attendance
        # keys off the same value as a hard String).
        self.assertIsInstance(row['id'], str)
        self.assertEqual(row['ageTier'], 'DEVELOPMENT')  # uppercase wire value


class MyProfileTests(APITestCase):
    def test_player_reads_own_profile_only(self):
        player = make_player('me@footpathcebu.test')
        self.client.force_authenticate(player)
        resp = self.client.get(reverse('players-me'))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data['id'], str(player.id))

    def test_non_player_denied(self):
        self.client.force_authenticate(make_user(Roles.COACH))
        self.assertEqual(self.client.get(reverse('players-me')).status_code, 403)


class LinkedPlayersTests(APITestCase):
    def test_guardian_sees_only_linked_children(self):
        guardian = make_user(Roles.GUARDIAN)
        mine = make_player('mine@footpathcebu.test')
        make_player('other@footpathcebu.test')  # not linked
        GuardianLink.objects.create(guardian=guardian, player=mine)

        self.client.force_authenticate(guardian)
        resp = self.client.get(reverse('players-linked'))
        self.assertEqual(resp.status_code, 200)
        ids = {r['id'] for r in resp.data}
        self.assertEqual(ids, {str(mine.id)})


class AttendanceAuthorizationTests(APITestCase):
    """F3 — object-level authz: a guardian may only read a linked player."""

    def setUp(self):
        self.guardian = make_user(Roles.GUARDIAN)
        self.my_child = make_player('child@footpathcebu.test')
        self.other_child = make_player('other@footpathcebu.test')
        GuardianLink.objects.create(guardian=self.guardian, player=self.my_child)
        Attendance.objects.create(
            player=self.my_child, status=AttendanceStatus.PRESENT
        )
        Attendance.objects.create(
            player=self.other_child, status=AttendanceStatus.PRESENT
        )

    def _url(self, player_id):
        return f"{reverse('attendance-list')}?player={player_id}"

    def test_guardian_can_read_linked_child(self):
        self.client.force_authenticate(self.guardian)
        resp = self.client.get(self._url(self.my_child.id))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(resp.data[0]['playerId'], str(self.my_child.id))

    def test_guardian_cannot_read_unlinked_child(self):
        self.client.force_authenticate(self.guardian)
        resp = self.client.get(self._url(self.other_child.id))
        self.assertEqual(resp.status_code, 403)

    def test_player_cannot_read_another_player(self):
        self.client.force_authenticate(self.other_child)
        resp = self.client.get(self._url(self.my_child.id))
        self.assertEqual(resp.status_code, 403)

    def test_coach_can_read_any_player(self):
        self.client.force_authenticate(make_user(Roles.COACH))
        resp = self.client.get(self._url(self.my_child.id))
        self.assertEqual(resp.status_code, 200)

    def test_attendance_json_matches_flutter_contract(self):
        self.client.force_authenticate(make_user(Roles.COACH))
        row = self.client.get(self._url(self.my_child.id)).data[0]
        self.assertEqual(
            set(row.keys()),
            {'playerId', 'status', 'updatedAt', 'sessionName', 'coachUid'},
        )


class AssessmentTests(APITestCase):
    def setUp(self):
        self.coach = make_user(Roles.COACH)
        self.player = make_player('p@footpathcebu.test')

    def test_coach_updates_ratings(self):
        self.client.force_authenticate(self.coach)
        url = reverse('player-assessment', args=[self.player.id])
        resp = self.client.put(
            url, {'ratings': {'pace': 90, 'shooting': 91, 'passing': 92,
                              'dribbling': 93, 'defending': 94, 'physical': 95}},
            format='json',
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data['ratings']['pace'], 90)
        self.player.player_profile.refresh_from_db()
        self.assertEqual(self.player.player_profile.shooting, 91)

    def test_non_coach_cannot_assess(self):
        self.client.force_authenticate(make_user(Roles.GUARDIAN))
        url = reverse('player-assessment', args=[self.player.id])
        self.assertEqual(self.client.put(url, {}, format='json').status_code, 403)

    def test_rating_out_of_range_rejected(self):
        self.client.force_authenticate(self.coach)
        url = reverse('player-assessment', args=[self.player.id])
        resp = self.client.put(
            url, {'ratings': {'pace': 200, 'shooting': 0, 'passing': 0,
                              'dribbling': 0, 'defending': 0, 'physical': 0}},
            format='json',
        )
        self.assertEqual(resp.status_code, 400)


class TrainingSessionTests(APITestCase):
    def setUp(self):
        self.coach = make_user(Roles.COACH)

    def _payload(self):
        return {
            'title': 'Evening Training',
            'date': str(date.today() + timedelta(days=1)),
            'startTime': '04:30 PM', 'endTime': '06:00 PM',
            'location': 'Cebu City Sports Complex', 'focus': 'TECHNICAL',
            'ageTiers': ['DEVELOPMENT', 'PATHWAY'],
        }

    @patch('academy.views.notify_session_scheduled')
    def test_coach_creates_session(self, _mock_notify):
        self.client.force_authenticate(self.coach)
        resp = self.client.post(
            reverse('training-sessions'), self._payload(), format='json'
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data['ageTiers'], ['DEVELOPMENT', 'PATHWAY'])
        self.assertEqual(resp.data['attendeeCount'], 0)

    def test_non_coach_cannot_create(self):
        self.client.force_authenticate(make_user(Roles.PLAYER))
        resp = self.client.post(
            reverse('training-sessions'), self._payload(), format='json'
        )
        self.assertEqual(resp.status_code, 403)

    def test_session_without_tier_rejected(self):
        self.client.force_authenticate(self.coach)
        payload = self._payload()
        payload['ageTiers'] = []
        resp = self.client.post(
            reverse('training-sessions'), payload, format='json'
        )
        self.assertEqual(resp.status_code, 400)

    def test_any_authenticated_user_can_list(self):
        TrainingSession.objects.create(
            title='X', date=date.today(), age_tiers=['DEVELOPMENT'],
            focus=SessionFocus.TECHNICAL,
        )
        self.client.force_authenticate(make_user(Roles.GUARDIAN))
        resp = self.client.get(reverse('training-sessions'))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 1)


class DeviceRegistrationTests(APITestCase):
    def test_upsert_by_token(self):
        user = make_user(Roles.PLAYER)
        self.client.force_authenticate(user)
        for _ in range(2):  # idempotent
            resp = self.client.post(
                reverse('devices'), {'token': 'abc', 'platform': 'android'},
                format='json',
            )
            self.assertEqual(resp.status_code, 204)
        self.assertEqual(DeviceToken.objects.filter(token='abc').count(), 1)

    def test_token_required(self):
        self.client.force_authenticate(make_user(Roles.PLAYER))
        resp = self.client.post(reverse('devices'), {}, format='json')
        self.assertEqual(resp.status_code, 400)


class PhotoUploadTests(APITestCase):
    def setUp(self):
        self.admin = make_user(Roles.ADMIN)
        self.player = make_player('p@footpathcebu.test')

    def _upload(self):
        from io import BytesIO
        return {'photo': BytesIO(b'\xff\xd8\xfffakejpeg')}

    def test_non_admin_cannot_upload(self):
        self.client.force_authenticate(make_user(Roles.COACH))
        url = reverse('player-photo-upload', args=[self.player.id])
        resp = self.client.post(url, self._upload(), format='multipart')
        self.assertEqual(resp.status_code, 403)

    @patch('academy.views.upload_photo')
    def test_admin_upload_stores_path(self, mock_upload):
        mock_upload.return_value = f'player-photos/{self.player.id}.jpg'
        self.client.force_authenticate(self.admin)
        url = reverse('player-photo-upload', args=[self.player.id])
        resp = self.client.post(url, self._upload(), format='multipart')
        self.assertEqual(resp.status_code, 200)
        self.player.player_profile.refresh_from_db()
        self.assertEqual(
            self.player.player_profile.photo_path,
            f'player-photos/{self.player.id}.jpg',
        )

    def test_missing_file_rejected(self):
        self.client.force_authenticate(self.admin)
        url = reverse('player-photo-upload', args=[self.player.id])
        resp = self.client.post(url, {}, format='multipart')
        self.assertEqual(resp.status_code, 400)


class NotificationFanOutTests(APITestCase):
    """The session-scheduled push targets players in the session's tiers plus
    their linked guardians — and nobody else."""

    @patch('academy.notifications.ensure_initialized')
    @patch('academy.notifications.messaging')
    def test_recipients_are_targeted_players_and_their_guardians(
        self, mock_messaging, _mock_init
    ):
        from academy.notifications import notify_session_scheduled

        dev_player = make_player('dev@x.test', tier=AgeTier.DEVELOPMENT)
        found_player = make_player('found@x.test', tier=AgeTier.FOUNDATION)
        guardian = make_user(Roles.GUARDIAN)
        GuardianLink.objects.create(guardian=guardian, player=dev_player)

        # Everyone has a device token registered.
        for i, u in enumerate((dev_player, found_player, guardian)):
            DeviceToken.objects.create(user=u, token=f't{i}', platform='android')

        # A multicast "success" response for however many tokens are sent.
        def _fake_send(msg):
            class _R:
                success_count = len(msg.tokens)
                responses = [type('x', (), {'success': True, 'exception': None})()
                             for _ in msg.tokens]
            return _R()

        mock_messaging.send_each_for_multicast.side_effect = _fake_send
        mock_messaging.MulticastMessage.side_effect = \
            lambda **kw: type('M', (), kw)()
        mock_messaging.Notification.side_effect = lambda **kw: kw

        session = TrainingSession.objects.create(
            title='Dev only', date=date.today(), age_tiers=[AgeTier.DEVELOPMENT],
            focus=SessionFocus.TECHNICAL,
        )
        sent = notify_session_scheduled(session)

        # dev_player + its guardian = 2 tokens. Foundation player excluded.
        self.assertEqual(sent, 2)
        sent_tokens = set(
            mock_messaging.send_each_for_multicast.call_args[0][0].tokens
        )
        self.assertEqual(sent_tokens, {'t0', 't2'})
