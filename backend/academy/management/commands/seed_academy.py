"""Populate academy demo data: player profiles, a training schedule, attendance,
and a guardian link — so a fresh database (SQLite or Supabase) demos the coach,
player, and guardian dashboards immediately.

Idempotent: safe to rerun. Assumes `seed_users` has already created the five
Firebase-backed role accounts (admin/coach/player/staff/guardian). The extra
roster players created here are local-only (no Firebase login) — they exist to
fill the coach's roster; the login demos use the seed_users accounts.
"""
from datetime import date, timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction

from accounts.models import Club, GuardianLink, Roles, User
from academy.models import (
    AgeTier,
    Attendance,
    AttendanceStatus,
    Eligibility,
    FootballMatch,
    PlayerMatchPerformance,
    PlayerProfile,
    SessionFocus,
    TrainingSession,
)

# (email, first, last, age, class_year, tier, position, ratings, eligibility)
ROSTER = [
    ('miguel.reyes@footpathcebu.test', 'Miguel', 'Reyes', 14, 'Class of 2028',
     AgeTier.DEVELOPMENT, 'ST', (82, 78, 70, 80, 45, 74), Eligibility.ELIGIBLE),
    ('paolo.cruz@footpathcebu.test', 'Paolo', 'Cruz', 15, 'Class of 2027',
     AgeTier.DEVELOPMENT, 'CM', (75, 68, 84, 79, 66, 71), Eligibility.ELIGIBLE),
    ('liam.tan@footpathcebu.test', 'Liam', 'Tan', 11, 'Class of 2031',
     AgeTier.FOUNDATION, 'GK', (60, 40, 55, 50, 78, 68), Eligibility.PENDING),
    ('noah.uy@footpathcebu.test', 'Noah', 'Uy', 12, 'Class of 2030',
     AgeTier.FOUNDATION, 'RW', (85, 66, 62, 82, 38, 60),
     Eligibility.ACADEMIC_WARNING),
    ('gabriel.lim@footpathcebu.test', 'Gabriel', 'Lim', 17, 'Class of 2025',
     AgeTier.PATHWAY, 'CB', (68, 45, 66, 60, 85, 82), Eligibility.ELIGIBLE),
    ('ethan.go@footpathcebu.test', 'Ethan', 'Go', 16, 'Class of 2026',
     AgeTier.PATHWAY, 'LB', (79, 52, 74, 72, 77, 75),
     Eligibility.NOT_ELIGIBLE),
]

DEMO_CLUB_NAME = 'FootPath Cebu Demo Club'
DEMO_CLUB_SLUG = 'footpath-cebu-demo'


