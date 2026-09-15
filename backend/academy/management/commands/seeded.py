"""Build the complete, deterministic FootPath Cebu demo fixture."""

from django.conf import settings
from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError
from django.db import connections, transaction
from django.db.migrations.executor import MigrationExecutor

from accounts.management.commands.seed_users import DEMO_PASSWORD


class Command(BaseCommand):
    help = (
        'Refresh all user-facing FootPath demo accounts and academy data. '
        'Non-demo records are preserved.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--password',
            default=DEMO_PASSWORD,
            help='Shared password for all six demo login accounts.',
        )
        parser.add_argument(
            '--allow-production',
            action='store_true',
            help='Explicitly allow demo credentials to be written outside DEBUG/test settings.',
        )

    def handle(self, *args, **options):
        if (
            not (settings.DEBUG or getattr(settings, 'TESTING', False))
            and not options['allow_production']
        ):
            raise CommandError(
                'Refusing to install known demo credentials outside development/test settings. '
                'Use --allow-production only when this database and Firebase project are '
                'intentionally dedicated to a demo.'
            )

        pending = self._pending_migrations()
        if pending:
            names = ', '.join(pending)
            raise CommandError(
                f'Unapplied migrations: {names}. Run "python manage.py migrate" before seeded.'
            )

        password = options['password']
        verbosity = options.get('verbosity', 1)
        with transaction.atomic():
            # seed_users initializes Firebase before making local database changes,
            # so missing/invalid credentials cannot trigger demo-data cleanup.
            call_command(
                'seed_users',
                password=password,
                verbosity=verbosity,
                stdout=self.stdout,
                stderr=self.stderr,
            )
            call_command(
                'seed_academy',
                refresh=True,
                verbosity=verbosity,
                stdout=self.stdout,
                stderr=self.stderr,
            )

        self.stdout.write('')
        self.stdout.write(self.style.SUCCESS('Complete FootPath demo dataset is ready.'))
        self.stdout.write(f'Password for all six login accounts: {password}')
        self.stdout.write('Player privacy PIN: 2468')
        self.stdout.write('Accounts: admin, coordinator, coach, player, staff, guardian')
        self.stdout.write('Email domain: @footpathcebu.test')

    @staticmethod
    def _pending_migrations():
        executor = MigrationExecutor(connections['default'])
        plan = executor.migration_plan(executor.loader.graph.leaf_nodes())
        return [f'{migration.app_label}.{migration.name}' for migration, _backward in plan]
