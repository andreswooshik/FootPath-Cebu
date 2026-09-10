"""Production-database integration checks, run by the PostgreSQL CI job."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, time, timedelta
from threading import Barrier
from types import SimpleNamespace
from unittest import skipUnless

from django.db import close_old_connections, connection, connections, transaction
from django.test import TransactionTestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import Club, Roles, User

from .attendance_service import replace_attendance
from .dispute_service import append_dispute_response
from .models import (
    Attendance,
    AuditLog,
    DeviceToken,
    Dispute,
    DisputeStatus,
    PlayerProfile,
    PushOutbox,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TrainingSession,
)
from .notifications import _send_to_users
from .push_delivery import deliver_pending
from .view_tournaments import _coordinator_mobile_fixture


@skipUnless(connection.vendor == 'postgresql', 'Requires isolated PostgreSQL test settings')
class PostgreSQLConcurrencyTests(TransactionTestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Concurrent FC', slug='concurrent-fc')
        self.coach = User.objects.create(
            username='concurrent-coach', role=Roles.COACH, club=self.club
        )
        self.coordinator = User.objects.create(
            username='concurrent-coordinator', role=Roles.COORDINATOR, club=self.club
        )
        self.players = [
            User.objects.create(
                username=f'concurrent-player-{n}', role=Roles.PLAYER, club=self.club
            )
            for n in range(2)
        ]
        for player in self.players:
            PlayerProfile.objects.create(user=player)

    def parallel(self, *actions):
        barrier = Barrier(len(actions))

        def run(action):
            close_old_connections()
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SET lock_timeout = '10s'")
                    cursor.execute("SET statement_timeout = '20s'")
                barrier.wait(timeout=10)
                return action()
            finally:
                connections.close_all()

        with ThreadPoolExecutor(max_workers=len(actions)) as executor:
            futures = [executor.submit(run, action) for action in actions]
            return [future.result(timeout=30) for future in futures]

    def test_first_overlapping_sessions_cannot_both_be_created(self):
        payload = {
            'title': 'Concurrent training',
            'date': (timezone.localdate() + timedelta(days=1)).isoformat(),
            'startTime': '04:00 PM',
            'endTime': '05:00 PM',
            'ageTiers': ['FOUNDATION'],
            'location': 'Pitch 1',
            'focus': 'TECHNICAL',
        }

        def create():
            client = APIClient()
            client.force_authenticate(User.objects.get(pk=self.coach.pk))
            return client.post(reverse('training-sessions'), payload, format='json').status_code

        self.assertEqual(sorted(self.parallel(create, create)), [201, 409])
        self.assertEqual(TrainingSession.objects.count(), 1)

    def test_competing_attendance_batches_leave_one_complete_batch(self):
        session = TrainingSession.objects.create(
            club=self.club, title='Roll call', date=timezone.localdate(), age_tiers=['FOUNDATION']
        )

        def replace(player):
            def action():
                replace_attendance(
                    coach=User.objects.get(pk=self.coach.pk),
                    session_id=session.pk,
                    records=[{'playerId': player.pk, 'status': 'PRESENT'}],
                )

            return action

        self.parallel(*(replace(player) for player in self.players))
        self.assertEqual(Attendance.objects.filter(session=session).count(), 1)

    def test_concurrent_comment_cannot_reopen_resolved_dispute(self):
        dispute = Dispute.objects.create(raised_by=self.coach, summary='Concurrent review')

        def reply(status):
            return lambda: (
                append_dispute_response(
                    actor=User.objects.get(pk=self.coach.pk),
                    dispute_id=dispute.pk,
                    body='Review response',
                    status_change_to=status,
                ).pk
            )

        self.parallel(reply(DisputeStatus.RESOLVED), reply(None))
        dispute.refresh_from_db()
        self.assertEqual(dispute.status, DisputeStatus.RESOLVED)
        self.assertEqual(dispute.responses.count(), 2)

    def test_nullable_fixture_joins_can_be_locked(self):
        schedule = TournamentSchedule.objects.create(
            club=self.club, title='Lock cup', starts_on=timezone.localdate()
        )
        bracket = TournamentAgeBracket.objects.create(
            schedule=schedule, max_age=12, academy_tiers=['FOUNDATION']
        )
        fixture = TournamentFixture.objects.create(
            schedule=schedule, age_bracket=bracket, kickoff_at=timezone.now()
        )
        with transaction.atomic():
            locked = _coordinator_mobile_fixture(self.coordinator, fixture.pk, lock=True)
            self.assertIsNone(locked.completed_match_id)
            fixtures = list(
                TournamentFixture.objects.select_for_update(of=('self',))
                .select_related('schedule', 'age_bracket')
                .filter(schedule=schedule)
            )
            self.assertEqual(len(fixtures), 1)

    def test_concurrent_audit_appends_form_one_sequence(self):
        self.parallel(
            lambda: AuditLog.record(self.coach, 'concurrent.first').pk,
            lambda: AuditLog.record(self.coach, 'concurrent.second').pk,
        )
        self.assertEqual(AuditLog.verify_chain(), (True, None))
        self.assertEqual(
            list(AuditLog.objects.order_by('sequence').values_list('sequence', flat=True)), [1, 2]
        )

    def test_tournament_publish_and_training_create_obey_priority(self):
        day = timezone.localdate() + timedelta(days=1)
        schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Priority cup',
            starts_on=day,
            venue='Pitch',
        )
        bracket = TournamentAgeBracket.objects.create(
            schedule=schedule,
            max_age=12,
            academy_tiers=['FOUNDATION'],
        )
        TournamentFixture.objects.create(
            schedule=schedule,
            age_bracket=bracket,
            stage='Final',
            location='Pitch',
            kickoff_at=timezone.make_aware(datetime.combine(day, time(16))),
            ends_at=timezone.make_aware(datetime.combine(day, time(17))),
        )

        def publish():
            client = APIClient()
            client.force_authenticate(User.objects.get(pk=self.coordinator.pk))
            return client.post(
                reverse('tournament-schedule-publish', args=[schedule.pk]),
                {'confirmTrainingCancellations': True},
                format='json',
            ).status_code

        def create():
            client = APIClient()
            client.force_authenticate(User.objects.get(pk=self.coach.pk))
            return client.post(
                reverse('training-sessions'),
                {
                    'title': 'Concurrent training',
                    'date': day.isoformat(),
                    'startTime': '04:00 PM',
                    'endTime': '05:00 PM',
                    'ageTiers': ['FOUNDATION'],
                    'location': 'Pitch',
                    'focus': 'TECHNICAL',
                },
                format='json',
            ).status_code

        publish_status, create_status = self.parallel(publish, create)
        self.assertEqual(publish_status, 200)
        self.assertIn(create_status, (201, 409))
        self.assertFalse(TrainingSession.objects.filter(status='SCHEDULED').exists())

    def test_two_workers_claim_one_event_without_network_transaction(self):
        player = self.players[0]
        DeviceToken.objects.create(user=player, token='concurrent-device')
        _send_to_users({player.pk}, title='Update', body='Open app', data={'type': 'test'})
        transactions_during_send = []

        class Gateway:
            def send(self, **kwargs):
                transactions_during_send.append(connection.in_atomic_block)
                return SimpleNamespace(responses=[SimpleNamespace(success=True)])

        results = self.parallel(
            lambda: deliver_pending(gateway=Gateway()),
            lambda: deliver_pending(gateway=Gateway()),
        )
        self.assertEqual(sum(results), 1)
        self.assertEqual(transactions_during_send, [False])
        self.assertIsNotNone(PushOutbox.objects.get().completed_at)
