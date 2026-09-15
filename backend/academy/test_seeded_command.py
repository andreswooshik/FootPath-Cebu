from datetime import date
from io import StringIO
from types import SimpleNamespace
from unittest.mock import patch

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings

from accounts.models import (
    Club,
    FirebaseProvisioningCleanup,
    GuardianLink,
    MemberRegistration,
    PlayerRegistration,
    Roles,
    User,
)

from .management.commands.seed_academy import (
    DEMO_CLUB_SLUG,
    DEMO_EMAILS,
    DEMO_PLAYER_EMAILS,
    SESSION_TITLES,
    TOURNAMENT_TITLE,
)
from .models import (
    Attendance,
    AttendanceStatus,
    AttendanceSubmission,
    AuditLog,
    ConfirmationStatus,
    DeviceToken,
    Dispute,
    DisputeResponse,
    FixtureStatus,
    FootballMatch,
    InjuryRecord,
    InjuryStatusUpdateRequest,
    InjuryUpdateReviewStatus,
    NotificationRecord,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerMatchPerformance,
    PlayerProfile,
    PlayerStatsAssessment,
    PushOutbox,
    SessionConfirmation,
    TournamentSchedule,
    TrainingSession,
    TrainingSessionStatus,
)


class UnifiedSeedCommandTests(TestCase):
    def _firebase_user(self, **kwargs):
        return SimpleNamespace(uid=f'uid-{kwargs["email"]}')

    @patch('accounts.management.commands.seed_users.ensure_initialized')
    @patch('accounts.management.commands.seed_users.firebase_auth.create_user')
    def test_seeded_refreshes_complete_demo_and_preserves_non_demo_data(
        self,
        create_firebase_user,
        _ensure_initialized,
    ):
        create_firebase_user.side_effect = self._firebase_user
        outside_club = Club.objects.create(
            name='Unrelated Academy',
            slug='unrelated-academy',
        )
        outside_user = User.objects.create(
            username='outside@example.test',
            email='outside@example.test',
            role=Roles.COACH,
            club=outside_club,
        )
        outside_session = TrainingSession.objects.create(
            title='Unrelated training',
            date='2026-09-15',
            age_tiers=['DEVELOPMENT'],
            club=outside_club,
        )

        output = StringIO()
        password = 'DemoPass!2026'
        call_command('seeded', password=password, stdout=output, verbosity=0)

        demo_club = Club.objects.get(slug=DEMO_CLUB_SLUG)
        login_emails = {
            'admin@footpathcebu.test': Roles.ADMIN,
            'coordinator@footpathcebu.test': Roles.COORDINATOR,
            'coach@footpathcebu.test': Roles.COACH,
            'player@footpathcebu.test': Roles.PLAYER,
            'staff@footpathcebu.test': Roles.SCHOOL_STAFF,
            'guardian@footpathcebu.test': Roles.GUARDIAN,
        }
        self.assertEqual(User.objects.filter(email__in=DEMO_EMAILS).count(), 12)
        self.assertEqual(
            PlayerProfile.objects.filter(user__email__in=DEMO_PLAYER_EMAILS).count(),
            7,
        )
        for email, role in login_emails.items():
            user = User.objects.get(email=email)
            self.assertEqual(user.role, role)
            self.assertEqual(user.club_id, None if role == Roles.ADMIN else demo_club.id)

        for email in (
            'admin@footpathcebu.test',
            'coordinator@footpathcebu.test',
            'staff@footpathcebu.test',
        ):
            self.assertTrue(User.objects.get(email=email).check_password(password))
        for email in (
            'coach@footpathcebu.test',
            'player@footpathcebu.test',
            'guardian@footpathcebu.test',
        ):
            user = User.objects.get(email=email)
            self.assertFalse(user.has_usable_password())
            self.assertEqual(user.firebase_uid, f'uid-{email}')

        sessions = TrainingSession.objects.filter(
            club=demo_club,
            title__in=SESSION_TITLES,
        )
        self.assertEqual(sessions.count(), 6)
        self.assertEqual(
            sessions.filter(status=TrainingSessionStatus.SCHEDULED).count(),
            3,
        )
        self.assertEqual(
            sessions.filter(status=TrainingSessionStatus.COMPLETED).count(),
            2,
        )
        self.assertEqual(
            sessions.filter(status=TrainingSessionStatus.CANCELLED).count(),
            1,
        )
        attendance = Attendance.objects.filter(player__email__in=DEMO_PLAYER_EMAILS)
        self.assertEqual(attendance.count(), 14)
        self.assertTrue(attendance.filter(status=AttendanceStatus.PRESENT).exists())
        self.assertTrue(attendance.filter(status=AttendanceStatus.ABSENT).exists())
        self.assertTrue(attendance.filter(status=AttendanceStatus.EXCUSED).exists())
        for record in attendance.filter(status=AttendanceStatus.PRESENT):
            self.assertIsNotNone(record.effort)
            self.assertIsNotNone(record.performance_score)
            self.assertTrue(record.note)

        login_player = User.objects.get(email='player@footpathcebu.test')
        self.assertTrue(
            SessionConfirmation.objects.filter(
                player=login_player,
                status=ConfirmationStatus.CONFIRMED,
            ).exists()
        )
        self.assertTrue(
            SessionConfirmation.objects.filter(status=ConfirmationStatus.DECLINED).exists()
        )
        action_ready = sessions.get(title='Tactical Shape & Set Pieces')
        self.assertFalse(
            SessionConfirmation.objects.filter(
                player=login_player,
                session=action_ready,
            ).exists()
        )

        tournament = TournamentSchedule.objects.get(
            club=demo_club,
            title=TOURNAMENT_TITLE,
        )
        self.assertTrue(tournament.is_published)
        self.assertEqual(tournament.fixtures.count(), 5)
        self.assertEqual(
            tournament.fixtures.filter(status=FixtureStatus.COMPLETED).count(),
            1,
        )
        self.assertEqual(tournament.age_brackets.get().squad.entries.count(), 4)
        self.assertEqual(
            PlayerMatchPerformance.objects.filter(
                player=login_player,
                coach_rating__isnull=False,
            ).count(),
            2,
        )
        self.assertTrue(
            PlayerMatchPerformance.objects.filter(
                match__source_fixture__schedule=tournament,
                coach_rating__isnull=True,
            ).exists()
        )

        self.assertEqual(PlayerDevelopmentAssessment.objects.filter(player=login_player).count(), 2)
        self.assertEqual(PlayerAssessmentSnapshot.objects.filter(player=login_player).count(), 2)
        self.assertEqual(PlayerStatsAssessment.objects.filter(player=login_player).count(), 2)
        for demo_player in User.objects.filter(email__in=DEMO_PLAYER_EMAILS):
            self.assertEqual(
                PlayerDevelopmentAssessment.objects.filter(player=demo_player).count(),
                2,
            )
            self.assertEqual(
                PlayerStatsAssessment.objects.filter(player=demo_player).count(),
                2,
            )
            self.assertTrue(demo_player.eligibility_history.exists())
        self.assertEqual(login_player.eligibility_history.count(), 2)
        self.assertEqual(InjuryRecord.objects.filter(player=login_player).count(), 2)
        self.assertEqual(
            InjuryStatusUpdateRequest.objects.filter(
                injury__player=login_player,
                review_status=InjuryUpdateReviewStatus.PENDING,
            ).count(),
            1,
        )
        self.assertEqual(Dispute.objects.filter(subject_player=login_player).count(), 2)
        self.assertEqual(
            DisputeResponse.objects.filter(dispute__subject_player=login_player).count(), 2
        )

        demo_notifications = NotificationRecord.objects.filter(data__demo=True)
        self.assertEqual(demo_notifications.count(), 8)
        self.assertEqual(demo_notifications.filter(read_at__isnull=True).count(), 4)
        self.assertEqual(demo_notifications.filter(read_at__isnull=False).count(), 4)
        self.assertEqual(AuditLog.objects.filter(action__startswith='demo.').count(), 6)
        self.assertEqual(AuditLog.verify_chain(), (True, None))

        self.assertFalse(DeviceToken.objects.exists())
        self.assertFalse(PushOutbox.objects.exists())
        self.assertFalse(AttendanceSubmission.objects.exists())
        self.assertFalse(PlayerRegistration.objects.exists())
        self.assertFalse(MemberRegistration.objects.exists())
        self.assertFalse(FirebaseProvisioningCleanup.objects.exists())

        original_player_id = login_player.id
        manual_player = User.objects.create(
            username='manual.player@example.test',
            email='manual.player@example.test',
            role=Roles.PLAYER,
            club=demo_club,
        )
        PlayerProfile.objects.create(
            user=manual_player,
            age=15,
            age_tier='DEVELOPMENT',
            position='CM',
        )
        manual_link = GuardianLink.objects.create(
            guardian=User.objects.get(email='guardian@footpathcebu.test'),
            player=manual_player,
        )
        manual_match = FootballMatch.objects.create(
            club=demo_club,
            competition='Manual Friendly',
            opponent='Cebu United',
            played_on=date.today(),
            our_score=0,
            opponent_score=0,
            created_by=User.objects.get(email='coach@footpathcebu.test'),
        )
        first_counts = self._demo_counts(demo_club)
        sessions.filter(title='Evening Technical Training').update(location='Changed')
        demo_notifications.filter(read_at__isnull=True).first().delete()

        call_command('seeded', password=password, stdout=StringIO(), verbosity=0)

        self.assertEqual(self._demo_counts(demo_club), first_counts)
        self.assertEqual(User.objects.get(email=login_player.email).id, original_player_id)
        self.assertEqual(
            sessions.get(title='Evening Technical Training').location,
            'Cebu City Sports Complex',
        )
        self.assertEqual(NotificationRecord.objects.filter(data__demo=True).count(), 8)
        self.assertTrue(Club.objects.filter(pk=outside_club.pk).exists())
        self.assertTrue(User.objects.filter(pk=outside_user.pk).exists())
        self.assertTrue(TrainingSession.objects.filter(pk=outside_session.pk).exists())
        self.assertTrue(GuardianLink.objects.filter(pk=manual_link.pk).exists())
        self.assertTrue(FootballMatch.objects.filter(pk=manual_match.pk).exists())
        self.assertIn('Complete FootPath demo dataset is ready.', output.getvalue())

    @staticmethod
    def _demo_counts(club):
        return {
            'users': User.objects.filter(email__in=DEMO_EMAILS).count(),
            'profiles': PlayerProfile.objects.filter(user__email__in=DEMO_PLAYER_EMAILS).count(),
            'sessions': TrainingSession.objects.filter(
                club=club,
                title__in=SESSION_TITLES,
            ).count(),
            'attendance': Attendance.objects.filter(player__email__in=DEMO_PLAYER_EMAILS).count(),
            'notifications': NotificationRecord.objects.filter(data__demo=True).count(),
            'audit': AuditLog.objects.filter(action__startswith='demo.').count(),
        }

    @override_settings(DEBUG=False, TESTING=False)
    @patch('accounts.management.commands.seed_users.ensure_initialized')
    def test_seeded_refuses_production_without_explicit_override(self, ensure_initialized):
        with self.assertRaisesMessage(CommandError, 'Refusing to install known demo credentials'):
            call_command('seeded', stdout=StringIO(), verbosity=0)

        ensure_initialized.assert_not_called()
        self.assertFalse(User.objects.filter(email__in=DEMO_EMAILS).exists())

    @patch(
        'academy.management.commands.seeded.Command._pending_migrations',
        return_value=[
            'accounts.0010_coordinator_player_registration',
            'accounts.0011_user_middle_initial',
        ],
    )
    @patch('accounts.management.commands.seed_users.ensure_initialized')
    def test_seeded_reports_pending_migrations_before_firebase_or_writes(
        self,
        ensure_initialized,
        _pending_migrations,
    ):
        with self.assertRaisesMessage(CommandError, 'Unapplied migrations: accounts.0010'):
            call_command('seeded', stdout=StringIO(), verbosity=0)

        ensure_initialized.assert_not_called()
        self.assertFalse(User.objects.filter(email__in=DEMO_EMAILS).exists())
