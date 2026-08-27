from datetime import date

from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase


class InjuryConfirmationMigrationTests(TransactionTestCase):
    migrate_from = ('academy', '0018_split_match_statistics_and_ratings')
    migrate_to = ('academy', '0019_injury_confirmation_workflow')

    def setUp(self):
        super().setUp()
        executor = MigrationExecutor(connection)
        executor.migrate([self.migrate_from])
        old_apps = executor.loader.project_state([self.migrate_from]).apps
        User = old_apps.get_model('accounts', 'User')
        InjuryRecord = old_apps.get_model('academy', 'InjuryRecord')
        player = User.objects.create(
            username='migration-player',
            email='migration-player@footpath.test',
            role='PLAYER',
        )
        self.record_id = InjuryRecord.objects.create(
            player=player,
            description='Existing ankle injury',
            body_part='Left ankle',
            status='RECOVERING',
            occurred_on=date(2026, 8, 1),
            notes='Historical care note.',
        ).pk
        self.player_id = player.pk

        executor = MigrationExecutor(connection)
        executor.migrate([self.migrate_to])
        self.apps = executor.loader.project_state([self.migrate_to]).apps

    def test_existing_injury_history_is_preserved_as_confirmed(self):
        InjuryRecord = self.apps.get_model('academy', 'InjuryRecord')

        record = InjuryRecord.objects.get(pk=self.record_id)

        self.assertEqual(record.player_id, self.player_id)
        self.assertEqual(record.reported_by_id, self.player_id)
        self.assertEqual(record.review_status, 'CONFIRMED')
        self.assertEqual(record.description, 'Existing ankle injury')
        self.assertEqual(record.body_part, 'Left ankle')
        self.assertEqual(record.status, 'RECOVERING')
        self.assertEqual(record.notes, 'Historical care note.')
