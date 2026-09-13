from django.core.management.base import BaseCommand

from accounts.firebase import ensure_initialized
from accounts.models import FirebaseProvisioningCleanup
from accounts.registration_service import cleanup_identity


class Command(BaseCommand):
    help = 'Retry Firebase identity cleanup after a failed player registration.'

    def handle(self, *args, **options):
        ensure_initialized()
        completed = 0
        for row in FirebaseProvisioningCleanup.objects.all().iterator():
            try:
                if cleanup_identity(row.firebase_uid):
                    row.delete()
                    completed += 1
            except Exception:
                self.stderr.write('Cleanup remains pending; retry when Firebase is available.')
        self.stdout.write(f'Completed {completed} pending cleanup operations.')
