"""Regression coverage for the backend audit's data and delivery failures."""

from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import Mock, patch

from django.db import DatabaseError, connection, transaction
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import Club, Roles, User
from portal.services import set_player_eligibility

from .models import (
    Attendance,
    AuditLog,
    DeviceToken,
    Dispute,
    DisputeStatus,
    Eligibility,
    EligibilityHistory,
    NotificationRecord,
    PlayerProfile,
    PushOutbox,
    TrainingSession,
)
from .notifications import _send_to_users
from .push_delivery import deliver_pending
from .serializer_training import TrainingSessionSerializer


class AuditFixtures:
    def setUp(self):
        super().setUp()
        self.club = Club.objects.create(name='Audit FC', slug='audit-fc', is_school_affiliated=True)
        self.coach = User.objects.create(username='coach-audit', role=Roles.COACH, club=self.club)
        self.staff = User.objects.create(
            username='staff-audit', role=Roles.SCHOOL_STAFF, club=self.club
        )
        self.player = User.objects.create(
            username='player-audit', role=Roles.PLAYER, club=self.club
        )
        self.profile = PlayerProfile.objects.create(user=self.player, age_tier='FOUNDATION')

    def session(self, **kwargs):
        return TrainingSession.objects.create(
            club=self.club,
            title='Audit session',
            age_tiers=['FOUNDATION'],
            **{'date': timezone.localdate(), **kwargs},
        )


class AuditRequestTests(AuditFixtures, APITestCase):
    def test_invalid_device_shapes_and_lengths_return_400(self):
        self.client.force_authenticate(self.coach)
        payloads = [
            {'token': 123},
            {'token': 'valid', 'platform': ['android']},
            {'token': 'x' * 256},
            {'token': 'valid', 'platform': 'unknown'},
            {'token': ''},
            [],
        ]
        for payload in payloads:
            with self.subTest(payload=payload):
                response = self.client.post(reverse('devices'), payload, format='json')
                self.assertEqual(response.status_code, 400)
        self.assertFalse(DeviceToken.objects.exists())

    def test_old_and_cancelled_sessions_cannot_be_confirmed(self):
        self.client.force_authenticate(self.player)
        for session in [
            self.session(date=timezone.localdate() - timedelta(days=30)),
            self.session(status='CANCELLED'),
        ]:
            response = self.client.post(
                reverse('session-confirmations'),
                {
                    'sessionId': session.pk,
                    'status': 'CONFIRMED',
                },
                format='json',
            )
            self.assertIn(response.status_code, (400, 409))
            from .models import SessionConfirmation

            self.assertFalse(SessionConfirmation.objects.filter(session=session).exists())

        current = self.session()
        response = self.client.post(
            reverse('session-confirmations'),
            {'sessionId': current.pk, 'status': 'CONFIRMED'},
            format='json',
        )
        self.assertEqual(response.status_code, 201)

    def test_missing_or_duplicate_attendance_does_not_destroy_existing_rows(self):
        self.client.force_authenticate(self.coach)
        session = self.session()
        Attendance.objects.create(player=self.player, session=session, status='PRESENT')
        row = {'playerId': self.player.pk, 'status': 'PRESENT'}
        for payload in [{}, {'records': [row, row]}, {'records': [row] * 501}]:
            response = self.client.post(
                reverse('attendance-session', args=[session.pk]), payload, format='json'
            )
            self.assertEqual(response.status_code, 400)
            self.assertEqual(Attendance.objects.filter(session=session).count(), 1)
        session.refresh_from_db()
        self.assertEqual(session.status, 'SCHEDULED')

    def test_list_pages_keep_array_contract_and_have_a_next_link(self):
        for _ in range(3):
            self.session()
        self.client.force_authenticate(self.coach)
        response = self.client.get(reverse('training-sessions'), {'limit': 2})
        self.assertEqual(len(response.data), 2)
        self.assertEqual(response['X-Next-Offset'], '2')
        next_page = self.client.get(reverse('training-sessions'), {'limit': 2, 'offset': 2})
        self.assertEqual(len(next_page.data), 1)
        self.assertNotIn('X-Next-Offset', next_page)
        self.assertFalse({r['id'] for r in response.data} & {r['id'] for r in next_page.data})
        self.assertEqual(
            self.client.get(reverse('training-sessions'), {'limit': 501}).status_code, 400
        )

    def test_api_comment_keeps_latest_dispute_status(self):
        dispute = Dispute.objects.create(raised_by=self.coach, summary='Review')
        self.client.force_authenticate(self.coach)
        from . import dispute_service

        real_append = dispute_service.append_dispute_response

        def intervening_resolution(**kwargs):
            Dispute.objects.filter(pk=dispute.pk).update(status=DisputeStatus.RESOLVED)
            return real_append(**kwargs)

        with patch.object(
            dispute_service, 'append_dispute_response', side_effect=intervening_resolution
        ):
            response = self.client.post(
                reverse('dispute-responses', args=[dispute.pk]),
                {'body': 'Comment only'},
                format='json',
            )
        self.assertEqual(response.status_code, 201)
        dispute.refresh_from_db()
        self.assertEqual(dispute.status, DisputeStatus.RESOLVED)


