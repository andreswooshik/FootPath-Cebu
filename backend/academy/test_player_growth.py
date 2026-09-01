"""End-to-end Player Growth history, calculation, and security tests."""
from datetime import date, datetime, timedelta
import importlib
from unittest.mock import patch

from django.apps import apps as django_apps
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import Club, GuardianLink, Roles, User

from .growth import (
    IMPROVING,
    INSUFFICIENT_DATA,
    build_match_growth,
    build_training_groups,
    per_90,
)
from .models import (
    AgeTier,
    AssessmentReason,
    Attendance,
    FootballMatch,
    MatchCategory,
    PlayerAssessmentSnapshot,
    PlayerMatchPerformance,
    PlayerProfile,
    TrainingSession,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
)
from .pin_service import set_pin
from .player_unlock import issue_player_unlock


def _club(name):
    return Club.objects.create(
        name=name,
        slug=name.lower().replace(' ', '-'),
        is_school_affiliated=False,
    )


def _user(email, role, club):
    return User.objects.create(
        username=email,
        email=email,
        firebase_uid=f'growth-{email}',
        role=role,
        club=club,
    )


def _player(email, club, position='CM'):
    user = _user(email, Roles.PLAYER, club)
    PlayerProfile.objects.create(
        user=user,
        age=15,
        age_tier=AgeTier.DEVELOPMENT,
        position=position,
        pace=50,
        shooting=50,
        passing=50,
        dribbling=50,
        defending=50,
        physical=50,
    )
    return user


class AssessmentGrowthTests(APITestCase):
    def setUp(self):
        self.club = _club('Growth Club')
        self.other_club = _club('Other Growth Club')
        self.coach = _user('coach@growth.test', Roles.COACH, self.club)
        self.other_coach = _user(
            'other-coach@growth.test', Roles.COACH, self.other_club
        )
        self.player = _player('player@growth.test', self.club)
        self.url = reverse('player-assessment', args=[self.player.id])

    def _payload(self, pace=60, reason='MONTHLY_REVIEW'):
        return {
            'ratings': {
                'pace': pace,
                'shooting': 51,
                'passing': 52,
                'dribbling': 53,
                'defending': 54,
                'physical': 55,
            },
            'coachNotes': 'Measured monthly review.',
            'assessmentReason': reason,
        }

    def test_real_change_creates_one_typed_snapshot(self):
        self.client.force_authenticate(self.coach)
        response = self.client.put(self.url, self._payload(), format='json')
        self.assertEqual(response.status_code, 200)
        snapshot = PlayerAssessmentSnapshot.objects.get(player=self.player)
        self.assertEqual(snapshot.reason, AssessmentReason.MONTHLY_REVIEW)
        self.assertEqual(snapshot.assessed_by, self.coach)
        self.assertEqual(snapshot.pace, 60)
        self.assertEqual(snapshot.position, 'CM')

    def test_no_op_update_does_not_duplicate_history(self):
        self.client.force_authenticate(self.coach)
        self.client.put(self.url, self._payload(), format='json')
        self.client.put(self.url, self._payload(), format='json')
        self.assertEqual(
            PlayerAssessmentSnapshot.objects.filter(player=self.player).count(),
            1,
        )

    @patch(
        'academy.views.PlayerAssessmentSnapshot.from_profile',
        side_effect=RuntimeError('snapshot write failed'),
    )
    def test_snapshot_failure_rolls_back_current_profile(self, _snapshot):
        self.client.force_authenticate(self.coach)
        with self.assertRaises(RuntimeError):
            self.client.put(self.url, self._payload(pace=88), format='json')
        self.player.player_profile.refresh_from_db()
        self.assertEqual(self.player.player_profile.pace, 50)

    def test_history_is_same_club_and_guardian_pin_protected(self):
        PlayerAssessmentSnapshot.from_profile(
            self.player.player_profile,
            assessed_by=self.coach,
            reason=AssessmentReason.BASELINE,
        )
        history_url = reverse('player-assessment-history', args=[self.player.id])
        self.client.force_authenticate(self.other_coach)
        self.assertEqual(self.client.get(history_url).status_code, 403)

        guardian = _user('guardian@growth.test', Roles.GUARDIAN, self.club)
        GuardianLink.objects.create(guardian=guardian, player=self.player)
        set_pin(self.player, '2468')
        self.client.force_authenticate(guardian)
        self.assertEqual(self.client.get(history_url).status_code, 403)
        token = issue_player_unlock(guardian.id, self.player.id)
        response = self.client.get(history_url, HTTP_X_PLAYER_UNLOCK=token)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data[0]['assessmentReason'], 'BASELINE')


