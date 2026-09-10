"""Populate academy demo data: player profiles, a training schedule, attendance,
and a guardian link — so a fresh database (SQLite or Supabase) demos the coach,
player, and guardian dashboards immediately.

Idempotent: safe to rerun. Assumes `seed_users` has already created the five
Firebase-backed role accounts (admin/coach/player/staff/guardian). The extra
roster players created here are local-only (no Firebase login) — they exist to
fill the coach's roster; the login demos use the seed_users accounts.
"""

from datetime import date, datetime, time, timedelta
from decimal import Decimal

from django.contrib.auth.hashers import make_password
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from academy.assessment_framework import FRAMEWORK_VERSION, framework_for
from academy.models import (
    AgeTier,
    Attendance,
    AttendanceStatus,
    ConfirmationStatus,
    Dispute,
    DisputeCategory,
    DisputeStatus,
    Eligibility,
    FixtureStatus,
    FootballMatch,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    MatchCategory,
    MatchVenue,
    NotificationRecord,
    PlayerDevelopmentAssessment,
    PlayerMatchPerformance,
    PlayerPrivacyPin,
    PlayerProfile,
    SessionConfirmation,
    SessionFocus,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
    TrainingSession,
)
from accounts.models import Club, GuardianLink, Roles, User

# (email, first, last, age, class_year, tier, position, ratings, eligibility)
ROSTER = [
    (
        'miguel.reyes@footpathcebu.test',
        'Miguel',
        'Reyes',
        14,
        'Class of 2028',
        AgeTier.DEVELOPMENT,
        'ST',
        (82, 78, 70, 80, 45, 74),
        Eligibility.ELIGIBLE,
    ),
    (
        'paolo.cruz@footpathcebu.test',
        'Paolo',
        'Cruz',
        15,
        'Class of 2027',
        AgeTier.DEVELOPMENT,
        'CM',
        (75, 68, 84, 79, 66, 71),
        Eligibility.ELIGIBLE,
    ),
    (
        'liam.tan@footpathcebu.test',
        'Liam',
        'Tan',
        11,
        'Class of 2031',
        AgeTier.FOUNDATION,
        'GK',
        (60, 40, 55, 50, 78, 68),
        Eligibility.PENDING,
    ),
    (
        'noah.uy@footpathcebu.test',
        'Noah',
        'Uy',
        12,
        'Class of 2030',
        AgeTier.FOUNDATION,
        'RW',
        (85, 66, 62, 82, 38, 60),
        Eligibility.ACADEMIC_WARNING,
    ),
    (
        'gabriel.lim@footpathcebu.test',
        'Gabriel',
        'Lim',
        17,
        'Class of 2025',
        AgeTier.PATHWAY,
        'CB',
        (68, 45, 66, 60, 85, 82),
        Eligibility.ELIGIBLE,
    ),
    (
        'ethan.go@footpathcebu.test',
        'Ethan',
        'Go',
        16,
        'Class of 2026',
        AgeTier.PATHWAY,
        'LB',
        (79, 52, 74, 72, 77, 75),
        Eligibility.NOT_ELIGIBLE,
    ),
]

DEMO_CLUB_NAME = 'FootPath Cebu Demo Club'
DEMO_CLUB_SLUG = 'footpath-cebu-demo'


