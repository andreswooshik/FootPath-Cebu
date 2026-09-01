from django.core.exceptions import ValidationError
from django.test import SimpleTestCase

from .player_stats import catalog_for, normalized_scores, overall, role_group_for


class PlayerStatsCatalogTests(SimpleTestCase):
    def test_every_supported_position_uses_its_role_catalog(self):
        expected = {
            'GK': 'GOALKEEPER', 'CB': 'DEFENDER', 'LB': 'DEFENDER', 'RB': 'DEFENDER',
            'CDM': 'MIDFIELDER', 'CM': 'MIDFIELDER', 'CAM': 'MIDFIELDER',
            'LW': 'ATTACKER', 'RW': 'ATTACKER', 'ST': 'ATTACKER',
        }
        for position, group in expected.items():
            returned_group, attributes = catalog_for(position)
            self.assertEqual(group, returned_group)
            self.assertEqual(6, len(attributes))

    def test_scores_are_complete_bounded_and_overall_is_rounded(self):
        scores = {
            'pace': 80, 'passing': 81, 'dribbling': 82,
            'vision': 83, 'defending': 84, 'physical': 85,
        }
        self.assertEqual(scores, normalized_scores('CM', scores))
        self.assertEqual(83, overall(scores))
        with self.assertRaises(ValidationError):
            normalized_scores('CM', {**scores, 'vision': 100})

    def test_role_change_selects_a_new_compatible_catalog(self):
        self.assertEqual('DEFENDER', role_group_for('CB'))
        self.assertEqual('ATTACKER', role_group_for('ST'))
