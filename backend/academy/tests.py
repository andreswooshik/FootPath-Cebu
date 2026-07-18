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
    ConfirmationStatus,
    DeviceToken,
    Dispute,
    DisputeCategory,
    DisputeResponse,
    DisputeStatus,
    Eligibility,
    EligibilityHistory,
    InjuryRecord,
    InjuryStatus,
    PlayerEligibility,
    PlayerProfile,
    SessionConfirmation,
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
            {'playerId', 'sessionId', 'status', 'effort', 'note',
             'updatedAt', 'sessionName', 'coachUid'},
        )


class SessionAttendanceTests(APITestCase):
    """The coach roll-call endpoint: GET coach/admin, POST coach-only with
    replace-this-session upsert semantics."""

    def setUp(self):
        self.coach = make_user(Roles.COACH)
        self.p1 = make_player('p1@footpathcebu.test')
        self.p2 = make_player('p2@footpathcebu.test')
        self.session = TrainingSession.objects.create(
            title='Evening Training', date=date.today(),
            age_tiers=[AgeTier.DEVELOPMENT], focus=SessionFocus.TECHNICAL,
        )

    def _url(self):
        return reverse('attendance-session', args=[self.session.id])

    def _payload(self):
        return {'records': [
            {'playerId': str(self.p1.id), 'status': 'PRESENT',
             'effort': 85, 'note': 'Sharp in the final third.'},
            {'playerId': str(self.p2.id), 'status': 'ABSENT'},
        ]}

    def test_coach_post_then_get_round_trip(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.post(self._url(), self._payload(), format='json')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 2)

        resp = self.client.get(self._url())
        self.assertEqual(resp.status_code, 200)
        by_player = {r['playerId']: r for r in resp.data}
        p1_row = by_player[str(self.p1.id)]
        self.assertEqual(p1_row['status'], 'PRESENT')
        self.assertEqual(p1_row['effort'], 85)
        self.assertEqual(p1_row['note'], 'Sharp in the final third.')
        self.assertEqual(p1_row['sessionId'], str(self.session.id))
        self.assertEqual(p1_row['coachUid'], self.coach.firebase_uid)
        p2_row = by_player[str(self.p2.id)]
        self.assertEqual(p2_row['status'], 'ABSENT')
        self.assertIsNone(p2_row['effort'])
        self.assertIsNone(p2_row['note'])

    def test_resubmit_replaces_not_duplicates(self):
        self.client.force_authenticate(self.coach)
        self.client.post(self._url(), self._payload(), format='json')

        # Resubmit with p1 corrected and p2 dropped entirely.
        resp = self.client.post(self._url(), {'records': [
            {'playerId': str(self.p1.id), 'status': 'EXCUSED'},
        ]}, format='json')
        self.assertEqual(resp.status_code, 200)

        records = Attendance.objects.filter(session=self.session)
        self.assertEqual(records.count(), 1)
        self.assertEqual(records.get().player_id, self.p1.id)
        self.assertEqual(records.get().status, AttendanceStatus.EXCUSED)

    def test_non_coach_post_denied(self):
        for role in (Roles.PLAYER, Roles.GUARDIAN, Roles.SCHOOL_STAFF, Roles.ADMIN):
            self.client.force_authenticate(make_user(role, f'{role}@x.test'))
            resp = self.client.post(self._url(), self._payload(), format='json')
            self.assertEqual(
                resp.status_code, 403,
                msg=f'{role} should not record attendance',
            )

    def test_admin_can_get_but_others_cannot(self):
        self.client.force_authenticate(make_user(Roles.ADMIN))
        self.assertEqual(self.client.get(self._url()).status_code, 200)
        for role in (Roles.PLAYER, Roles.GUARDIAN, Roles.SCHOOL_STAFF):
            self.client.force_authenticate(make_user(role, f'{role}@g.test'))
            self.assertEqual(self.client.get(self._url()).status_code, 403)

    def test_session_attendance_json_matches_flutter_contract(self):
        self.client.force_authenticate(self.coach)
        self.client.post(self._url(), self._payload(), format='json')
        row = self.client.get(self._url()).data[0]
        self.assertEqual(
            set(row.keys()),
            {'playerId', 'sessionId', 'status', 'effort', 'note',
             'updatedAt', 'sessionName', 'coachUid'},
        )

    def test_invalid_status_rejected(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.post(self._url(), {'records': [
            {'playerId': str(self.p1.id), 'status': 'LATE'},
        ]}, format='json')
        self.assertEqual(resp.status_code, 400)

    def test_out_of_range_effort_rejected(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.post(self._url(), {'records': [
            {'playerId': str(self.p1.id), 'status': 'PRESENT', 'effort': 101},
        ]}, format='json')
        self.assertEqual(resp.status_code, 400)

    def test_unknown_player_rejected(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.post(self._url(), {'records': [
            {'playerId': '999999', 'status': 'PRESENT'},
        ]}, format='json')
        self.assertEqual(resp.status_code, 400)

    def test_unknown_session_404(self):
        self.client.force_authenticate(self.coach)
        url = reverse('attendance-session', args=[999999])
        self.assertEqual(self.client.get(url).status_code, 404)
        self.assertEqual(
            self.client.post(url, self._payload(), format='json').status_code, 404
        )

    def _post_to_session_dated(self, when):
        session = TrainingSession.objects.create(
            title=f'session {when}', date=when,
            age_tiers=[AgeTier.DEVELOPMENT], focus=SessionFocus.TECHNICAL,
        )
        url = reverse('attendance-session', args=[session.id])
        return self.client.post(url, self._payload(), format='json')

    def test_attendance_window_is_session_day_through_two_days_after(self):
        # Open: the session day and up to two days after.
        self.client.force_authenticate(self.coach)
        for offset in (0, 1, 2):
            when = date.today() - timedelta(days=offset)
            self.assertEqual(
                self._post_to_session_dated(when).status_code, 200,
                msg=f'{offset} day(s) after should be open',
            )

    def test_attendance_closed_before_session_and_after_two_days(self):
        # Closed: before the session, and more than two days after.
        self.client.force_authenticate(self.coach)
        for when in (date.today() + timedelta(days=1),
                     date.today() - timedelta(days=3)):
            self.assertEqual(
                self._post_to_session_dated(when).status_code, 400, msg=str(when),
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


class DisputeTests(APITestCase):
    """The dispute foundation — coach flags, School Staff/Admin participate,
    players/guardians have no access, and the response thread is the
    append-only audit trail."""

    def setUp(self):
        self.coach = make_user(Roles.COACH)
        self.staff = make_user(Roles.SCHOOL_STAFF)
        self.admin = make_user(Roles.ADMIN)
        self.player = make_player('p1@footpathcebu.test')
        self.dispute = Dispute.objects.create(
            raised_by=self.coach,
            subject_player=self.player,
            category=DisputeCategory.ATTENDANCE,
            summary='Attendance mark disputed',
            detail='Player claims they were present on July 10.',
        )

    def _payload(self):
        return {
            'subjectPlayerId': str(self.player.id),
            'category': 'ASSESSMENT',
            'summary': 'Rating query',
            'detail': 'Guardian questioned the last assessment.',
        }

    def test_coach_creates_dispute(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.post(reverse('disputes'), self._payload(), format='json')
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data['status'], 'OPEN')
        self.assertEqual(resp.data['subjectPlayerId'], str(self.player.id))
        # raised_by is the request user, never client-supplied.
        dispute = Dispute.objects.get(pk=resp.data['id'])
        self.assertEqual(dispute.raised_by, self.coach)

    def test_dispute_without_subject_player_allowed(self):
        self.client.force_authenticate(self.coach)
        payload = self._payload()
        del payload['subjectPlayerId']
        resp = self.client.post(reverse('disputes'), payload, format='json')
        self.assertEqual(resp.status_code, 201)
        self.assertIsNone(resp.data['subjectPlayerId'])

    def test_player_and_guardian_denied(self):
        guardian = make_user(Roles.GUARDIAN)
        GuardianLink.objects.create(guardian=guardian, player=self.player)
        for user in (self.player, guardian):
            self.client.force_authenticate(user)
            self.assertEqual(self.client.get(reverse('disputes')).status_code, 403)
            self.assertEqual(
                self.client.get(
                    reverse('dispute-detail', args=[self.dispute.id])
                ).status_code, 403,
            )
            self.assertEqual(
                self.client.post(
                    reverse('disputes'), self._payload(), format='json'
                ).status_code, 403,
            )
            self.assertEqual(
                self.client.post(
                    reverse('dispute-responses', args=[self.dispute.id]),
                    {'body': 'hi'}, format='json',
                ).status_code, 403,
            )

    def test_staff_and_admin_list_but_cannot_create(self):
        for user in (self.staff, self.admin):
            self.client.force_authenticate(user)
            resp = self.client.get(reverse('disputes'))
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(len(resp.data), 1)
            self.assertEqual(
                self.client.post(
                    reverse('disputes'), self._payload(), format='json'
                ).status_code, 403,
                msg=f'{user.role} must not raise disputes',
            )

    def test_response_with_status_change_moves_the_dispute(self):
        self.client.force_authenticate(self.staff)
        resp = self.client.post(
            reverse('dispute-responses', args=[self.dispute.id]),
            {'body': 'Reviewed the sign-in sheet; correcting the record.',
             'statusChangeTo': 'RESOLVED'},
            format='json',
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data['status'], 'RESOLVED')
        self.dispute.refresh_from_db()
        self.assertEqual(self.dispute.status, DisputeStatus.RESOLVED)
        response = self.dispute.responses.get()
        self.assertEqual(response.author, self.staff)
        self.assertEqual(response.status_change_to, DisputeStatus.RESOLVED)

    def test_response_without_status_change_leaves_status(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.post(
            reverse('dispute-responses', args=[self.dispute.id]),
            {'body': 'Adding context: the drill list from that day.'},
            format='json',
        )
        self.assertEqual(resp.status_code, 201)
        self.dispute.refresh_from_db()
        self.assertEqual(self.dispute.status, DisputeStatus.OPEN)

    def test_invalid_category_and_status_rejected(self):
        self.client.force_authenticate(self.coach)
        payload = self._payload() | {'category': 'VIBES'}
        self.assertEqual(
            self.client.post(reverse('disputes'), payload, format='json')
            .status_code, 400,
        )
        self.assertEqual(
            self.client.post(
                reverse('dispute-responses', args=[self.dispute.id]),
                {'body': 'x', 'statusChangeTo': 'MAYBE'}, format='json',
            ).status_code, 400,
        )

    def test_dispute_json_matches_flutter_contract(self):
        DisputeResponse.objects.create(
            dispute=self.dispute, author=self.staff, body='Looking into it.',
            status_change_to=DisputeStatus.UNDER_REVIEW,
        )
        self.client.force_authenticate(self.coach)
        row = self.client.get(reverse('disputes')).data[0]
        self.assertEqual(
            set(row.keys()),
            {'id', 'raisedByName', 'subjectPlayerId', 'subjectPlayerName',
             'category', 'status', 'summary', 'detail', 'createdAt',
             'updatedAt', 'responses'},
        )
        self.assertEqual(
            set(row['responses'][0].keys()),
            {'id', 'authorName', 'authorRole', 'body', 'statusChangeTo',
             'createdAt'},
        )
        self.assertIsInstance(row['id'], str)


class InjuryRecordTests(APITestCase):
    """Injury CRUD — the player owns their records; coach/admin read-only;
    a guardian reads a linked child's records only (never writes, never an
    unlinked child): medical data, least-privilege."""

    def setUp(self):
        self.player = make_player('p1@footpathcebu.test')
        self.other_player = make_player('p2@footpathcebu.test')
        self.coach = make_user(Roles.COACH)
        self.guardian = make_user(Roles.GUARDIAN)
        GuardianLink.objects.create(guardian=self.guardian, player=self.player)
        self.record = InjuryRecord.objects.create(
            player=self.player, description='Sprained ankle',
            body_part='Left ankle', status=InjuryStatus.RECOVERING,
            occurred_on=date(2026, 7, 1), notes='Twisted landing from a header.',
        )

    def _detail(self, pk=None):
        return reverse('injury-detail', args=[pk or self.record.id])

    def _payload(self):
        return {
            'description': 'Hamstring strain', 'bodyPart': 'Right hamstring',
            'status': 'ACTIVE', 'occurredOn': '2026-07-10',
            'notes': 'Felt a pull during sprints.',
        }

    def test_player_creates_own_record(self):
        self.client.force_authenticate(self.player)
        resp = self.client.post(reverse('injuries'), self._payload(), format='json')
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data['playerId'], str(self.player.id))
        self.assertEqual(
            InjuryRecord.objects.filter(player=self.player).count(), 2
        )

    def test_player_lists_own_records_only(self):
        InjuryRecord.objects.create(
            player=self.other_player, description='Bruised knee',
            occurred_on=date(2026, 7, 5),
        )
        self.client.force_authenticate(self.player)
        resp = self.client.get(reverse('injuries'))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(resp.data[0]['playerId'], str(self.player.id))

    def test_player_updates_and_deletes_own_record(self):
        self.client.force_authenticate(self.player)
        resp = self.client.put(
            self._detail(), {'status': 'RECOVERED', 'resolvedOn': '2026-07-15'},
            format='json',
        )
        self.assertEqual(resp.status_code, 200)
        self.record.refresh_from_db()
        self.assertEqual(self.record.status, InjuryStatus.RECOVERED)
        self.assertEqual(self.record.resolved_on, date(2026, 7, 15))

        resp = self.client.delete(self._detail())
        self.assertEqual(resp.status_code, 204)
        self.assertFalse(InjuryRecord.objects.filter(pk=self.record.pk).exists())

    def test_player_cannot_touch_another_players_record(self):
        self.client.force_authenticate(self.other_player)
        self.assertEqual(self.client.get(self._detail()).status_code, 403)
        self.assertEqual(
            self.client.put(self._detail(), {}, format='json').status_code, 403
        )
        self.assertEqual(self.client.delete(self._detail()).status_code, 403)

    def test_coach_reads_all_but_cannot_write(self):
        self.client.force_authenticate(self.coach)
        resp = self.client.get(reverse('injuries'))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(self.client.get(self._detail()).status_code, 200)

        # Narrowing to one player works for the coach's profile view.
        resp = self.client.get(f"{reverse('injuries')}?player={self.player.id}")
        self.assertEqual(len(resp.data), 1)

        self.assertEqual(
            self.client.post(
                reverse('injuries'), self._payload(), format='json'
            ).status_code, 403,
        )
        self.assertEqual(
            self.client.put(
                self._detail(), {'status': 'RECOVERED'}, format='json'
            ).status_code, 403,
        )
        self.assertEqual(self.client.delete(self._detail()).status_code, 403)

    def test_guardian_reads_linked_child_only_and_never_writes(self):
        self.client.force_authenticate(self.guardian)
        # Must name a linked child — no blanket listing, no unlinked child.
        self.assertEqual(self.client.get(reverse('injuries')).status_code, 403)
        self.assertEqual(
            self.client.get(
                f"{reverse('injuries')}?player={self.other_player.id}"
            ).status_code, 403,
        )
        resp = self.client.get(
            f"{reverse('injuries')}?player={self.player.id}"
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(resp.data[0]['playerId'], str(self.player.id))
        # Detail read of the linked child's record works too.
        self.assertEqual(self.client.get(self._detail()).status_code, 200)
        # Writes stay player-only.
        self.assertEqual(
            self.client.post(
                reverse('injuries'), self._payload(), format='json'
            ).status_code, 403,
        )
        self.assertEqual(
            self.client.put(
                self._detail(), {'status': 'RECOVERED'}, format='json'
            ).status_code, 403,
        )
        self.assertEqual(self.client.delete(self._detail()).status_code, 403)

    def test_injury_json_matches_flutter_contract(self):
        self.client.force_authenticate(self.player)
        row = self.client.get(reverse('injuries')).data[0]
        self.assertEqual(
            set(row.keys()),
            {'id', 'playerId', 'description', 'bodyPart', 'status',
             'occurredOn', 'resolvedOn', 'notes', 'createdAt', 'updatedAt'},
        )
        self.assertIsInstance(row['id'], str)

    def test_invalid_status_rejected(self):
        self.client.force_authenticate(self.player)
        payload = self._payload() | {'status': 'BROKEN'}
        resp = self.client.post(reverse('injuries'), payload, format='json')
        self.assertEqual(resp.status_code, 400)


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


class PushTriggerTests(APITestCase):
    """The assessment-saved and eligibility-changed pushes target the player +
    linked guardians (and nobody else), fire only on real transitions, and
    only after commit."""

    def setUp(self):
        self.coach = make_user(Roles.COACH)
        self.player = make_player('p@footpathcebu.test')
        self.guardian = make_user(Roles.GUARDIAN)
        other_player = make_player('other@footpathcebu.test')  # not notified
        GuardianLink.objects.create(guardian=self.guardian, player=self.player)
        for i, u in enumerate((self.player, self.guardian, other_player)):
            DeviceToken.objects.create(user=u, token=f't{i}', platform='android')

    def _mock_send(self, mock_messaging):
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

    @patch('academy.notifications.ensure_initialized')
    @patch('academy.notifications.messaging')
    def test_assessment_put_notifies_player_and_guardian(
        self, mock_messaging, _mock_init
    ):
        self._mock_send(mock_messaging)
        self.client.force_authenticate(self.coach)
        url = reverse('player-assessment', args=[self.player.id])
        with self.captureOnCommitCallbacks(execute=True):
            resp = self.client.put(
                url, {'ratings': {'pace': 90, 'shooting': 91, 'passing': 92,
                                  'dribbling': 93, 'defending': 94,
                                  'physical': 95}},
                format='json',
            )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(mock_messaging.send_each_for_multicast.call_count, 1)
        sent = mock_messaging.send_each_for_multicast.call_args[0][0]
        self.assertEqual(set(sent.tokens), {'t0', 't1'})
        self.assertEqual(sent.data['type'], 'assessment_saved')

    @patch('academy.notifications.ensure_initialized')
    @patch('academy.notifications.messaging')
    def test_orm_eligibility_change_fires_regardless_of_write_path(
        self, mock_messaging, _mock_init
    ):
        self._mock_send(mock_messaging)
        profile = self.player.player_profile
        with self.captureOnCommitCallbacks(execute=True):
            profile.eligibility = Eligibility.ACADEMIC_WARNING
            profile.save()

        self.assertEqual(mock_messaging.send_each_for_multicast.call_count, 1)
        sent = mock_messaging.send_each_for_multicast.call_args[0][0]
        self.assertEqual(set(sent.tokens), {'t0', 't1'})
        self.assertEqual(sent.data['type'], 'eligibility_changed')
        self.assertEqual(sent.data['previous'], Eligibility.ELIGIBLE)

    @patch('academy.notifications.ensure_initialized')
    @patch('academy.notifications.messaging')
    def test_unchanged_eligibility_save_does_not_fire(
        self, mock_messaging, _mock_init
    ):
        self._mock_send(mock_messaging)
        profile = self.player.player_profile
        with self.captureOnCommitCallbacks(execute=True):
            profile.age = 16  # a save that leaves eligibility untouched
            profile.save()
        mock_messaging.send_each_for_multicast.assert_not_called()


class EligibilityHistorySignalTests(APITestCase):
    """Every eligibility transition writes exactly one append-only history row;
    non-transitions write none. Independent of the push — no device tokens, and
    the on_commit push never runs inside the test transaction."""

    def setUp(self):
        # make_player provisions the profile at ELIGIBLE (a create, not a
        # transition — so it records no history).
        self.player = make_player('hist@footpathcebu.test')
        self.staff = make_user(Roles.SCHOOL_STAFF)

    def test_change_records_a_history_row(self):
        self.assertFalse(EligibilityHistory.objects.exists())  # created ≠ change
        profile = self.player.player_profile
        profile._changed_by = self.staff
        profile.eligibility = Eligibility.ACADEMIC_WARNING
        profile.save()

        rows = EligibilityHistory.objects.filter(player=self.player)
        self.assertEqual(rows.count(), 1)
        row = rows.get()
        self.assertEqual(row.old_status, Eligibility.ELIGIBLE)
        self.assertEqual(row.new_status, Eligibility.ACADEMIC_WARNING)
        self.assertEqual(row.changed_by, self.staff)

    def test_unchanged_save_records_no_history(self):
        profile = self.player.player_profile
        profile.age = 16  # a save that leaves eligibility untouched
        profile.save()
        self.assertFalse(EligibilityHistory.objects.exists())

    def test_history_is_append_only_across_changes(self):
        profile = self.player.player_profile
        for status in (Eligibility.PENDING,
                       Eligibility.NOT_ELIGIBLE,
                       Eligibility.ELIGIBLE):
            profile.eligibility = status
            profile.save()
        rows = EligibilityHistory.objects.filter(player=self.player)
        self.assertEqual(rows.count(), 3)
        # Ordering is newest-first; the last transition lands on top.
        self.assertEqual(rows.first().new_status, Eligibility.ELIGIBLE)
        self.assertEqual(rows.first().old_status, Eligibility.NOT_ELIGIBLE)


class EligibilityHistoryEndpointTests(APITestCase):
    """GET /api/players/<id>/eligibility-history/ — object-scoped reads and the
    privacy-aware changedBy field."""

    def setUp(self):
        self.player = make_player('elig@footpathcebu.test')
        self.other_player = make_player('elig-other@footpathcebu.test')
        self.guardian = make_user(Roles.GUARDIAN)
        GuardianLink.objects.create(guardian=self.guardian, player=self.player)
        self.staff = make_user(Roles.SCHOOL_STAFF)
        self.staff.first_name, self.staff.last_name = 'Maria', 'Santos'
        self.staff.save()

        # One attributed transition + one system (actor unknown) transition.
        profile = self.player.player_profile
        profile._changed_by = self.staff
        profile.eligibility = Eligibility.ACADEMIC_WARNING
        profile.save()
        profile._changed_by = None
        profile.eligibility = Eligibility.ELIGIBLE
        profile.save()

    def _url(self, player_id=None):
        return reverse(
            'eligibility-history', args=[player_id or self.player.id]
        )

    def test_player_reads_own_history_newest_first(self):
        self.client.force_authenticate(self.player)
        resp = self.client.get(self._url())
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 2)
        self.assertEqual(resp.data[0]['newStatus'], Eligibility.ELIGIBLE)
        self.assertEqual(resp.data[1]['newStatus'], Eligibility.ACADEMIC_WARNING)
        self.assertEqual(
            set(resp.data[0].keys()),
            {'id', 'oldStatus', 'newStatus', 'changedAt', 'changedBy'},
        )

    def test_changed_by_is_role_only_for_families_full_name_for_staff(self):
        # Player (and guardian) see the role, never the staff member's name.
        self.client.force_authenticate(self.player)
        rows = self.client.get(self._url()).data
        self.assertEqual(rows[1]['changedBy'], 'School Staff')
        self.assertEqual(rows[0]['changedBy'], 'System')

        # School Staff see who actually made the change.
        self.client.force_authenticate(self.staff)
        rows = self.client.get(self._url()).data
        self.assertEqual(rows[1]['changedBy'], 'Maria Santos')

    def test_guardian_reads_linked_child_but_not_others(self):
        self.client.force_authenticate(self.guardian)
        self.assertEqual(self.client.get(self._url()).status_code, 200)
        self.assertEqual(
            self.client.get(self._url(self.other_player.id)).status_code, 403,
        )

    def test_player_cannot_read_another_players_history(self):
        self.client.force_authenticate(self.other_player)
        self.assertEqual(self.client.get(self._url()).status_code, 403)

    def test_staff_and_admin_read_any_coach_denied(self):
        for user, expected in (
            (self.staff, 200),
            (make_user(Roles.ADMIN), 200),
            (make_user(Roles.COACH), 403),
        ):
            self.client.force_authenticate(user)
            self.assertEqual(
                self.client.get(self._url()).status_code, expected, user.role,
            )

    def test_unknown_player_404(self):
        self.client.force_authenticate(self.staff)
        self.assertEqual(self.client.get(self._url(999999)).status_code, 404)


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


def _fake_provision(*, email, first_name, last_name, role):
    """Stand-in for accounts.services.provision_user that skips Firebase
    entirely but still creates a real local User row, so callers see the
    same (user, temp_password, note) shape the real function returns."""
    user = User.objects.create(
        username=email, email=email, first_name=first_name,
        last_name=last_name, role=role, firebase_uid=f'uid-{email}',
    )
    return user, 'TempPass123', 'New Firebase account created.'


class AdminCreatePlayerViewTests(APITestCase):
    """POST /api/admin/players/ — the console's Add Player flow: creates the
    User + PlayerProfile (with the now-required identity fields) together,
    and optionally a GuardianLink, all in one atomic call."""

    def setUp(self):
        self.admin = make_user(Roles.ADMIN)
        self.coach = make_user(Roles.COACH)
        self.guardian = make_user(Roles.GUARDIAN, email='g@footpathcebu.test')
        self.url = reverse('admin-player-create')

    def _payload(self, **overrides):
        payload = {
            'email': 'newplayer@footpathcebu.test',
            'first_name': 'Juan',
            'last_name': 'Dela Cruz',
            'middle_initial': 'S',
            'date_of_birth': '2012-05-04',
        }
        payload.update(overrides)
        return payload

    @patch('academy.views.provision_user', side_effect=_fake_provision)
    def test_admin_creates_player_with_profile_and_guardian(self, _mock):
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            self.url,
            self._payload(guardian_id=self.guardian.id),
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        user = User.objects.get(email='newplayer@footpathcebu.test')
        self.assertEqual(user.role, Roles.PLAYER)
        profile = PlayerProfile.objects.get(user=user)
        self.assertEqual(profile.middle_initial, 'S')
        self.assertEqual(str(profile.date_of_birth), '2012-05-04')
        self.assertTrue(
            GuardianLink.objects.filter(
                guardian=self.guardian, player=user
            ).exists()
        )
        self.assertEqual(response.data['temporary_password'], 'TempPass123')

    @patch('academy.views.provision_user', side_effect=_fake_provision)
    def test_guardian_is_optional(self, _mock):
        self.client.force_authenticate(self.admin)
        response = self.client.post(self.url, self._payload(), format='json')

        self.assertEqual(response.status_code, 201)
        self.assertEqual(GuardianLink.objects.count(), 0)

    @patch('academy.views.provision_user', side_effect=_fake_provision)
    def test_missing_required_field_creates_nothing(self, _mock):
        self.client.force_authenticate(self.admin)
        payload = self._payload()
        del payload['date_of_birth']
        response = self.client.post(self.url, payload, format='json')

        self.assertEqual(response.status_code, 400)
        self.assertFalse(
            User.objects.filter(email='newplayer@footpathcebu.test').exists()
        )
        self.assertFalse(PlayerProfile.objects.exists())

    @patch('academy.views.provision_user', side_effect=_fake_provision)
    def test_blank_name_is_rejected(self, _mock):
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            self.url, self._payload(first_name=''), format='json'
        )
        self.assertEqual(response.status_code, 400)

    def test_non_admin_denied(self):
        self.client.force_authenticate(self.coach)
        response = self.client.post(self.url, self._payload(), format='json')
        self.assertEqual(response.status_code, 403)

    @patch('accounts.services.ensure_initialized')
    @patch('accounts.services.firebase_auth')
    def test_duplicate_email_rejected(self, mock_firebase_auth, _mock_init):
        # Uses the REAL provision_user (only the Firebase SDK call is
        # mocked), since its email-uniqueness guard runs before Firebase is
        # ever touched — exactly the path this test exercises.
        make_user(Roles.PLAYER, email='newplayer@footpathcebu.test')
        self.client.force_authenticate(self.admin)
        response = self.client.post(self.url, self._payload(), format='json')

        self.assertEqual(response.status_code, 400)
        mock_firebase_auth.get_user_by_email.assert_not_called()
        self.assertFalse(PlayerProfile.objects.exists())


class AdminSiteRegistrationTests(APITestCase):
    """The Academy admin index is trimmed to Academic Eligibility, Disputes,
    and Injury records only — Attendances/Device tokens/Training
    sessions/the full Player profiles admin are hidden (players are created
    via the console's Add Player flow, not admin)."""

    def test_only_the_intended_models_are_registered(self):
        from django.contrib import admin as django_admin

        registered = set(django_admin.site._registry.keys())
        self.assertIn(PlayerEligibility, registered)
        self.assertIn(EligibilityHistory, registered)
        self.assertIn(Dispute, registered)
        self.assertIn(InjuryRecord, registered)
        self.assertNotIn(Attendance, registered)
        self.assertNotIn(DeviceToken, registered)
        self.assertNotIn(TrainingSession, registered)
        self.assertNotIn(PlayerProfile, registered)


class SessionConfirmationTests(APITestCase):
    """Player RSVPs: the player POSTs their own confirmation, it persists and is
    upserted on (player, session), and reads are object-scoped like attendance.
    This is the persistence the in-memory mock never gave — a confirmation now
    survives logout/restart and is readable by the coach.
    """

    def setUp(self):
        self.player = make_player('rsvp@footpathcebu.test')
        self.guardian = make_user(Roles.GUARDIAN)
        GuardianLink.objects.create(guardian=self.guardian, player=self.player)
        self.other = make_player('other-rsvp@footpathcebu.test')
        self.session = TrainingSession.objects.create(
            title='Evening Training', date=date.today(),
            age_tiers=[AgeTier.DEVELOPMENT], focus=SessionFocus.TECHNICAL,
        )

    def _url(self, player_id=None):
        base = reverse('session-confirmations')
        return f'{base}?player={player_id}' if player_id else base

    def test_player_confirms_and_it_persists(self):
        self.client.force_authenticate(self.player)
        resp = self.client.post(
            self._url(),
            {'sessionId': str(self.session.id), 'status': 'CONFIRMED'},
            format='json',
        )
        self.assertEqual(resp.status_code, 201)
        # Persisted server-side, and readable back on a fresh request.
        self.assertEqual(SessionConfirmation.objects.count(), 1)
        rows = self.client.get(self._url(self.player.id)).data
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['status'], 'CONFIRMED')

    def test_reconfirming_upserts_the_same_row(self):
        self.client.force_authenticate(self.player)
        body = {'sessionId': str(self.session.id), 'status': 'CONFIRMED'}
        self.client.post(self._url(), body, format='json')
        # Flip to declined — the same (player, session) row updates in place.
        self.client.post(
            self._url(),
            {'sessionId': str(self.session.id), 'status': 'DECLINED'},
            format='json',
        )
        self.assertEqual(SessionConfirmation.objects.count(), 1)
        row = SessionConfirmation.objects.get()
        self.assertEqual(row.status, ConfirmationStatus.DECLINED)

    def test_json_matches_flutter_contract(self):
        SessionConfirmation.objects.create(
            player=self.player, session=self.session,
            status=ConfirmationStatus.CONFIRMED,
        )
        self.client.force_authenticate(self.player)
        row = self.client.get(self._url(self.player.id)).data[0]
        self.assertEqual(
            set(row.keys()), {'sessionId', 'playerId', 'status', 'respondedAt'},
        )
        self.assertEqual(row['playerId'], str(self.player.id))
        self.assertEqual(row['sessionId'], str(self.session.id))

    def test_only_players_can_confirm(self):
        body = {'sessionId': str(self.session.id), 'status': 'CONFIRMED'}
        for role in (Roles.COACH, Roles.GUARDIAN, Roles.SCHOOL_STAFF):
            self.client.force_authenticate(make_user(role, f'{role}@rsvp.test'))
            resp = self.client.post(self._url(), body, format='json')
            self.assertEqual(resp.status_code, 403, role)
        self.assertFalse(SessionConfirmation.objects.exists())

    def test_guardian_reads_linked_child_but_not_others(self):
        SessionConfirmation.objects.create(
            player=self.player, session=self.session,
            status=ConfirmationStatus.CONFIRMED,
        )
        self.client.force_authenticate(self.guardian)
        self.assertEqual(
            self.client.get(self._url(self.player.id)).status_code, 200,
        )
        self.assertEqual(
            self.client.get(self._url(self.other.id)).status_code, 403,
        )

    def test_coach_can_read_any_player(self):
        self.client.force_authenticate(make_user(Roles.COACH))
        self.assertEqual(
            self.client.get(self._url(self.player.id)).status_code, 200,
        )

    def test_unknown_status_is_rejected(self):
        self.client.force_authenticate(self.player)
        resp = self.client.post(
            self._url(),
            {'sessionId': str(self.session.id), 'status': 'MAYBE'},
            format='json',
        )
        self.assertEqual(resp.status_code, 400)
        self.assertFalse(SessionConfirmation.objects.exists())
