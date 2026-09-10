"""Run the durable notification worker, once or continuously."""

import time

from django.core.management.base import BaseCommand
from django.db import close_old_connections

from academy.push_delivery import deliver_pending


class Command(BaseCommand):
    help = 'Deliver pending push notifications with retries; use --watch for a worker.'

    def add_arguments(self, parser):
        parser.add_argument('--watch', action='store_true')
        parser.add_argument('--limit', type=int, default=100)

    def handle(self, *args, **options):
        while True:
            close_old_connections()
            sent = deliver_pending(limit=max(1, options['limit']))
            self.stdout.write(f'Delivered to {sent} devices.')
            if not options['watch']:
                return
            time.sleep(5)
