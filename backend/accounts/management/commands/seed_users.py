from datetime import date

from django.core.management.base import BaseCommand
from django.db import transaction
from firebase_admin import auth as firebase_auth

from academy.models import AgeTierSetting, PlayerProfile
from accounts.firebase import ensure_initialized
from accounts.models import Club, Roles, User

DEMO_CLUB_NAME = 'FootPath Cebu Demo Club'
DEMO_CLUB_SLUG = 'footpath-cebu-demo'


class Command(BaseCommand):
    help = (
        'Create panel-demo users for all six roles. Mobile users are synced '
        'to Firebase; web users receive Django passwords. Idempotent and safe '
        'to rerun for the dedicated @footpathcebu.test accounts.'
    )

    SEEDS = [
        # email, role, first name, last name, Firebase login, Django login
        ('admin@footpathcebu.test', Roles.ADMIN, 'Demo', 'Admin', False, True),
        (
            'coordinator@footpathcebu.test',
            Roles.COORDINATOR,
            'Demo',
            'Coordinator',
            True,
            True,
        ),
        ('coach@footpathcebu.test', Roles.COACH, 'Demo', 'Coach', True, False),
        ('player@footpathcebu.test', Roles.PLAYER, 'Demo', 'Player', True, False),
        (
            'staff@footpathcebu.test',
            Roles.SCHOOL_STAFF,
            'Demo',
            'School Staff',
            False,
            True,
        ),
        (
            'guardian@footpathcebu.test',
            Roles.GUARDIAN,
            'Demo',
            'Guardian',
            True,
            False,
        ),
    ]

    def add_arguments(self, parser):
        parser.add_argument(
            '--password',
            default='FootPath!2026',
            help='Shared demo password for all seeded accounts.',
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

        password = options['password']
        for (
            email,
            role,
            first_name,
            last_name,
            firebase_login,
            django_login,
        ) in self.SEEDS:
            firebase_uid = None
            if firebase_login:
                try:
                    fb_user = firebase_auth.create_user(
                        email=email,
                        password=password,
                        disabled=False,
                    )
                    self.stdout.write(f'Created Firebase user {email}')
                except firebase_auth.EmailAlreadyExistsError:
                    fb_user = firebase_auth.get_user_by_email(email)
                    firebase_auth.update_user(
                        fb_user.uid,
                        password=password,
                        disabled=False,
                    )
                    self.stdout.write(f'Reset existing Firebase demo user {email}')
                firebase_uid = fb_user.uid

            user = User.objects.filter(email__iexact=email).first()
            if user is None and firebase_uid:
                user = User.objects.filter(firebase_uid=firebase_uid).first()
            created = user is None
            if user is None:
                user = User(username=email)

            user.username = email
            user.email = email
            user.first_name = first_name
            user.last_name = last_name
            user.role = role
            user.club = None if role == Roles.ADMIN else demo_club
            user.firebase_uid = firebase_uid
            user.is_active = True
            user.is_staff = role == Roles.ADMIN
            user.is_superuser = role == Roles.ADMIN
            if django_login:
                user.set_password(password)
            else:
                user.set_unusable_password()
            user.save()
            if role == Roles.PLAYER:
                birth_date = date(date.today().year - 14, 1, 1)
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
                    f'{"Created" if created else "Updated"} local user {email} as {role}'
                )
            )

        self.stdout.write(
            self.style.SUCCESS(
                f'Panel demo accounts are ready. All six use the password {password!r}.'
            )
        )