class TrainingPerformanceScoreTests(APITestCase):
    def setUp(self):
        self.club = _club('Training Growth Club')
        self.coach = _user('coach@training-growth.test', Roles.COACH, self.club)
        self.player = _player('player@training-growth.test', self.club)
        self.session = TrainingSession.objects.create(
            title='Technical detail',
            date=date.today(),
            start_time='02:00 PM',
            end_time='03:00 PM',
            location='Pitch 1',
            focus='TECHNICAL',
            age_tiers=[AgeTier.DEVELOPMENT],
            club=self.club,
            created_by=self.coach,
        )
        self.url = reverse('attendance-session', args=[self.session.id])
        self.client.force_authenticate(self.coach)

    def _post(self, record):
        return self.client.post(
            self.url, {'records': [record]}, format='json'
        )

    def test_present_player_accepts_effort_and_performance(self):
        response = self._post({
            'playerId': self.player.id,
            'status': 'PRESENT',
            'effort': 83,
            'performanceScore': 8.4,
            'note': 'Strong first touch.',
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(float(response.data[0]['performanceScore']), 8.4)

    def test_absent_and_excused_normalize_participation_values(self):
        for status in ('ABSENT', 'EXCUSED'):
            response = self._post({
                'playerId': self.player.id,
                'status': status,
                'effort': 95,
                'performanceScore': 9.5,
            })
            self.assertEqual(response.status_code, 200)
            self.assertIsNone(response.data[0]['effort'])
            self.assertIsNone(response.data[0]['performanceScore'])

    def test_old_payload_without_optional_score_stays_valid(self):
        response = self._post({
            'playerId': self.player.id,
            'status': 'PRESENT',
            'effort': 70,
        })
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.data[0]['performanceScore'])

    def test_performance_score_range_is_validated(self):
        response = self._post({
            'playerId': self.player.id,
            'status': 'PRESENT',
            'performanceScore': 10.1,
        })
        self.assertEqual(response.status_code, 400)


class MatchCategoryAndGrowthApiTests(APITestCase):
    def setUp(self):
        self.club = _club('Match Growth Club')
        self.coordinator = _user(
            'coordinator@match-growth.test', Roles.COORDINATOR, self.club
        )
        self.coach = _user('coach@match-growth.test', Roles.COACH, self.club)
        self.player = _player('player@match-growth.test', self.club)

    def _match(self, day, *, category=MatchCategory.OTHER, score=(2, 1)):
        return FootballMatch.objects.create(
            club=self.club,
            opponent=f'Opponent {day}',
            competition='League',
            played_on=date.today() - timedelta(days=day),
            venue='HOME',
            category=category,
            our_score=score[0],
            opponent_score=score[1],
            created_by=self.coordinator,
        )

    def _performance(self, match, *, goals=0, minutes=90, rating=7.0):
        return PlayerMatchPerformance.objects.create(
            match=match,
            player=self.player,
            position='CM',
            starter=True,
            minutes_played=minutes,
            goals=goals,
            shots=goals,
            shots_on_target=goals,
            passes_attempted=20,
            passes_completed=16,
            coach_rating=rating,
        )

    def test_ad_hoc_category_and_fixture_tournament_enforcement(self):
        self.client.force_authenticate(self.coordinator)
        response = self.client.post(
            reverse('football-matches'),
            {
                'opponent': 'Friendly XI',
                'competition': 'Friendly',
                'playedOn': str(date.today()),
                'venue': 'HOME',
                'ourScore': 1,
                'opponentScore': 0,
                'category': 'FRIENDLY',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['category'], 'FRIENDLY')
        invalid = self.client.post(
            reverse('football-matches'),
            {
                'opponent': 'Invalid XI',
                'competition': 'Unknown',
                'playedOn': str(date.today()),
                'venue': 'HOME',
                'ourScore': 1,
                'opponentScore': 0,
                'category': 'CUP',
            },
            format='json',
        )
        self.assertEqual(invalid.status_code, 400)

        schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Cebu Cup',
            starts_on=date.today(),
            uploaded_by=self.coordinator,
        )
        bracket = TournamentAgeBracket.objects.create(
            schedule=schedule, max_age=16
        )
        fixture = TournamentFixture.objects.create(
            schedule=schedule,
            age_bracket=bracket,
            stage='Semi-final',
            opponent='Cup XI',
            kickoff_at=timezone.make_aware(datetime.combine(
                date.today(), datetime.min.time()
            )),
        )
        response = self.client.post(
            reverse('football-matches'),
            {
                'fixtureId': str(fixture.id),
                'ourScore': 3,
                'opponentScore': 2,
                'category': 'LEAGUE',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        fixture.refresh_from_db()
        self.assertIsNone(fixture.completed_match_id)

    def test_growth_filters_group_tournaments_and_handle_zero_minutes(self):
        regular = self._match(1, category=MatchCategory.LEAGUE)
        self._performance(regular, goals=1, minutes=0)
        tournament = self._match(2, category=MatchCategory.TOURNAMENT)
        schedule = TournamentSchedule.objects.create(
            club=self.club, title='Cebu Cup', starts_on=date.today()
        )
        bracket = TournamentAgeBracket.objects.create(schedule=schedule, max_age=16)
        TournamentFixture.objects.create(
            schedule=schedule,
            age_bracket=bracket,
            stage='Final',
            opponent=tournament.opponent,
            kickoff_at=timezone.now(),
            completed_match=tournament,
        )
        self._performance(tournament, goals=1)

        self.client.force_authenticate(self.player)
        response = self.client.get(
            reverse('player-growth', args=[self.player.id]),
            {'range': 'all'},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.data['regularMatches']['summary']['goalsPer90'], None
        )
        group = response.data['tournaments']['groups'][0]
        self.assertEqual(group['tournament'], 'Cebu Cup')
        self.assertEqual(group['ageBracketLabel'], 'U16')
        self.assertEqual(group['teamRecord']['wins'], 1)

    def test_growth_range_and_explicit_dates_filter_every_match_summary(self):
        recent = self._performance(self._match(1), goals=1)
        middle = self._performance(self._match(40), goals=2)
        self._performance(self._match(100), goals=3)
        self.client.force_authenticate(self.player)

        response = self.client.get(
            reverse('player-growth', args=[self.player.id]),
            {'range': 'last30days', 'category': 'regular_match'},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['regularMatches']['sampleSize'], 1)
        self.assertEqual(
            response.data['regularMatches']['history'][0]['id'],
            str(recent.id),
        )

        day = middle.match.played_on.isoformat()
        response = self.client.get(
            reverse('player-growth', args=[self.player.id]),
            {
                'range': 'all',
                'category': 'regular_match',
                'from': day,
                'to': day,
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['regularMatches']['sampleSize'], 1)
        self.assertEqual(
            response.data['regularMatches']['history'][0]['id'],
            str(middle.id),
        )

    def test_growth_is_same_club_and_guardian_pin_protected(self):
        url = reverse('player-growth', args=[self.player.id])
        other_club = _club('Unauthorized Growth Club')
        other_coach = _user(
            'other-coach@match-growth.test', Roles.COACH, other_club
        )
        self.client.force_authenticate(other_coach)
        self.assertEqual(self.client.get(url).status_code, 403)

        guardian = _user(
            'guardian@match-growth.test', Roles.GUARDIAN, self.club
        )
        GuardianLink.objects.create(guardian=guardian, player=self.player)
        set_pin(self.player, '2468')
        self.client.force_authenticate(guardian)
        self.assertEqual(self.client.get(url).status_code, 403)
        token = issue_player_unlock(guardian.id, self.player.id)
        self.assertEqual(
            self.client.get(url, HTTP_X_PLAYER_UNLOCK=token).status_code,
            200,
        )

    def test_all_summary_is_not_truncated_by_history_cap(self):
        for day in range(105):
            self._performance(self._match(day), goals=1)
        self.client.force_authenticate(self.player)
        response = self.client.get(
            reverse('player-match-statistics', args=[self.player.id]),
            {'range': 'all'},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['summary']['matchesPlayed'], 105)
        self.assertEqual(len(response.data['performances']), 100)

    def test_growth_endpoint_query_count_is_bounded(self):
        for day in range(6):
            self._performance(self._match(day), goals=day % 2)
        self.client.force_authenticate(self.coach)
        with CaptureQueriesContext(connection) as queries:
            response = self.client.get(
                reverse('player-growth', args=[self.player.id]),
                {'range': 'all'},
            )
        self.assertEqual(response.status_code, 200)
        self.assertLessEqual(len(queries), 10)


class GrowthCalculationTests(APITestCase):
    def test_per_90_never_divides_zero_minutes(self):
        self.assertIsNone(per_90(3, 0))

    def test_equal_windows_classify_direction_and_insufficient_data(self):
        club = _club('Calculation Club')
        coordinator = _user('coordinator@calc.test', Roles.COORDINATOR, club)
        player = _player('player@calc.test', club)
        rows = []
        for index, goals in enumerate((2, 2, 0, 0)):
            match = FootballMatch.objects.create(
                club=club,
                opponent=f'Calc {index}',
                played_on=date.today() - timedelta(days=index),
                venue='HOME',
                our_score=4,
                opponent_score=0,
                created_by=coordinator,
            )
            rows.append(PlayerMatchPerformance.objects.create(
                match=match,
                player=player,
                position='CM',
                minutes_played=90,
                goals=goals,
                shots=goals,
                shots_on_target=goals,
            ))
        growth = build_match_growth(rows)
        self.assertEqual(
            growth['metrics']['goalsPer90']['classification'], IMPROVING
        )
        self.assertEqual(
            build_match_growth(rows[:1])['metrics']['goalsPer90']['classification'],
            INSUFFICIENT_DATA,
        )

    def test_legacy_training_history_uses_effort_for_its_trend(self):
        club = _club('Legacy Training Calculation Club')
        coach = _user('coach@legacy-training.test', Roles.COACH, club)
        player = _player('player@legacy-training.test', club)
        for index, effort in enumerate((90, 90, 70, 70)):
            session = TrainingSession.objects.create(
                title=f'Technical {index}',
                date=date.today() - timedelta(days=index),
                focus='TECHNICAL',
                age_tiers=[AgeTier.DEVELOPMENT],
                club=club,
                created_by=coach,
            )
            Attendance.objects.create(
                player=player,
                session=session,
                status='PRESENT',
                effort=effort,
                recorded_by=coach,
            )
        rows = Attendance.objects.select_related('session').order_by(
            '-session__date'
        )

        technical = build_training_groups(rows)[0]
        self.assertEqual(technical['comparison']['metric'], 'EFFORT')
        self.assertEqual(technical['comparison']['effortDelta'], 20.0)
        self.assertEqual(
            technical['comparison']['classification'], IMPROVING
        )


class BaselineMigrationDataTests(APITestCase):
    def test_data_step_preserves_profile_as_one_nullable_coach_baseline(self):
        club = _club('Migration Growth Club')
        player = _player('player@migration-growth.test', club, position='GK')
        profile = player.player_profile
        profile.diving = 77
        profile.coach_notes = 'Latest known evaluation only.'
        profile.save(update_fields=['diving', 'coach_notes'])

        migration = importlib.import_module(
            'academy.migrations.0023_player_growth'
        )
        migration.seed_growth_baselines(django_apps, None)

        snapshot = PlayerAssessmentSnapshot.objects.get(player=player)
        self.assertEqual(snapshot.reason, AssessmentReason.BASELINE)
        self.assertIsNone(snapshot.assessed_by)
        self.assertEqual(snapshot.position, 'GK')
        self.assertEqual(snapshot.diving, 77)
        self.assertEqual(snapshot.coach_notes, 'Latest known evaluation only.')