class AuditIntegrityTests(AuditFixtures, TestCase):
    def test_failed_history_write_rolls_back_eligibility(self):
        original = self.profile.eligibility
        with patch(
            'academy.signals.EligibilityHistory.objects.create',
            side_effect=DatabaseError('history failed'),
        ):
            with self.assertRaises(DatabaseError):
                set_player_eligibility(
                    staff=self.staff, player_profile=self.profile, new_status=Eligibility.ELIGIBLE
                )
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.eligibility, original)
        self.assertFalse(EligibilityHistory.objects.exists())
        self.assertFalse(PushOutbox.objects.exists())

    def test_non_eligibility_save_does_not_record_unsaved_status(self):
        self.profile.eligibility = Eligibility.ELIGIBLE
        self.profile.age = 12
        self.profile.save(update_fields=['age'])
        self.assertFalse(EligibilityHistory.objects.exists())

    def test_audit_chain_uses_sequence_despite_reversed_clock(self):
        now = timezone.now()
        with patch('academy.model_operations.timezone.now', return_value=now):
            first = AuditLog.record(self.staff, 'audit.first')
        with patch(
            'academy.model_operations.timezone.now', return_value=now - timedelta(seconds=1)
        ):
            second = AuditLog.record(self.staff, 'audit.second')
        self.assertEqual(second.sequence, first.sequence + 1)
        self.assertEqual(AuditLog.verify_chain(), (True, None))

    def test_actor_reassignment_breaks_audit_verification(self):
        entry = AuditLog.record(self.staff, 'audit.actor')
        with connection.cursor() as cursor:
            cursor.execute(
                'UPDATE academy_auditlog SET actor_id = %s WHERE id = %s',
                [self.player.pk, entry.pk],
            )
        self.assertEqual(AuditLog.verify_chain(), (False, entry.pk))

    def test_deleted_actor_preserves_immutable_identity_and_valid_chain(self):
        entry = AuditLog.record(self.staff, 'audit.actor')
        actor_id = str(self.staff.pk)
        self.staff.delete()
        entry.refresh_from_db()
        self.assertEqual(entry.actor_identifier, actor_id)
        self.assertEqual(AuditLog.verify_chain(), (True, None))

    def test_session_list_count_uses_one_aggregate_query(self):
        sessions = [self.session() for _ in range(8)]
        with self.assertNumQueries(1):
            rows = TrainingSessionSerializer(sessions, many=True).data
        self.assertEqual([row['eligiblePlayerCount'] for row in rows], [1] * 8)

    def test_legacy_proof_remains_valid_when_v2_entries_are_appended(self):
        values = {
            'previous_hash': '',
            'action': 'legacy.event',
            'target': '',
            'detail': '',
            'created_at': timezone.now(),
        }
        legacy_hash = AuditLog._digest(**values)
        legacy = AuditLog.objects.create(
            **values,
            entry_hash=legacy_hash,
            sequence=1,
            hash_version=1,
        )
        new_entry = AuditLog.record(self.staff, 'new.event')
        legacy.refresh_from_db()
        self.assertEqual(legacy.entry_hash, legacy_hash)
        self.assertEqual(new_entry.previous_hash, legacy_hash)
        self.assertEqual(AuditLog.verify_chain(), (True, None))


