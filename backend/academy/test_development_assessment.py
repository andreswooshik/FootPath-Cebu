from unittest.mock import patch

from django.urls import reverse
from django.test import TestCase
from rest_framework.test import APITestCase

from accounts.models import Club, Roles, User
from academy.assessment_framework import framework_for
from academy.models import (
    AssessmentReason,
    AuditLog,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerProfile,
)


def _club(name):
    return Club.objects.create(
        name=name,
        slug=name.lower().replace(' ', '-'),
        is_school_affiliated=False,
    )


def _user(email, role, club):
    return User.objects.create(
        username=email,
        email=email,
        firebase_uid=f'development-{email}',
        role=role,
        club=club,
    )


def _ratings(framework, value=3):
    return {
        domain['key']: {
            indicator['key']: value
            for indicator in domain['indicators']
        }
        for domain in framework['domains']
    }


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


class DevelopmentAssessmentApiTests(APITestCase):
    def setUp(self):
        self.club = _club('Development API Club')
        self.other_club = _club('Other Development API Club')
        self.coach = _user('coach@development.test', Roles.COACH, self.club)
        self.other_coach = _user(
            'other@development.test', Roles.COACH, self.other_club
        )
        self.player = _user('player@development.test', Roles.PLAYER, self.club)
        self.profile = PlayerProfile.objects.create(
            user=self.player,
            age=14,
            age_tier='DEVELOPMENT',
            position='CM',
        )
        self.url = reverse('player-assessment', args=[self.player.id])
        self.framework = framework_for(
            self.profile.age_tier,
            self.profile.position,
        )

    def _payload(self, value=3, **overrides):
        payload = {
            'frameworkVersion': 1,
            'developmentRatings': _ratings(self.framework, value),
            'strengths': 'Scans early and supports teammates.',
            'developmentTargets': 'Receive on the weaker side more often.',
            'coachNotes': 'Monthly holistic review.',
            'assessmentReason': 'MONTHLY_REVIEW',
        }
        payload.update(overrides)
        return payload

    def test_get_returns_age_and_position_specific_framework(self):
        self.client.force_authenticate(self.coach)
        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 200)
        framework = response.data['framework']
        self.assertEqual(framework['version'], 1)
        self.assertEqual(framework['ageTier'], 'DEVELOPMENT')
        self.assertEqual(framework['positionGroup'], 'MIDFIELD')
        technical = framework['domains'][0]
        self.assertEqual(technical['key'], 'technical')
        self.assertEqual(len(technical['indicators']), 5)
        self.assertEqual(technical['minimumObserved'], 3)
        self.assertIsNone(response.data['latestAssessment'])

    def test_framework_is_coach_only_and_same_club(self):
        self.client.force_authenticate(self.other_coach)
        self.assertEqual(self.client.get(self.url).status_code, 403)
        self.client.force_authenticate(self.player)
        self.assertEqual(self.client.get(self.url).status_code, 403)

    def test_valid_write_updates_current_profile_and_one_immutable_history(self):
        self.client.force_authenticate(self.coach)
        response = self.client.put(self.url, self._payload(), format='json')

        self.assertEqual(response.status_code, 200)
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.development_framework_version, 1)
        self.assertEqual(
            self.profile.development_scores,
            self._payload()['developmentRatings'],
        )
        self.assertIsNotNone(self.profile.development_assessed_at)
        snapshot = PlayerDevelopmentAssessment.objects.get(player=self.player)
        self.assertEqual(snapshot.assessed_by, self.coach)
        self.assertEqual(snapshot.reason, AssessmentReason.MONTHLY_REVIEW)
        self.assertEqual(snapshot.position, 'CM')
        self.assertEqual(snapshot.age_tier, 'DEVELOPMENT')
        self.assertEqual(snapshot.scores, self.profile.development_scores)
        self.assertFalse(PlayerAssessmentSnapshot.objects.exists())
        self.assertEqual(
            response.data['developmentAssessment']['domainScores']['technical'],
            3.0,
        )
        self.assertTrue(
            AuditLog.objects.filter(
                action='development_assessment.saved',
                actor=self.coach,
            ).exists()
        )

    def test_no_op_write_does_not_duplicate_history_or_audit(self):
        self.client.force_authenticate(self.coach)
        self.client.put(self.url, self._payload(), format='json')
        self.client.put(self.url, self._payload(), format='json')

        self.assertEqual(PlayerDevelopmentAssessment.objects.count(), 1)
        self.assertEqual(
            AuditLog.objects.filter(
                action='development_assessment.saved'
            ).count(),
            1,
        )

    def test_rejects_invalid_score_shape_and_incomplete_domains(self):
        self.client.force_authenticate(self.coach)
        payload = self._payload()
        payload['developmentRatings']['technical'][
            'firstTouchBallControl'
        ] = True
        response = self.client.put(self.url, payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('developmentRatings', response.data)

        payload = self._payload()
        technical = payload['developmentRatings']['technical']
        for key in list(technical)[1:]:
            technical[key] = None
        response = self.client.put(self.url, payload, format='json')
        self.assertEqual(response.status_code, 400)
        self.assertIn('developmentRatings', response.data)
        self.assertFalse(PlayerDevelopmentAssessment.objects.exists())

    def test_requires_written_strength_and_target(self):
        self.client.force_authenticate(self.coach)
        for field in ('strengths', 'developmentTargets'):
            response = self.client.put(
                self.url,
                self._payload(**{field: '   '}),
                format='json',
            )
            self.assertEqual(response.status_code, 400)
            self.assertIn(field, response.data)

    def test_rejects_mixed_legacy_and_framework_payload(self):
        self.client.force_authenticate(self.coach)
        response = self.client.put(
            self.url,
            self._payload(ratings={'pace': 99}),
            format='json',
        )
        self.assertEqual(response.status_code, 400)

    @patch(
        'academy.views.PlayerDevelopmentAssessment.from_profile',
        side_effect=RuntimeError('development snapshot failed'),
    )
    def test_snapshot_failure_rolls_back_current_framework_state(self, _write):
        self.client.force_authenticate(self.coach)
        with self.assertRaises(RuntimeError):
            self.client.put(self.url, self._payload(), format='json')
        self.profile.refresh_from_db()
        self.assertIsNone(self.profile.development_framework_version)
        self.assertEqual(self.profile.development_scores, {})


class DevelopmentAssessmentGrowthTests(APITestCase):
    def setUp(self):
        self.club = _club('Development Growth Club')
        self.coach = _user('coach@development-growth.test', Roles.COACH, self.club)
        self.player = _user(
            'player@development-growth.test', Roles.PLAYER, self.club
        )
        self.profile = PlayerProfile.objects.create(
            user=self.player,
            age=15,
            age_tier='DEVELOPMENT',
            position='ST',
        )
        self.assessment_url = reverse(
            'player-assessment', args=[self.player.id]
        )
        self.growth_url = reverse('player-growth', args=[self.player.id])
        self.framework = framework_for('DEVELOPMENT', 'ST')
        self.client.force_authenticate(self.coach)

    def _save(self, value, strength):
        return self.client.put(
            self.assessment_url,
            {
                'frameworkVersion': 1,
                'developmentRatings': _ratings(self.framework, value),
                'strengths': strength,
                'developmentTargets': 'Keep applying the next action.',
                'assessmentReason': 'GENERAL_REVIEW',
            },
            format='json',
        )

    def test_growth_adds_domain_trends_without_changing_legacy_contract(self):
        self.assertEqual(self._save(2, 'Developing habits.').status_code, 200)
        self.assertEqual(self._save(4, 'Stronger habits.').status_code, 200)

        response = self.client.get(
            self.growth_url,
            {'range': 'all', 'category': 'assessment'},
        )
        self.assertEqual(response.status_code, 200)
        assessment = response.data['assessments']
        self.assertIn('summary', assessment)
        self.assertIn('history', assessment)
        self.assertEqual(assessment['developmentSummary']['sampleSize'], 2)
        self.assertEqual(len(assessment['developmentHistory']), 2)
        technical = assessment['developmentSummary']['domains'][0]
        self.assertEqual(technical['key'], 'technical')
        self.assertEqual(technical['latestScore'], 4.0)
        self.assertEqual(technical['previousScore'], 2.0)
        self.assertEqual(technical['delta'], 2.0)
        self.assertEqual(technical['classification'], 'IMPROVING')
        self.assertNotIn('overall', assessment['developmentSummary'])
        self.assertEqual(assessment['history'], [])

    def test_not_observed_is_excluded_and_low_comparability_is_insufficient(self):
        first = _ratings(self.framework, 3)
        second = _ratings(self.framework, 4)
        technical_keys = list(first['technical'])
        for key in technical_keys[3:]:
            first['technical'][key] = None
        for key in technical_keys[:2]:
            second['technical'][key] = None

        for ratings, strength in (
            (first, 'First observation.'),
            (second, 'Second observation.'),
        ):
            response = self.client.put(
                self.assessment_url,
                {
                    'frameworkVersion': 1,
                    'developmentRatings': ratings,
                    'strengths': strength,
                    'developmentTargets': 'Continue observing.',
                    'assessmentReason': 'GENERAL_REVIEW',
                },
                format='json',
            )
            self.assertEqual(response.status_code, 200)

        response = self.client.get(
            self.growth_url,
            {'range': 'all', 'category': 'assessment'},
        )
        technical = response.data['assessments'][
            'developmentSummary'
        ]['domains'][0]
        self.assertEqual(technical['comparableIndicatorCount'], 1)
        self.assertEqual(technical['classification'], 'INSUFFICIENT_DATA')
