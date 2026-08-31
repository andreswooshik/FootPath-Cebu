from django.test import TestCase

from accounts.models import Roles, User
from academy.models import (
    AssessmentReason,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerProfile,
)


class PlayerDevelopmentAssessmentModelTests(TestCase):
    def setUp(self):
        self.coach = User.objects.create_user(
            username='coach-development',
            email='coach-development@example.com',
            password='test-password',
            role=Roles.COACH,
        )
        self.player = User.objects.create_user(
            username='player-development',
            email='player-development@example.com',
            password='test-password',
            role=Roles.PLAYER,
        )
        self.profile = PlayerProfile.objects.create(
            user=self.player,
            age=14,
            age_tier='DEVELOPMENT',
            position='CM',
        )

    def test_profile_defaults_do_not_fabricate_framework_scores(self):
        self.assertIsNone(self.profile.development_framework_version)
        self.assertEqual(self.profile.development_scores, {})
        self.assertEqual(self.profile.development_strengths, '')
        self.assertEqual(self.profile.development_targets, '')
        self.assertIsNone(self.profile.development_assessed_at)
        self.assertFalse(PlayerDevelopmentAssessment.objects.exists())

    def test_snapshot_copies_current_framework_state_without_legacy_row(self):
        self.profile.development_framework_version = 1
        self.profile.development_scores = {
            'technical': {'firstTouchBallControl': 4},
        }
        self.profile.development_strengths = 'Scans before receiving.'
        self.profile.development_targets = 'Use the weaker foot more often.'
        self.profile.coach_notes = 'Good response to feedback.'
        self.profile.save()

        snapshot = PlayerDevelopmentAssessment.from_profile(
            self.profile,
            assessed_by=self.coach,
            reason=AssessmentReason.MONTHLY_REVIEW,
        )

        self.assertEqual(snapshot.player, self.player)
        self.assertEqual(snapshot.assessed_by, self.coach)
        self.assertEqual(snapshot.position, 'CM')
        self.assertEqual(snapshot.age_tier, 'DEVELOPMENT')
        self.assertEqual(snapshot.age_at_assessment, 14)
        self.assertEqual(snapshot.framework_version, 1)
        self.assertEqual(snapshot.scores, self.profile.development_scores)
        self.assertEqual(snapshot.strengths, self.profile.development_strengths)
        self.assertEqual(
            snapshot.development_targets,
            self.profile.development_targets,
        )
        self.assertEqual(snapshot.reason, AssessmentReason.MONTHLY_REVIEW)
        self.assertFalse(PlayerAssessmentSnapshot.objects.exists())
