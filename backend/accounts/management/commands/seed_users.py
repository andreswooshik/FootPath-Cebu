from django.core.management.base import BaseCommand
from firebase_admin import auth as firebase_auth

from accounts.firebase import ensure_initialized
from accounts.models import Roles, User


class Command(BaseCommand):
    help = (
        'Create Firebase + local dev users for all five roles. Idempotent: '
        'safe to rerun. This mirrors how Admin provisioning will work.'
    )

    SEEDS = [
        ('admin@footpathcebu.test', Roles.ADMIN),
        ('coach@footpathcebu.test', Roles.COACH),
        ('player@footpathcebu.test', Roles.PLAYER),
        ('staff@footpathcebu.test', Roles.SCHOOL_STAFF),
        ('guardian@footpathcebu.test', Roles.GUARDIAN),
    ]

    def add_arguments(self, parser):
        parser.add_argument(
            '--password',
            default='FootPath!2026',
            help='Password for all seeded Firebase users (min 6 chars).',
        )

    def handle(self, *args, **options):
        ensure_initialized()
        for email, role in self.SEEDS:
            try:
                fb_user = firebase_auth.create_user(
                    email=email, password=options['password']
                )
                self.stdout.write(f'Created Firebase user {email}')
            except firebase_auth.EmailAlreadyExistsError:
                fb_user = firebase_auth.get_user_by_email(email)
                self.stdout.write(f'Firebase user {email} already exists')

            user, created = User.objects.update_or_create(
                firebase_uid=fb_user.uid,
                defaults={'username': email, 'email': email, 'role': role},
            )
            if created:
                # API users authenticate via Firebase only — no local password.
                user.set_unusable_password()
                user.save()
            self.stdout.write(
                self.style.SUCCESS(
                    f'{"Created" if created else "Updated"} local user '
                    f'{email} as {role}'
                )
            )
