from django.core.exceptions import ValidationError
from django.test import SimpleTestCase
from django.urls import reverse
from rest_framework.test import APITestCase

from accounts.models import Roles

from .models import PlayerStatsAssessment
from .player_stats import catalog_for, normalized_scores, overall, role_group_for
from .tests import make_player, make_user


class PlayerStatsCatalogTests(SimpleTestCase):
    def test_every_supported_position_uses_its_role_catalog(self):
        expected = {
            'GK': 'GOALKEEPER',
            'CB': 'DEFENDER',
            'LB': 'DEFENDER',
            'RB': 'DEFENDER',
            'CDM': 'MIDFIELDER',
            'CM': 'MIDFIELDER',
            'CAM': 'MIDFIELDER',
            'LW': 'ATTACKER',
            'RW': 'ATTACKER',
            'ST': 'ATTACKER',
        }
        for position, group in expected.items():
            returned_group, attributes = catalog_for(position)
            self.assertEqual(group, returned_group)
            self.assertEqual(6, len(attributes))

    def test_scores_are_complete_bounded_and_overall_is_rounded(self):
        scores = {
            'pace': 80,
            'passing': 81,
            'dribbling': 82,
            'vision': 83,
            'defending': 84,
            'physical': 85,
        }
        self.assertEqual(scores, normalized_scores('CM', scores))
        self.assertEqual(83, overall(scores))
        with self.assertRaises(ValidationError):
            normalized_scores('CM', {**scores, 'vision': 100})

    def test_role_change_selects_a_new_compatible_catalog(self):
        self.assertEqual('DEFENDER', role_group_for('CB'))
        self.assertEqual('ATTACKER', role_group_for('ST'))


class PlayerStatsApiTests(APITestCase):
    def setUp(self):
        self.coach = make_user(Roles.COACH, 'stats-coach@footpathcebu.test')
        self.player = make_player('stats-player@footpathcebu.test', position='CM')
        self.url = reverse('player-stats', args=[self.player.id])
        self.scores = {
            'pace': 80,
            'passing': 81,
            'dribbling': 82,
            'vision': 83,
            'defending': 84,
            'physical': 85,
        }

    def _assessment(self, scores):
        return PlayerStatsAssessment.objects.create(
            player=self.player,
            assessed_by=self.coach,
            position='CM',
            role_group='MIDFIELDER',
            catalog_version=1,
            scores=scores,
            overall=overall(scores),
            reason='MONTHLY_REVIEW',
            coach_notes='Reviewed with the player.',
        )

    def test_get_zero_and_one_record_are_baselines(self):
        self.client.force_authenticate(self.coach)
        empty = self.client.get(self.url)
        self.assertIsNone(empty.data['latestCompatibleStats'])
        self.assertTrue(empty.data['comparison']['baseline'])
        self._assessment(self.scores)
        one = self.client.get(self.url)
        self.assertTrue(one.data['comparison']['baseline'])
        self.assertIsNone(one.data['comparison']['overallDelta'])

    def test_get_compares_latest_to_immediately_previous_compatible_record(self):
        self._assessment(self.scores)
        newer = {**self.scores, 'pace': 90, 'physical': 75}
        self._assessment(newer)
        self.client.force_authenticate(self.coach)

        response = self.client.get(self.url)

        comparison = response.data['comparison']
        self.assertFalse(comparison['baseline'])
        self.assertEqual(83, comparison['previousOverall'])
        self.assertEqual(83, comparison['newOverall'])
        self.assertEqual(0, comparison['overallDelta'])
        self.assertEqual(80, comparison['attributes']['pace']['previous'])
        self.assertEqual(90, comparison['attributes']['pace']['new'])
        self.assertEqual(10, comparison['attributes']['pace']['delta'])
        self.assertEqual(-10, comparison['attributes']['physical']['delta'])

    def test_incompatible_role_group_is_not_used_as_comparison_baseline(self):
        self._assessment(self.scores)
        PlayerStatsAssessment.objects.create(
            player=self.player,
            assessed_by=self.coach,
            position='ST',
            role_group='ATTACKER',
            catalog_version=1,
            scores={
                'pace': 1,
                'shooting': 1,
                'dribbling': 1,
                'off_ball_movement': 1,
                'passing': 1,
                'physical': 1,
            },
            overall=1,
            reason='MONTHLY_REVIEW',
            coach_notes='Different role group.',
        )
        self.client.force_authenticate(self.coach)

        response = self.client.get(self.url)

        self.assertTrue(response.data['comparison']['baseline'])
        self.assertEqual(1, len(response.data['history']))

    def test_write_rejects_blank_reason_and_notes(self):
        self.client.force_authenticate(self.coach)
        payload = {
            'catalogVersion': 1,
            'scores': self.scores,
            'reason': '   ',
            'coachNotes': '   ',
        }

        response = self.client.post(self.url, payload, format='json')

        self.assertEqual(response.status_code, 400)
        self.assertIn('reason', response.data)
        self.assertIn('coachNotes', response.data)
