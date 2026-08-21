from datetime import date

from django.core.management.base import BaseCommand
from django.db import transaction
from firebase_admin import auth as firebase_auth

from accounts.firebase import ensure_initialized
from accounts.models import Club, Roles, User
from academy.models import AgeTierSetting, PlayerProfile


DEMO_CLUB_NAME = 'FootPath Cebu Demo Club'
DEMO_CLUB_SLUG = 'footpath-cebu-demo'


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

    @transaction.atomic
    def handle(self, *args, **options):
        ensure_initialized()
        demo_club, _ = Club.objects.get_or_create(
            name=DEMO_CLUB_NAME,
            defaults={'slug': DEMO_CLUB_SLUG},
        )
        club_changes = []
        if not demo_club.is_active:
            demo_club.is_active = True
            club_changes.append('is_active')
        if not demo_club.is_school_affiliated:
            demo_club.is_school_affiliated = True
            club_changes.append('is_school_affiliated')
        if demo_club.school_name != DEMO_CLUB_NAME:
            demo_club.school_name = DEMO_CLUB_NAME
            club_changes.append('school_name')
        if club_changes:
            demo_club.save(update_fields=club_changes)

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
                defaults={
                    'username': email,
                    'email': email,
                    'role': role,
                    'club': None if role == Roles.ADMIN else demo_club,
                },
            )
            if created:
                # API users authenticate via Firebase only — no local password.
                user.set_unusable_password()
                user.save()
            if role == Roles.PLAYER:
                birth_date = date(date.today().year - 15, 1, 1)
                age, tier = AgeTierSetting.profile_defaults_for(birth_date)
                PlayerProfile.objects.get_or_create(
                    user=user,
                    defaults={
                        'date_of_birth': birth_date,
                        'age': age,
                        'age_tier': tier,
                    },
                )
            self.stdout.write(
                self.style.SUCCESS(
                    f'{"Created" if created else "Updated"} local user '
                    f'{email} as {role}'
                )
            )
