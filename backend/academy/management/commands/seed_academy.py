"""Populate academy demo data: player profiles, a training schedule, attendance,
and a guardian link — so a fresh database (SQLite or Supabase) demos the coach,
player, and guardian dashboards immediately.

Idempotent: safe to rerun. Assumes `seed_users` has already created the
role login accounts. The extra roster players created here are local-only (no
Firebase login) — they exist to fill the coach's roster; the login demos use
the seed_users accounts.
"""

from datetime import date, datetime, time, timedelta
from decimal import Decimal

from django.contrib.auth.hashers import make_password
from django.core.management.base import BaseCommand
from django.db import models, transaction
from django.utils import timezone

from academy.assessment_framework import FRAMEWORK_VERSION, framework_for
from academy.models import (
    AgeTier,
    Attendance,
    AttendanceStatus,
    AuditLog,
    ConfirmationStatus,
    Dispute,
    DisputeCategory,
    DisputeResponse,
    DisputeStatus,
    Eligibility,
    EligibilityHistory,
    FixtureStatus,
    FootballMatch,
    InjuryRecord,
    InjuryReportStatus,
    InjurySeverity,
    InjuryStatus,
    InjuryStatusUpdateRequest,
    InjuryType,
    InjuryUpdateReviewStatus,
    MatchCategory,
    MatchVenue,
    NotificationRecord,
    PlayerAssessmentSnapshot,
    PlayerDevelopmentAssessment,
    PlayerMatchPerformance,
    PlayerPrivacyPin,
    PlayerProfile,
    PlayerStatsAssessment,
    SessionConfirmation,
    SessionFocus,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
    TrainingSession,
    TrainingSessionStatus,
)
from academy.player_stats import CATALOG_VERSION, overall, role_group_for, score_keys
from accounts.models import Club, GuardianLink, Roles, User

# (email, first, last, age, tier, position, ratings, eligibility)
ROSTER = [
    (
        'miguel.reyes@footpathcebu.test',
        'Miguel',
        'Reyes',
        14,
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
        AgeTier.PATHWAY,
        'LB',
        (79, 52, 74, 72, 77, 75),
        Eligibility.NOT_ELIGIBLE,
    ),
]

DEMO_CLUB_NAME = 'FootPath Cebu Demo Club'
DEMO_CLUB_SLUG = 'footpath-cebu-demo'
TOURNAMENT_TITLE = 'Rising Star Cup — Boys U14'
LOGIN_EMAILS = (
    'admin@footpathcebu.test',
    'coordinator@footpathcebu.test',
    'coach@footpathcebu.test',
    'player@footpathcebu.test',
    'guardian@footpathcebu.test',
)
ROSTER_EMAILS = tuple(row[0] for row in ROSTER)
DEMO_EMAILS = (*LOGIN_EMAILS, *ROSTER_EMAILS)
DEMO_PLAYER_EMAILS = ('player@footpathcebu.test', *ROSTER_EMAILS)
ROSTER_CONTACTS = {
    'miguel.reyes@footpathcebu.test': ('A', '+639172000001'),
    'paolo.cruz@footpathcebu.test': ('B', '+639172000002'),
    'liam.tan@footpathcebu.test': ('C', '+639172000003'),
    'noah.uy@footpathcebu.test': ('D', '+639172000004'),
    'gabriel.lim@footpathcebu.test': ('E', '+639172000005'),
    'ethan.go@footpathcebu.test': ('F', '+639172000006'),
}
SESSION_TITLES = (
    'Evening Technical Training',
    'Foundation Fundamentals',
    'Tactical Shape & Set Pieces',
    'Match Prep & Mentality',
    'Pressing and Transition Review',
    'Weather-Cancelled Conditioning',
)
MATCH_OPPONENTS = ('Cebu United', 'Mandaue FC', 'Danao City FC')
INJURY_DESCRIPTIONS = (
    'Mild ankle discomfort after group-stage match',
    'Recovering left hamstring strain',
)
DISPUTE_SUMMARIES = (
    'Review the recorded group-stage attendance',
    'Clarify preseason eligibility decision',
)


def birth_date_for_age(age):
    today = date.today()
    try:
        return today.replace(year=today.year - age)
    except ValueError:
        return today.replace(year=today.year - age, day=28)