class OutboxTests(AuditFixtures, TestCase):
    def enqueue(self):
        return _send_to_users(
            {self.player.pk}, title='Update', body='Open the app.', data={'type': 'test'}
        )

    def gateway(self):
        gateway = Mock()
        gateway.send.side_effect = lambda **kw: SimpleNamespace(
            responses=[SimpleNamespace(success=True, exception=None) for _ in kw['tokens']]
        )
        return gateway

    def test_rollback_discards_inbox_and_delivery_job(self):
        with self.assertRaises(ValueError), transaction.atomic():
            self.enqueue()
            raise ValueError('business transaction failed')
        self.assertFalse(NotificationRecord.objects.exists())
        self.assertFalse(PushOutbox.objects.exists())

    def test_large_fanout_batches_and_completed_event_is_not_resent(self):
        DeviceToken.objects.bulk_create(
            [DeviceToken(user=self.player, token=f'token-{n}') for n in range(501)]
        )
        self.enqueue()
        gateway = self.gateway()
        self.assertEqual(deliver_pending(gateway=gateway), 501)
        self.assertEqual(
            [len(call.kwargs['tokens']) for call in gateway.send.call_args_list], [500, 1]
        )
        self.assertEqual(deliver_pending(gateway=gateway), 0)
        self.assertEqual(NotificationRecord.objects.count(), 1)

    def test_failed_batch_retries_without_recreating_inbox(self):
        DeviceToken.objects.create(user=self.player, token='token')
        self.enqueue()
        gateway = self.gateway()
        gateway.send.side_effect = RuntimeError('provider unavailable')
        self.assertEqual(deliver_pending(gateway=gateway), 0)
        job = PushOutbox.objects.get()
        self.assertIsNone(job.completed_at)
        self.assertEqual(job.attempts, 1)
        PushOutbox.objects.update(available_at=timezone.now())
        self.assertEqual(deliver_pending(gateway=self.gateway()), 1)
        self.assertEqual(NotificationRecord.objects.count(), 1)

    def test_token_reassigned_after_failure_is_not_sent_to_new_owner(self):
        DeviceToken.objects.create(user=self.player, token='token')
        self.enqueue()
        gateway = self.gateway()
        gateway.send.side_effect = RuntimeError('offline')
        deliver_pending(gateway=gateway)
        DeviceToken.objects.update(user=self.coach)
        PushOutbox.objects.update(available_at=timezone.now())
        gateway = self.gateway()
        deliver_pending(gateway=gateway)
        gateway.send.assert_not_called()

    def test_partial_failure_retries_only_unsuccessful_tokens(self):
        DeviceToken.objects.bulk_create(
            [DeviceToken(user=self.player, token=t) for t in ('first', 'second')]
        )
        self.enqueue()
        gateway = Mock()
        gateway.send.return_value = SimpleNamespace(
            responses=[
                SimpleNamespace(success=True, exception=None),
                SimpleNamespace(success=False, exception=RuntimeError('retry')),
            ]
        )
        self.assertEqual(deliver_pending(gateway=gateway), 1)
        failed = next(iter(PushOutbox.objects.get().pending_tokens))
        PushOutbox.objects.update(available_at=timezone.now())
        retry = self.gateway()
        self.assertEqual(deliver_pending(gateway=retry), 1)
        self.assertEqual(retry.send.call_args.kwargs['tokens'], [failed])
