from datetime import date

from django.core.management.base import BaseCommand
from django.db import transaction
from firebase_admin import auth as firebase_auth

from academy.models import AgeTierSetting, PlayerProfile
from accounts.firebase import ensure_initialized
from accounts.models import Club, Roles, User

DEMO_CLUB_NAME = 'FootPath Cebu Demo Club'
DEMO_CLUB_SLUG = 'footpath-cebu-demo'
DEMO_PASSWORD = 'FootPath!2026'


def birth_date_for_age(age):
    """Return a date whose age remains exact whenever the seed is run."""
    today = date.today()
    try:
        return today.replace(year=today.year - age)
    except ValueError:  # February 29 in a non-leap birth year.
        return today.replace(year=today.year - age, day=28)


class Command(BaseCommand):
    help = (
        'Create panel-demo users for the supported roles. Mobile users are synced '
        'to Firebase; portal users receive Django passwords. Idempotent and safe '
        'to rerun for the dedicated @footpathcebu.test accounts.'
    )

    SEEDS = [
        # email, role, first, last, initial, mobile, Firebase login, Django login
        (
            'admin@footpathcebu.test',
            Roles.ADMIN,
            'Alicia',
            'Santos',
            'D',
            '+639171000001',
            False,
            True,
        ),
        (
            'coordinator@footpathcebu.test',
            Roles.COORDINATOR,
            'Carlo',
            'Mendoza',
            'R',
            '+639171000002',
            True,
            True,
        ),
        (
            'coach@footpathcebu.test',
            Roles.COACH,
            'Marco',
            'Villanueva',
            'L',
            '+639171000003',
            True,
            False,
        ),
        (
            'player@footpathcebu.test',
            Roles.PLAYER,
            'Nico',
            'Garcia',
            'T',
            '+639171000004',
            True,
            False,
        ),
        (
            'guardian@footpathcebu.test',
            Roles.GUARDIAN,
            'Elena',
            'Garcia',
            'P',
            '+639171000006',
            True,
            False,
        ),
    ]

    def add_arguments(self, parser):
        parser.add_argument(
            '--password',
            default=DEMO_PASSWORD,
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
        if demo_club.head_coach_name != 'Marco L. Villanueva':
            demo_club.head_coach_name = 'Marco L. Villanueva'
            club_changes.append('head_coach_name')
        if demo_club.cvfa_membership != 'CVFA-DEMO-2026':
            demo_club.cvfa_membership = 'CVFA-DEMO-2026'
            club_changes.append('cvfa_membership')
        if club_changes:
            demo_club.save(update_fields=club_changes)

        password = options['password']
        for (
            email,
            role,
            first_name,
            last_name,
            middle_initial,
            mobile_number,
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
            user.middle_initial = middle_initial
            user.mobile_number = mobile_number
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
                birth_date = birth_date_for_age(14)
                age, tier = AgeTierSetting.profile_defaults_for(birth_date)
                PlayerProfile.objects.update_or_create(
                    user=user,
                    defaults={
                        'middle_initial': middle_initial,
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
                f'Panel demo accounts are ready. All accounts use the password {password!r}.'
            )
        )