def class_year_for_age(age):
    return f'Class of {date.today().year + max(1, 18 - age)}'


class Command(BaseCommand):
    help = 'Seed player profiles, training, attendance, match statistics, and a guardian link.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--refresh',
            action='store_true',
            help='Remove and rebuild only canonical FootPath demo records.',
        )

    @transaction.atomic
    def handle(self, *args, **options):
        club, _ = Club.objects.get_or_create(
            name=DEMO_CLUB_NAME,
            defaults={'slug': DEMO_CLUB_SLUG},
        )
        if options.get('refresh'):
            self._refresh_demo_data(club)

        club.slug = DEMO_CLUB_SLUG
        club.is_active = True
        club.is_school_affiliated = True
        club.school_name = DEMO_CLUB_NAME
        club.head_coach_name = 'Marco L. Villanueva'
        club.cvfa_membership = 'CVFA-DEMO-2026'
        club.save(
            update_fields=[
                'slug',
                'is_active',
                'is_school_affiliated',
                'school_name',
                'head_coach_name',
                'cvfa_membership',
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
                class_year_for_age(14),
                AgeTier.DEVELOPMENT,
                'CAM',
                (80, 81, 83, 85, 60, 72),
                Eligibility.ELIGIBLE,
            )

        # 2. Roster players (local-only; fill the coach's squad view).
        players = []
        for email, first, last, age, tier, pos, ratings, elig in ROSTER:
            middle_initial, mobile_number = ROSTER_CONTACTS[email]
            user, _ = User.objects.update_or_create(
                username=email,
                defaults={
                    'email': email,
                    'first_name': first,
                    'last_name': last,
                    'middle_initial': middle_initial,
                    'mobile_number': mobile_number,
                    'role': Roles.PLAYER,
                    'club': club,
                    'is_active': True,
                    'firebase_uid': None,
                },
            )
            user.set_unusable_password()
            user.save(update_fields=['password'])
            self._ensure_profile(
                user,
                age,
                class_year_for_age(age),
                tier,
                pos,
                ratings,
                elig,
            )
            players.append(user)

        # 3. Training schedule covers upcoming, completed, and cancelled UI states.
        sessions = self._seed_sessions(coach, club)

        # 4. Complete roll calls make progress and attendance history useful.
        all_players = [player for player in [login_player, *players] if player]
        self._seed_attendance(coach, sessions, all_players)

        # 5. Completed league history for every demo player profile.
        self._seed_matches(coach, club, all_players)

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
                roster_players=players,
                sessions=sessions,
            )
            self._seed_audit_entries(
                coordinator=coordinator,
                coach=coach,
                player=login_player,
            )

        demo_users = User.objects.filter(email__in=DEMO_EMAILS)
        self.stdout.write(
            self.style.SUCCESS(
                f'Seeded {demo_users.count()} demo users, '
                f'{PlayerProfile.objects.filter(user__email__in=DEMO_PLAYER_EMAILS).count()} '
                f'player profiles, '
                f'{TrainingSession.objects.filter(club=club, title__in=SESSION_TITLES).count()} '
                f'sessions, '
                f'{Attendance.objects.filter(player__email__in=DEMO_PLAYER_EMAILS).count()} '
                f'attendance records, and '
                f'{FootballMatch.objects.filter(club=club, opponent__in=MATCH_OPPONENTS).count()} '
                f'matches.'
            )
        )

    def _refresh_demo_data(self, club):
        """Delete only records owned by the canonical deterministic fixture."""
        player_ids = list(
            User.objects.filter(email__in=DEMO_PLAYER_EMAILS).values_list('id', flat=True)
        )
        user_ids = list(User.objects.filter(email__in=DEMO_EMAILS).values_list('id', flat=True))

        seeded_sessions = TrainingSession.objects.filter(
            club=club,
            title__in=SESSION_TITLES,
        )
        Attendance.objects.filter(session__in=seeded_sessions).delete()
        SessionConfirmation.objects.filter(session__in=seeded_sessions).delete()
        seeded_sessions.delete()

        seeded_tournaments = TournamentSchedule.objects.filter(
            club=club,
            title=TOURNAMENT_TITLE,
        )
        TournamentFixture.objects.filter(schedule__in=seeded_tournaments).delete()
        seeded_tournaments.delete()
        FootballMatch.objects.filter(club=club).filter(
            models.Q(
                competition='Cebu Youth League',
                opponent__in=('Cebu United', 'Mandaue FC'),
            )
            | models.Q(competition=TOURNAMENT_TITLE, opponent='Danao City FC')
        ).delete()

        if player_ids:
            PlayerDevelopmentAssessment.objects.filter(player_id__in=player_ids).delete()
            PlayerAssessmentSnapshot.objects.filter(player_id__in=player_ids).delete()
            PlayerStatsAssessment.objects.filter(player_id__in=player_ids).delete()
            EligibilityHistory.objects.filter(player_id__in=player_ids).delete()
            PlayerPrivacyPin.objects.filter(player_id__in=player_ids).delete()
            InjuryRecord.objects.filter(
                player_id__in=player_ids,
                description__in=INJURY_DESCRIPTIONS,
            ).delete()

        Dispute.objects.filter(summary__in=DISPUTE_SUMMARIES).filter(
            models.Q(raised_by_id__in=user_ids) | models.Q(subject_player_id__in=player_ids)
        ).delete()
        NotificationRecord.objects.filter(
            user_id__in=user_ids,
            data__demo=True,
        ).delete()
        GuardianLink.objects.filter(
            guardian__email='guardian@footpathcebu.test',
            player__email='player@footpathcebu.test',
        ).delete()

    def _ensure_profile(self, user, age, cls, tier, pos, ratings, elig):
        pace, shooting, passing, dribbling, defending, physical = ratings
        goalkeeper_ratings = (74, 72, 68, 80, 65, 76) if pos == 'GK' else (0, 0, 0, 0, 0, 0)
        defaults = {
            'middle_initial': user.middle_initial or '',
            'date_of_birth': birth_date_for_age(age),
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
            'diving': goalkeeper_ratings[0],
            'handling': goalkeeper_ratings[1],
            'kicking': goalkeeper_ratings[2],
            'reflexes': goalkeeper_ratings[3],
            'speed': goalkeeper_ratings[4],
            'positioning': goalkeeper_ratings[5],
            'eligibility': elig,
        }
        profile, created = PlayerProfile.objects.get_or_create(user=user, defaults=defaults)
        if not created:
            # The deterministic fixture writes its own two-row eligibility history
            # below. A direct update avoids manufacturing notification/outbox rows
            # while restoring an edited demo profile.
            PlayerProfile.objects.filter(pk=profile.pk).update(**defaults)

    def _seed_sessions(self, coach, club):
        today = date.today()
        specs = [
            {
                'title': 'Evening Technical Training',
                'date': today + timedelta(days=2),
                'start_time': '04:30 PM',
                'end_time': '06:00 PM',
                'location': 'Cebu City Sports Complex',
                'focus': SessionFocus.TECHNICAL,
                'additional_focuses': [SessionFocus.TACTICAL],
                'age_tiers': [AgeTier.DEVELOPMENT, AgeTier.PATHWAY],
                'session_objectives': 'Improve first touch, scanning, and combination play.',
                'equipment_requirements': 'Balls, cones, bibs, and mini goals.',
                'coach_instructions': 'Arrive 20 minutes early for pitch setup.',
                'status': TrainingSessionStatus.SCHEDULED,
            },
            {
                'title': 'Foundation Fundamentals',
                'date': today + timedelta(days=5),
                'start_time': '09:00 AM',
                'end_time': '10:30 AM',
                'location': 'Abellana Field',
                'focus': SessionFocus.PHYSICAL,
                'additional_focuses': [SessionFocus.TECHNICAL],
                'age_tiers': [AgeTier.FOUNDATION],
                'session_objectives': 'Build balance, coordination, and confident ball mastery.',
                'equipment_requirements': 'Size-four balls, cones, ladders, and water.',
                'coach_instructions': 'Use short activity blocks and frequent water breaks.',
                'status': TrainingSessionStatus.SCHEDULED,
            },
            {
                'title': 'Tactical Shape & Set Pieces',
                'date': today + timedelta(days=8),
                'start_time': '04:00 PM',
                'end_time': '05:45 PM',
                'location': 'Cebu City Sports Complex',
                'focus': SessionFocus.TACTICAL,
                'additional_focuses': [SessionFocus.MATCH_PREPARATION],
                'age_tiers': list(AgeTier.values),
                'session_objectives': 'Rehearse team shape, restarts, and transition roles.',
                'equipment_requirements': 'Full goals, mannequins, bibs, and match balls.',
                'coach_instructions': 'Prepare separate restart roles for each age tier.',
                'status': TrainingSessionStatus.SCHEDULED,
            },
            {
                'title': 'Match Prep & Mentality',
                'date': today - timedelta(days=3),
                'start_time': '05:00 PM',
                'end_time': '06:30 PM',
                'location': 'Cebu City Sports Complex',
                'focus': SessionFocus.MENTAL,
                'additional_focuses': [SessionFocus.MATCH_PREPARATION],
                'age_tiers': list(AgeTier.values),
                'session_objectives': 'Practice match routines and responses to setbacks.',
                'equipment_requirements': 'Bibs, cones, tactics board, and match balls.',
                'coach_instructions': 'Record complete attendance and player observations.',
                'status': TrainingSessionStatus.COMPLETED,
            },
            {
                'title': 'Pressing and Transition Review',
                'date': today - timedelta(days=10),
                'start_time': '04:30 PM',
                'end_time': '06:00 PM',
                'location': 'Cebu City Sports Complex',
                'focus': SessionFocus.TACTICAL,
                'additional_focuses': [SessionFocus.PHYSICAL],
                'age_tiers': list(AgeTier.values),
                'session_objectives': 'Coordinate pressing triggers and recovery runs.',
                'equipment_requirements': 'Cones, bibs, balls, and GPS vests when available.',
                'coach_instructions': 'Capture effort and performance scores for the full roster.',
                'status': TrainingSessionStatus.COMPLETED,
            },
            {
                'title': 'Weather-Cancelled Conditioning',
                'date': today + timedelta(days=1),
                'start_time': '04:30 PM',
                'end_time': '05:45 PM',
                'location': 'Abellana Field',
                'focus': SessionFocus.PHYSICAL,
                'additional_focuses': [],
                'age_tiers': list(AgeTier.values),
                'session_objectives': 'Develop safe football-specific conditioning.',
                'equipment_requirements': 'Cones, hurdles, and hydration stations.',
                'coach_instructions': 'Cancelled demo state; do not conduct this session.',
                'status': TrainingSessionStatus.CANCELLED,
                'cancellation_reason': 'Pitch closed because of severe weather.',
                'cancelled_at': timezone.now(),
                'cancelled_by_action': 'DEMO_WEATHER_CLOSURE',
            },
        ]
        sessions = {}
        for spec in specs:
            title = spec['title']
            defaults = dict(spec)
            defaults.pop('title')
            defaults.update(created_by=coach, club=club)
            session, _ = TrainingSession.objects.update_or_create(
                title=title,
                club=club,
                defaults=defaults,
            )
            sessions[title] = session
        return sessions

    def _seed_attendance(self, coach, sessions, players):
        if not players:
            return
        roll_calls = {
            'Match Prep & Mentality': [
                (AttendanceStatus.PRESENT, 88, '8.6', 'Sharp decisions and consistent effort.'),
                (AttendanceStatus.PRESENT, 82, '8.0', 'Strong finishing movement.'),
                (AttendanceStatus.ABSENT, None, None, 'Absent without performance scoring.'),
                (AttendanceStatus.EXCUSED, None, None, 'School commitment was approved.'),
                (AttendanceStatus.PRESENT, 75, '7.2', 'Positive wide runs throughout.'),
                (AttendanceStatus.PRESENT, 84, '8.1', 'Reliable defensive communication.'),
                (AttendanceStatus.ABSENT, None, None, 'Unavailable for this session.'),
            ],
            'Pressing and Transition Review': [
                (AttendanceStatus.PRESENT, 91, '9.0', 'Led pressing triggers intelligently.'),
                (AttendanceStatus.EXCUSED, None, None, 'Family commitment was approved.'),
                (AttendanceStatus.PRESENT, 79, '7.8', 'Good support angles in transition.'),
                (AttendanceStatus.PRESENT, 87, '8.4', 'Confident handling and distribution.'),
                (AttendanceStatus.ABSENT, None, None, 'Absent without performance scoring.'),
                (AttendanceStatus.PRESENT, 76, '7.5', 'Stayed compact and competed well.'),
                (AttendanceStatus.PRESENT, 80, '7.7', 'Recovered position consistently.'),
            ],
        }
        for title, records in roll_calls.items():
            session = sessions[title]
            for player, (status, effort, score, note) in zip(players, records):
                Attendance.objects.update_or_create(
                    player=player,
                    session=session,
                    defaults={
                        'status': status,
                        'effort': effort,
                        'performance_score': Decimal(score) if score else None,
                        'note': note,
                        'recorded_by': coach,
                    },
                )
            session.attendance_revision = 1
            session.save(update_fields=['attendance_revision'])

    def _seed_matches(self, coach, club, players):
        specs = [
            ('Cebu United', 7, 'HOME', 3, 1, Decimal('8.7'), 2, 1),
            ('Mandaue FC', 21, 'AWAY', 1, 1, Decimal('7.4'), 0, 1),
        ]
        for opponent, days_ago, venue, ours, theirs, rating, goals, assists in specs:
            match, _ = FootballMatch.objects.update_or_create(
                club=club,
                competition='Cebu Youth League',
                opponent=opponent,
                defaults={
                    'played_on': date.today() - timedelta(days=days_ago),
                    'venue': venue,
                    'category': MatchCategory.LEAGUE,
                    'our_score': ours,
                    'opponent_score': theirs,
                    'created_by': coach,
                },
            )
            for index, player in enumerate(players):
                profile = player.player_profile
                player_rating = max(Decimal('6.5'), rating - Decimal(index) / Decimal('10'))
                player_goals = goals if index == 0 else (1 if index == 1 and ours > 1 else 0)
                player_assists = assists if index == 0 else (1 if index == 2 and ours > 1 else 0)
                is_goalkeeper = profile.position == 'GK'
                PlayerMatchPerformance.objects.update_or_create(
                    match=match,
                    player=player,
                    defaults={
                        'position': profile.position or 'CM',
                        'starter': True,
                        'minutes_played': 80,
                        'goals': player_goals,
                        'assists': player_assists,
                        'shots': 0 if is_goalkeeper else max(player_goals, 3 + (index % 3)),
                        'shots_on_target': (
                            0
                            if is_goalkeeper
                            else max(player_goals, 1 + (index % 2))
                        ),
                        'passes_attempted': 24 + index * 2,
                        'passes_completed': 18 + index,
                        'tackles': 0 if is_goalkeeper else 1 + (index % 3),
                        'interceptions': 0 if is_goalkeeper else index % 2,
                        'saves': 5 if is_goalkeeper else 0,
                        'goals_conceded': theirs if is_goalkeeper else 0,
                        'clean_sheet': is_goalkeeper and theirs == 0,
                        'coach_rating': player_rating,
                        'notes': 'Completed league performance for demo history.',
                        'recorded_by': coach,
                        'rated_by': coach,
                        'rated_at': timezone.now() - timedelta(days=days_ago - 1),
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
            title=TOURNAMENT_TITLE,
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
            competition=TOURNAMENT_TITLE,
            opponent='Danao City FC',
            defaults={
                'played_on': today - timedelta(days=1),
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

        for index, player in enumerate(squad_players):
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

    def _seed_panel_workflows(
        self,
        *,
        coordinator,
        coach,
        guardian,
        player,
        roster_players,
        sessions,
    ):
        """Seed visible records for every role-specific demo workflow."""
        profile = player.player_profile
        assessed_at = timezone.now()
        self._seed_development_assessments(profile, coach, assessed_at=assessed_at)
        self._seed_rating_history(profile, coach)
        self._seed_player_stats(profile, coach)
        # Every card in the demo roster must open into useful data. This keeps
        # Coordinator testing representative instead of giving only the login
        # player assessment history while the six roster-only profiles are empty.
        for roster_player in roster_players:
            roster_profile = roster_player.player_profile
            self._seed_development_assessments(
                roster_profile,
                coach,
                assessed_at=assessed_at,
            )
            self._seed_rating_history(roster_profile, coach)
            self._seed_player_stats(roster_profile, coach)

        PlayerPrivacyPin.objects.update_or_create(
            player=player,
            defaults={
                'pin_hash': make_password('2468'),
                'failed_attempts': 0,
                'locked_until': None,
            },
        )
        SessionConfirmation.objects.update_or_create(
            player=player,
            session=sessions['Evening Technical Training'],
            defaults={'status': ConfirmationStatus.CONFIRMED},
        )
        if roster_players:
            SessionConfirmation.objects.update_or_create(
                player=roster_players[0],
                session=sessions['Tactical Shape & Set Pieces'],
                defaults={'status': ConfirmationStatus.DECLINED},
            )

        InjuryRecord.objects.update_or_create(
            player=player,
            description='Mild ankle discomfort after group-stage match',
            defaults={
                'injury_type': InjuryType.JOINT_LIGAMENT,
                'severity': InjurySeverity.MINOR,
                'body_part': 'Right ankle',
                'status': InjuryStatus.RECOVERING,
                'occurred_on': date.today() - timedelta(days=1),
                'resolved_on': None,
                'notes': 'Guardian submitted the report; Coordinator review is pending.',
                'reported_by': guardian or player,
                'review_status': InjuryReportStatus.PENDING,
                'reviewed_by': None,
                'reviewed_at': None,
                'rejection_reason': '',
                'archived_at': None,
            },
        )
        confirmed_injury, _ = InjuryRecord.objects.update_or_create(
            player=player,
            description='Recovering left hamstring strain',
            defaults={
                'injury_type': InjuryType.MUSCLE,
                'severity': InjurySeverity.MODERATE,
                'body_part': 'Left hamstring',
                'status': InjuryStatus.ACTIVE,
                'occurred_on': date.today() - timedelta(days=14),
                'resolved_on': None,
                'notes': 'Confirmed care-team record with a recovery update to review.',
                'reported_by': coach,
                'review_status': InjuryReportStatus.CONFIRMED,
                'reviewed_by': coordinator,
                'reviewed_at': timezone.now() - timedelta(days=12),
                'rejection_reason': '',
                'archived_at': None,
            },
        )
        InjuryStatusUpdateRequest.objects.update_or_create(
            injury=confirmed_injury,
            review_status=InjuryUpdateReviewStatus.PENDING,
            defaults={
                'proposed_status': InjuryStatus.RECOVERING,
                'proposed_resolved_on': None,
                'notes': 'Pain-free in light training; requesting Recovering status.',
                'submitted_by': coach,
                'reviewed_by': None,
                'reviewed_at': None,
                'rejection_reason': '',
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
                    'The Coach flagged this demo record for Coordinator review.'
                ),
            },
        )
        resolved_dispute, _ = Dispute.objects.update_or_create(
            raised_by=coach,
            subject_player=player,
            summary='Clarify preseason eligibility decision',
            defaults={
                'category': DisputeCategory.ELIGIBILITY,
                'status': DisputeStatus.RESOLVED,
                'detail': 'Historical demo thread showing a completed staff review.',
            },
        )
        DisputeResponse.objects.get_or_create(
            dispute=resolved_dispute,
            author=coordinator,
            body='School records were checked and the eligibility flag was corrected.',
            defaults={'status_change_to': DisputeStatus.UNDER_REVIEW},
        )
        DisputeResponse.objects.get_or_create(
            dispute=resolved_dispute,
            author=coach,
            body='The correction is visible in the player profile. Thank you.',
            defaults={'status_change_to': DisputeStatus.RESOLVED},
        )

        self._seed_eligibility_history(player, coordinator)
        self._seed_roster_eligibility_history(roster_players, coordinator)
        self._seed_notifications(coordinator, coach, player, guardian)

    @staticmethod
    def _development_scores(framework, *, high, low):
        return {
            domain['key']: {
                indicator['key']: high if index % 2 == 0 else low
                for index, indicator in enumerate(domain['indicators'])
            }
            for domain in framework['domains']
        }

    def _seed_development_assessments(self, profile, coach, *, assessed_at):
        framework = framework_for(profile.age_tier, profile.position)
        current_scores = self._development_scores(framework, high=4, low=3)
        historical_scores = self._development_scores(framework, high=3, low=2)
        profile.development_framework_version = FRAMEWORK_VERSION
        profile.development_scores = current_scores
        profile.development_strengths = (
            'Scans early, receives on the half-turn, and supports teammates.'
        )
        profile.development_targets = (
            'Improve weaker-foot passing and recovery runs after turnovers.'
        )
        profile.development_assessed_at = assessed_at
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

        historical, created = PlayerDevelopmentAssessment.objects.get_or_create(
            player=profile.user,
            framework_version=FRAMEWORK_VERSION,
            reason='BASELINE',
            defaults={
                'assessed_by': coach,
                'position': profile.position,
                'age_tier': profile.age_tier,
                'age_at_assessment': profile.age,
                'scores': historical_scores,
                'strengths': 'Shows confidence receiving and carrying the ball.',
                'development_targets': 'Scan earlier and communicate before receiving.',
                'coach_notes': 'Demo baseline development review.',
            },
        )
        if created:
            PlayerDevelopmentAssessment.objects.filter(pk=historical.pk).update(
                created_at=assessed_at - timedelta(days=45)
            )
        current, created = PlayerDevelopmentAssessment.objects.get_or_create(
            player=profile.user,
            framework_version=FRAMEWORK_VERSION,
            reason='GENERAL_REVIEW',
            defaults={
                'assessed_by': coach,
                'position': profile.position,
                'age_tier': profile.age_tier,
                'age_at_assessment': profile.age,
                'scores': current_scores,
                'strengths': profile.development_strengths,
                'development_targets': profile.development_targets,
                'coach_notes': profile.coach_notes,
            },
        )
        if created:
            PlayerDevelopmentAssessment.objects.filter(pk=current.pk).update(
                created_at=assessed_at - timedelta(days=2)
            )

    def _seed_rating_history(self, profile, coach):
        base_fields = (
            'pace',
            'shooting',
            'passing',
            'dribbling',
            'defending',
            'physical',
            'diving',
            'handling',
            'kicking',
            'reflexes',
            'speed',
            'positioning',
        )
        current_values = {field: getattr(profile, field) for field in base_fields}
        historical_values = {field: max(0, value - 5) for field, value in current_values.items()}
        now = timezone.now()
        historical, created = PlayerAssessmentSnapshot.objects.get_or_create(
            player=profile.user,
            reason='BASELINE',
            defaults={
                'assessed_by': coach,
                'position': profile.position,
                'coach_notes': 'Demo baseline ratings before the latest training cycle.',
                **historical_values,
            },
        )
        if created:
            PlayerAssessmentSnapshot.objects.filter(pk=historical.pk).update(
                created_at=now - timedelta(days=60)
            )
        current, created = PlayerAssessmentSnapshot.objects.get_or_create(
            player=profile.user,
            reason='GENERAL_REVIEW',
            defaults={
                'assessed_by': coach,
                'position': profile.position,
                'coach_notes': profile.coach_notes,
                **current_values,
            },
        )
        if created:
            PlayerAssessmentSnapshot.objects.filter(pk=current.pk).update(
                created_at=now - timedelta(days=5)
            )

    def _seed_player_stats(self, profile, coach):
        keys = score_keys(profile.position, CATALOG_VERSION)
        now = timezone.now()
        for reason, values, days_ago, notes in (
            (
                'Demo baseline assessment',
                (72, 74, 75, 70, 58, 69),
                50,
                'Baseline Player Stats entry for trend testing.',
            ),
            (
                'Demo monthly review',
                (80, 83, 85, 82, 64, 74),
                4,
                'Improved scanning, passing choices, and repeat effort.',
            ),
        ):
            scores = dict(zip(keys, values))
            assessment, created = PlayerStatsAssessment.objects.get_or_create(
                player=profile.user,
                catalog_version=CATALOG_VERSION,
                reason=reason,
                defaults={
                    'assessed_by': coach,
                    'position': profile.position,
                    'role_group': role_group_for(profile.position),
                    'scores': scores,
                    'overall': overall(scores),
                    'coach_notes': notes,
                },
            )
            if created:
                PlayerStatsAssessment.objects.filter(pk=assessment.pk).update(
                    created_at=now - timedelta(days=days_ago)
                )

    @staticmethod
    def _seed_eligibility_history(player, coordinator):
        now = timezone.now()
        transitions = (
            (Eligibility.PENDING, Eligibility.ACADEMIC_WARNING, 30),
            (Eligibility.ACADEMIC_WARNING, Eligibility.ELIGIBLE, 7),
        )
        for old_status, new_status, days_ago in transitions:
            history, created = EligibilityHistory.objects.get_or_create(
                player=player,
                old_status=old_status,
                new_status=new_status,
                defaults={'changed_by': coordinator},
            )
            if created:
                EligibilityHistory.objects.filter(pk=history.pk).update(
                    changed_at=now - timedelta(days=days_ago)
                )

    @staticmethod
    def _seed_roster_eligibility_history(players, coordinator):
        now = timezone.now()
        for index, player in enumerate(players):
            status = player.player_profile.eligibility
            is_initial_pending = status == Eligibility.PENDING
            history, created = EligibilityHistory.objects.get_or_create(
                player=player,
                old_status='' if is_initial_pending else Eligibility.PENDING,
                new_status=status,
                defaults={
                    'changed_by': None if is_initial_pending else coordinator,
                },
            )
            if created:
                EligibilityHistory.objects.filter(pk=history.pk).update(
                    changed_at=now - timedelta(days=21 - index)
                )

    @staticmethod
    def _seed_notifications(coordinator, coach, player, guardian):
        now = timezone.now()
        specs = (
            (
                coordinator,
                'tournament.knockout_pending',
                'Knockout fixture needs an opponent',
                'Update the Rising Star Cup semifinal after group qualification.',
                False,
            ),
            (
                coordinator,
                'club.demo_ready',
                'Demo club is ready',
                'All role accounts and roster records are available.',
                True,
            ),
            (
                coach,
                'match.rating_pending',
                'Player ratings are ready',
                'Rate the squad from the completed match against Danao City FC.',
                False,
            ),
            (
                coach,
                'training.assigned',
                'Training plan assigned',
                'The next technical session is ready for delivery.',
                True,
            ),
            (
                player,
                'training.reminder',
                'Upcoming training',
                'Your next FootPath Cebu Demo Club session is scheduled.',
                False,
            ),
            (
                player,
                'eligibility.changed',
                'Eligibility updated',
                'Your current status is Eligible.',
                True,
            ),
            (
                guardian,
                'injury.review_pending',
                'Injury report submitted',
                'The Coordinator has been asked to review the ankle report.',
                False,
            ),
            (
                guardian,
                'guardian.link_ready',
                'Player access is ready',
                'Use the demo privacy PIN to view the linked player.',
                True,
            ),
        )
        for user, event_type, title, body, is_read in specs:
            if user is None:
                continue
            NotificationRecord.objects.update_or_create(
                user=user,
                event_type=event_type,
                title=title,
                defaults={
                    'body': body,
                    'data': {'demo': True},
                    'read_at': now - timedelta(hours=1) if is_read else None,
                },
            )

    @staticmethod
    def _seed_audit_entries(*, coordinator, coach, player):
        entries = (
            (coordinator, 'demo.club_ready', DEMO_CLUB_SLUG, 'School club configured'),
            (coordinator, 'demo.accounts_ready', DEMO_CLUB_SLUG, 'Supported login roles available'),
            (coach, 'demo.sessions_ready', DEMO_CLUB_SLUG, 'Training and attendance ready'),
            (coordinator, 'demo.tournament_ready', TOURNAMENT_TITLE, 'Published U14 workflow'),
            (coach, 'demo.care_ready', player.email, 'Injury review scenarios ready'),
            (coordinator, 'demo.academic_ready', player.email, 'Eligibility and disputes ready'),
        )
        for actor, action, target, detail in entries:
            if not AuditLog.objects.filter(
                action=action,
                target=target,
                detail=detail,
            ).exists():
                AuditLog.record(actor, action, target=target, detail=detail)