class Command(BaseCommand):
    help = (
        'Seed player profiles, training, attendance, match statistics, and '
        'a guardian link.'
    )

    @transaction.atomic
    def handle(self, *args, **options):
        club, _ = Club.objects.get_or_create(
            name=DEMO_CLUB_NAME,
            defaults={'slug': DEMO_CLUB_SLUG},
        )
        club.is_active = True
        club.is_school_affiliated = True
        club.school_name = DEMO_CLUB_NAME
        club.save(update_fields=[
            'is_active', 'is_school_affiliated', 'school_name',
        ])

        coach = User.objects.filter(
            email='coach@footpathcebu.test', role=Roles.COACH,
        ).first()
        if coach and coach.club_id != club.id:
            coach.club = club
            coach.save(update_fields=['club'])

        # 1. Give the seeded login-player a profile, if present.
        login_player = User.objects.filter(
            email='player@footpathcebu.test'
        ).first()
        if login_player:
            login_player.role = Roles.PLAYER
            login_player.club = club
            login_player.is_active = True
            login_player.save(update_fields=['role', 'club', 'is_active'])
            self._ensure_profile(
                login_player, 15, 'Class of 2027', AgeTier.DEVELOPMENT, 'CAM',
                (80, 81, 83, 85, 60, 72), Eligibility.ELIGIBLE,
            )

        # 2. Roster players (local-only; fill the coach's squad view).
        players = []
        for (email, first, last, age, cls, tier, pos, ratings, elig) in ROSTER:
            user, _ = User.objects.update_or_create(
                username=email,
                defaults={
                    'email': email, 'first_name': first, 'last_name': last,
                    'role': Roles.PLAYER, 'club': club, 'is_active': True,
                },
            )
            self._ensure_profile(user, age, cls, tier, pos, ratings, elig)
            players.append(user)

        # 3. Training schedule (two upcoming, one past).
        sessions = self._seed_sessions(coach, club)

        # 4. Attendance for the login-player across the past session.
        past = next((s for s in sessions if s.date < date.today()), None)
        if login_player and past:
            Attendance.objects.update_or_create(
                player=login_player, session=past,
                defaults={'status': AttendanceStatus.PRESENT, 'recorded_by': coach},
            )
        for i, p in enumerate(players[:3]):
            if past:
                Attendance.objects.update_or_create(
                    player=p, session=past,
                    defaults={
                        'status': [AttendanceStatus.PRESENT, AttendanceStatus.ABSENT,
                                   AttendanceStatus.EXCUSED][i % 3],
                        'recorded_by': coach,
                    },
                )

        # 5. Completed matches and history for the login-player's Progress tab.
        self._seed_matches(coach, club, login_player)

        # 6. Link the seeded guardian to the login-player for the guardian demo.
        guardian = User.objects.filter(email='guardian@footpathcebu.test').first()
        if guardian and login_player:
            guardian.role = Roles.GUARDIAN
            guardian.club = club
            guardian.is_active = True
            guardian.save(update_fields=['role', 'club', 'is_active'])
            GuardianLink.objects.get_or_create(
                guardian=guardian, player=login_player
            )

        self.stdout.write(self.style.SUCCESS(
            f'Seeded {PlayerProfile.objects.count()} player profiles, '
            f'{TrainingSession.objects.count()} sessions, '
            f'{Attendance.objects.count()} attendance records, '
            f'{FootballMatch.objects.count()} matches, and '
            f'{PlayerMatchPerformance.objects.count()} match performances.'
        ))

    def _ensure_profile(self, user, age, cls, tier, pos, ratings, elig):
        pace, shooting, passing, dribbling, defending, physical = ratings
        PlayerProfile.objects.update_or_create(
            user=user,
            defaults={
                'age': age, 'class_year': cls, 'age_tier': tier, 'position': pos,
                'pace': pace, 'shooting': shooting, 'passing': passing,
                'dribbling': dribbling, 'defending': defending, 'physical': physical,
                'eligibility': elig,
            },
        )

    def _seed_sessions(self, coach, club):
        today = date.today()
        specs = [
            ('Evening Technical Training', today + timedelta(days=2), '04:30 PM',
             '06:00 PM', 'Cebu City Sports Complex', SessionFocus.TECHNICAL,
             [AgeTier.DEVELOPMENT, AgeTier.PATHWAY]),
            ('Foundation Fundamentals', today + timedelta(days=5), '09:00 AM',
             '10:30 AM', 'Abellana Field', SessionFocus.PHYSICAL,
             [AgeTier.FOUNDATION]),
            ('Match Prep & Mentality', today - timedelta(days=3), '05:00 PM',
             '06:30 PM', 'Cebu City Sports Complex', SessionFocus.MENTAL,
             [AgeTier.DEVELOPMENT, AgeTier.PATHWAY, AgeTier.FOUNDATION]),
        ]
        sessions = []
        for (title, d, start, end, loc, focus, tiers) in specs:
            session, _ = TrainingSession.objects.update_or_create(
                title=title, date=d,
                defaults={
                    'start_time': start, 'end_time': end, 'location': loc,
                    'focus': focus, 'age_tiers': list(tiers), 'created_by': coach,
                    'club': club,
                },
            )
            sessions.append(session)
        return sessions

    def _seed_matches(self, coach, club, login_player):
        specs = [
            ('Cebu United', 7, 'HOME', 3, 1, Decimal('8.7'), 2, 1),
            ('Mandaue FC', 21, 'AWAY', 1, 1, Decimal('7.4'), 0, 1),
        ]
        for opponent, days_ago, venue, ours, theirs, rating, goals, assists in specs:
            match, _ = FootballMatch.objects.update_or_create(
                club=club,
                opponent=opponent,
                played_on=date.today() - timedelta(days=days_ago),
                defaults={
                    'competition': 'Cebu Youth League',
                    'venue': venue,
                    'our_score': ours,
                    'opponent_score': theirs,
                    'created_by': coach,
                },
            )
            if login_player is not None:
                PlayerMatchPerformance.objects.update_or_create(
                    match=match,
                    player=login_player,
                    defaults={
                        'position': 'CAM',
                        'starter': True,
                        'minutes_played': 80,
                        'goals': goals,
                        'assists': assists,
                        'shots': 5,
                        'shots_on_target': 3,
                        'passes_attempted': 36,
                        'passes_completed': 29,
                        'tackles': 2,
                        'interceptions': 1,
                        'coach_rating': rating,
                        'notes': 'Strong movement and decision-making.',
                        'recorded_by': coach,
                    },
                )
