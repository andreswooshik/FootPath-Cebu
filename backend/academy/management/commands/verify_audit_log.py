from django.core.management.base import BaseCommand, CommandError

from academy.models import AuditLog


class Command(BaseCommand):
    help = 'Verify the cryptographic chain of append-only audit entries.'

    def handle(self, *args, **options):
        valid, failing_id = AuditLog.verify_chain()
        if not valid:
            raise CommandError(f'Audit chain verification failed at entry {failing_id}.')
        self.stdout.write(self.style.SUCCESS('Audit chain is valid.'))