class Command(BaseCommand):
    help = 'Seed player profiles, training, attendance, match statistics, and a guardian link.'

    @transaction.atomic
    def handle(self, *args, **options):
        club, _ = Club.objects.get_or_create(
            name=DEMO_CLUB_NAME,
            defaults={'slug': DEMO_CLUB_SLUG},
        )
        club.is_active = True
        club.is_school_affiliated = True
        club.school_name = DEMO_CLUB_NAME
        club.save(
            update_fields=[
                'is_active',
                'is_school_affiliated',
                'school_name',
            ]
        )

        coach = User.objects.filter(
            email='coach@footpathcebu.test',
            role=Roles.COACH,
        ).first()
        if coach and coach.club_id != club.id:
            coach.club = club
            coach.save(update_fields=['club'])

        # 1. Give the seeded login-player a profile, if present.
        login_player = User.objects.filter(email='player@footpathcebu.test').first()
        if login_player:
            login_player.role = Roles.PLAYER
            login_player.club = club
            login_player.is_active = True
            login_player.save(update_fields=['role', 'club', 'is_active'])
            self._ensure_profile(
                login_player,
                14,
                'Class of 2028',
                AgeTier.DEVELOPMENT,
                'CAM',
                (80, 81, 83, 85, 60, 72),
                Eligibility.ELIGIBLE,
            )

        # 2. Roster players (local-only; fill the coach's squad view).
        players = []
        for email, first, last, age, cls, tier, pos, ratings, elig in ROSTER:
            user, _ = User.objects.update_or_create(
                username=email,
                defaults={
                    'email': email,
                    'first_name': first,
                    'last_name': last,
                    'role': Roles.PLAYER,
                    'club': club,
                    'is_active': True,
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
                player=login_player,
                session=past,
                defaults={'status': AttendanceStatus.PRESENT, 'recorded_by': coach},
            )
        for i, p in enumerate(players[:3]):
            if past:
                Attendance.objects.update_or_create(
                    player=p,
                    session=past,
                    defaults={
                        'status': [
                            AttendanceStatus.PRESENT,
                            AttendanceStatus.ABSENT,
                            AttendanceStatus.EXCUSED,
                        ][i % 3],
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
            GuardianLink.objects.get_or_create(guardian=guardian, player=login_player)

        # 7. A panel-ready tournament workflow. The Coordinator has already
        # published the programme, the Coach has a published squad and one
        # completed group match to rate, and TBD knockout fixtures remain for
        # the Coordinator to update after qualification.
        coordinator = User.objects.filter(
            email='coordinator@footpathcebu.test',
            role=Roles.COORDINATOR,
        ).first()
        if coordinator and coordinator.club_id != club.id:
            coordinator.club = club
            coordinator.save(update_fields=['club'])
        if coordinator and coach and login_player:
            self._seed_rising_star_tournament(
                coordinator=coordinator,
                coach=coach,
                club=club,
                squad_players=[login_player, *players[:3]],
            )
            self._seed_panel_workflows(
                coordinator=coordinator,
                coach=coach,
                guardian=guardian,
                player=login_player,
                sessions=sessions,
            )

        self.stdout.write(
            self.style.SUCCESS(
                f'Seeded {PlayerProfile.objects.count()} player profiles, '
                f'{TrainingSession.objects.count()} sessions, '
                f'{Attendance.objects.count()} attendance records, '
                f'{FootballMatch.objects.count()} matches, and '
                f'{PlayerMatchPerformance.objects.count()} match performances.'
            )
        )

    def _ensure_profile(self, user, age, cls, tier, pos, ratings, elig):
        pace, shooting, passing, dribbling, defending, physical = ratings
        PlayerProfile.objects.update_or_create(
            user=user,
            defaults={
                'date_of_birth': date(date.today().year - age, 1, 1),
                'age': age,
                'class_year': cls,
                'age_tier': tier,
                'position': pos,
                'pace': pace,
                'shooting': shooting,
                'passing': passing,
                'dribbling': dribbling,
                'defending': defending,
                'physical': physical,
                'eligibility': elig,
            },
        )

    def _seed_sessions(self, coach, club):
        today = date.today()
        specs = [
            (
                'Evening Technical Training',
                today + timedelta(days=2),
                '04:30 PM',
                '06:00 PM',
                'Cebu City Sports Complex',
                SessionFocus.TECHNICAL,
                [AgeTier.DEVELOPMENT, AgeTier.PATHWAY],
            ),
            (
                'Foundation Fundamentals',
                today + timedelta(days=5),
                '09:00 AM',
                '10:30 AM',
                'Abellana Field',
                SessionFocus.PHYSICAL,
                [AgeTier.FOUNDATION],
            ),
            (
                'Match Prep & Mentality',
                today - timedelta(days=3),
                '05:00 PM',
                '06:30 PM',
                'Cebu City Sports Complex',
                SessionFocus.MENTAL,
                [AgeTier.DEVELOPMENT, AgeTier.PATHWAY, AgeTier.FOUNDATION],
            ),
        ]
        sessions = []
        for title, d, start, end, loc, focus, tiers in specs:
            session, _ = TrainingSession.objects.update_or_create(
                title=title,
                date=d,
                defaults={
                    'start_time': start,
                    'end_time': end,
                    'location': loc,
                    'focus': focus,
                    'age_tiers': list(tiers),
                    'created_by': coach,
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

    def _seed_rising_star_tournament(self, *, coordinator, coach, club, squad_players):
        """Create the exact Coordinator -> Coach -> knockout demo handoff."""
        today = date.today()

        def kickoff(days_from_today, hour, minute):
            value = datetime.combine(
                today + timedelta(days=days_from_today),
                time(hour=hour, minute=minute),
            )
            return timezone.make_aware(value, timezone.get_current_timezone())

        schedule, _ = TournamentSchedule.objects.update_or_create(
            club=club,
            title='Rising Star Cup — Boys U14',
            defaults={
                'venue': 'Cebu City Sports Center',
                'starts_on': today - timedelta(days=1),
                'uploaded_by': coordinator,
                'is_published': True,
                'published_at': timezone.now(),
            },
        )
        bracket, _ = TournamentAgeBracket.objects.update_or_create(
            schedule=schedule,
            max_age=14,
            defaults={
                'scheduled_at': kickoff(-1, 13, 0),
                'academy_tiers': [AgeTier.FOUNDATION, AgeTier.DEVELOPMENT],
            },
        )
        squad, _ = TournamentSquad.objects.update_or_create(
            bracket=bracket,
            defaults={
                'status': TournamentSquadStatus.PUBLISHED,
                'published_at': timezone.now(),
                'updated_by': coach,
            },
        )
        for player in squad_players:
            profile = getattr(player, 'player_profile', None)
            TournamentSquadEntry.objects.update_or_create(
                squad=squad,
                player=player,
                defaults={
                    'position': profile.position if profile else '',
                    'added_by': coach,
                },
            )

        completed_match, _ = FootballMatch.objects.update_or_create(
            club=club,
            competition=schedule.title,
            opponent='Danao City FC',
            played_on=today - timedelta(days=1),
            defaults={
                'venue': MatchVenue.NEUTRAL,
                'category': MatchCategory.TOURNAMENT,
                'our_score': 2,
                'opponent_score': 1,
                'created_by': coordinator,
            },
        )
        completed_fixture, _ = TournamentFixture.objects.update_or_create(
            schedule=schedule,
            stage='Group A · Match 1',
            defaults={
                'age_bracket': bracket,
                'opponent': 'Danao City FC',
                'kickoff_at': kickoff(-1, 13, 0),
                'ends_at': kickoff(-1, 13, 15),
                'venue': MatchVenue.NEUTRAL,
                'location': 'Pitch 1',
                'status': FixtureStatus.COMPLETED,
                'completed_match': completed_match,
            },
        )

        for index, player in enumerate(squad_players[:3]):
            position = player.player_profile.position or 'CM'
            is_goalkeeper = position == 'GK'
            PlayerMatchPerformance.objects.update_or_create(
                match=completed_match,
                player=player,
                defaults={
                    'position': position,
                    'starter': True,
                    'minutes_played': 15,
                    'goals': 1 if index < 2 else 0,
                    'assists': 1 if index == 2 else 0,
                    'shots': 2 if not is_goalkeeper else 0,
                    'shots_on_target': 1 if not is_goalkeeper else 0,
                    'passes_attempted': 12,
                    'passes_completed': 9,
                    'tackles': 2,
                    'interceptions': 1,
                    'saves': 3 if is_goalkeeper else 0,
                    'goals_conceded': 1 if is_goalkeeper else 0,
                    'clean_sheet': False,
                    # Intentionally unrated: this is the Coach's panel-demo task.
                    'coach_rating': None,
                    'notes': '',
                    'recorded_by': coordinator,
                    'rated_by': None,
                    'rated_at': None,
                },
            )

        fixture_specs = [
            ('Group A · Match 2', 'Giuseppe FC', 0, 13, 18, 'Pitch 1'),
            ('Group A · Match 3', 'Lo-ok FC', 0, 15, 6, 'Pitch 1'),
            ('Semifinal', 'TBD', 1, 15, 42, 'Pitch 3'),
            ('Championship', 'TBD', 1, 15, 50, 'Pitch 3'),
        ]
        for stage, opponent, day_offset, hour, minute, location in fixture_specs:
            starts_at = kickoff(day_offset, hour, minute)
            TournamentFixture.objects.update_or_create(
                schedule=schedule,
                stage=stage,
                defaults={
                    'age_bracket': bracket,
                    'opponent': opponent,
                    'kickoff_at': starts_at,
                    'ends_at': starts_at + timedelta(minutes=15),
                    'venue': MatchVenue.NEUTRAL,
                    'location': location,
                    'status': FixtureStatus.SCHEDULED,
                    'completed_match': None,
                },
            )

        return completed_fixture

    def _seed_panel_workflows(self, *, coordinator, coach, guardian, player, sessions):
        """Seed visible records for the remaining role-specific demo flows."""
        profile = player.player_profile
        framework = framework_for(profile.age_tier, profile.position)
        profile.development_framework_version = FRAMEWORK_VERSION
        profile.development_scores = {
            domain['key']: {
                indicator['key']: 4 if index % 2 == 0 else 3
                for index, indicator in enumerate(domain['indicators'])
            }
            for domain in framework['domains']
        }
        profile.development_strengths = (
            'Scans early, receives on the half-turn, and supports teammates.'
        )
        profile.development_targets = (
            'Improve weaker-foot passing and recovery runs after turnovers.'
        )
        profile.development_assessed_at = timezone.now()
        profile.coach_notes = 'Panel demo assessment; safe to update during the demo.'
        profile.save(
            update_fields=[
                'development_framework_version',
                'development_scores',
                'development_strengths',
                'development_targets',
                'development_assessed_at',
                'coach_notes',
            ]
        )
        if not PlayerDevelopmentAssessment.objects.filter(
            player=player,
            framework_version=FRAMEWORK_VERSION,
        ).exists():
            PlayerDevelopmentAssessment.from_profile(
                profile,
                assessed_by=coach,
                reason='GENERAL_REVIEW',
            )

        PlayerPrivacyPin.objects.update_or_create(
            player=player,
            defaults={
                'pin_hash': make_password('2468'),
                'failed_attempts': 0,
                'locked_until': None,
            },
        )
        upcoming = next((session for session in sessions if session.date >= date.today()), None)
        if upcoming:
            SessionConfirmation.objects.update_or_create(
                player=player,
                session=upcoming,
                defaults={'status': ConfirmationStatus.CONFIRMED},
            )

        InjuryRecord.objects.update_or_create(
            player=player,
            description='Mild ankle discomfort after group-stage match',
            defaults={
                'body_part': 'Right ankle',
                'status': InjuryStatus.RECOVERING,
                'occurred_on': date.today() - timedelta(days=1),
                'notes': 'Guardian submitted the report; Coordinator review is pending.',
                'reported_by': guardian or player,
                'review_status': InjuryReportStatus.PENDING,
                'reviewed_by': None,
                'reviewed_at': None,
            },
        )
        Dispute.objects.update_or_create(
            raised_by=coach,
            subject_player=player,
            summary='Review the recorded group-stage attendance',
            defaults={
                'category': DisputeCategory.ATTENDANCE,
                'status': DisputeStatus.OPEN,
                'detail': (
                    'The Coach flagged this demo record so School Staff can '
                    'show the review and response workflow.'
                ),
            },
        )
        for user, event_type, title, body in [
            (
                coordinator,
                'tournament.knockout_pending',
                'Knockout fixture needs an opponent',
                'Update the Rising Star Cup semifinal after group qualification.',
            ),
            (
                coach,
                'match.rating_pending',
                'Player ratings are ready',
                'Rate the squad from the completed match against Danao City FC.',
            ),
            (
                player,
                'training.reminder',
                'Upcoming training',
                'Your next FootPath Cebu Demo Club session is scheduled.',
            ),
            (
                guardian,
                'injury.review_pending',
                'Injury report submitted',
                'The Coordinator has been asked to review the ankle report.',
            ),
        ]:
            if user is None:
                continue
            NotificationRecord.objects.update_or_create(
                user=user,
                event_type=event_type,
                title=title,
                defaults={'body': body, 'data': {'demo': True}},
            )
