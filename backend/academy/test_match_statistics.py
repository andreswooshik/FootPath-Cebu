"""Match performance API contract, calculations, and tenant security tests."""
from datetime import date, timedelta

from django.urls import reverse
from rest_framework.test import APITestCase

from accounts.models import Club, GuardianLink, Roles, User

from .models import (
    AgeTier,
    Eligibility,
    FootballMatch,
    PlayerMatchPerformance,
    PlayerProfile,
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
        firebase_uid=f'uid-{email}',
        role=role,
        club=club,
    )


def _player(email, club):
    user = _user(email, Roles.PLAYER, club)
    PlayerProfile.objects.create(
        user=user,
        age=15,
        class_year='Class of 2028',
        age_tier=AgeTier.DEVELOPMENT,
        position='CM',
        eligibility=Eligibility.ELIGIBLE,
    )
    return user


class MatchPerformanceApiTests(APITestCase):
    def setUp(self):
        self.club_a = _club('Match Club A')
        self.club_b = _club('Match Club B')
        self.coach_a = _user('coach-a@match.test', Roles.COACH, self.club_a)
        self.coach_b = _user('coach-b@match.test', Roles.COACH, self.club_b)
        self.admin = _user('admin@match.test', Roles.ADMIN, None)
        self.player_a = _player('player-a@match.test', self.club_a)
        self.player_b = _player('player-b@match.test', self.club_b)
        self.match_a = FootballMatch.objects.create(
            club=self.club_a,
            opponent='Cebu United',
            competition='Youth League',
            played_on=date.today() - timedelta(days=2),
            venue='HOME',
            our_score=3,
            opponent_score=1,
            created_by=self.coach_a,
        )

    def _match_payload(self, **overrides):
        payload = {
            'opponent': 'Mandaue FC',
            'competition': 'Youth League',
            'playedOn': str(date.today()),
            'venue': 'AWAY',
            'ourScore': 2,
            'opponentScore': 2,
        }
        payload.update(overrides)
        return payload

    def _performance_payload(self, **overrides):
        payload = {
            'position': 'CM',
            'starter': True,
            'minutesPlayed': 80,
            'goals': 1,
            'assists': 2,
            'shots': 4,
            'shotsOnTarget': 3,
            'passesAttempted': 40,
            'passesCompleted': 32,
            'tackles': 3,
            'interceptions': 2,
            'yellowCards': 1,
            'redCards': 0,
            'saves': 0,
            'goalsConceded': 0,
            'cleanSheet': False,
            'coachRating': 8.5,
            'notes': 'Controlled midfield and created chances.',
        }
        payload.update(overrides)
        return payload

    def _performance_url(self, match=None, player=None):
        return reverse(
            'match-performance-detail',
            args=[
                (match or self.match_a).id,
                (player or self.player_a).id,
            ],
        )

    def test_coach_creates_match_stamped_to_own_club(self):
        self.client.force_authenticate(self.coach_a)
        response = self.client.post(
            reverse('football-matches'),
            self._match_payload(),
            format='json',
        )
        self.assertEqual(response.status_code, 201)
        created = FootballMatch.objects.get(pk=response.data['id'])
        self.assertEqual(created.club, self.club_a)
        self.assertEqual(created.created_by, self.coach_a)

    def test_match_list_and_detail_are_club_scoped(self):
        FootballMatch.objects.create(
            club=self.club_b,
            opponent='Hidden Rival',
            played_on=date.today(),
            our_score=1,
            opponent_score=0,
            created_by=self.coach_b,
        )
        self.client.force_authenticate(self.coach_a)
        response = self.client.get(reverse('football-matches'))
        self.assertEqual(
            {row['opponent'] for row in response.data},
            {'Cebu United'},
        )

    def test_non_coach_cannot_create_match(self):
        self.client.force_authenticate(self.player_a)
        response = self.client.post(
            reverse('football-matches'),
            self._match_payload(),
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_admin_reads_all_matches_but_does_not_create_them(self):
        FootballMatch.objects.create(
            club=self.club_b,
            opponent='Club B Rival',
            played_on=date.today(),
            our_score=2,
            opponent_score=0,
            created_by=self.coach_b,
        )
        self.client.force_authenticate(self.admin)
        self.assertEqual(
            len(self.client.get(reverse('football-matches')).data), 2
        )
        response = self.client.post(
            reverse('football-matches'),
            self._match_payload(),
            format='json',
        )
        self.assertEqual(response.status_code, 403)

    def test_future_match_is_rejected(self):
        self.client.force_authenticate(self.coach_a)
        response = self.client.post(
            reverse('football-matches'),
            self._match_payload(
                playedOn=str(date.today() + timedelta(days=1)),
            ),
            format='json',
        )
        self.assertEqual(response.status_code, 400)

    def test_coach_upserts_one_players_performance(self):
        self.client.force_authenticate(self.coach_a)
        first = self.client.put(
            self._performance_url(), self._performance_payload(), format='json'
        )
        self.assertEqual(first.status_code, 201)
        self.assertEqual(first.data['coachRating'], 8.5)

        second = self.client.put(
            self._performance_url(),
            self._performance_payload(goals=2, coachRating=9.0),
            format='json',
        )
        self.assertEqual(second.status_code, 200)
        self.assertEqual(PlayerMatchPerformance.objects.count(), 1)
        self.assertEqual(PlayerMatchPerformance.objects.get().goals, 2)

    def test_coach_cannot_record_other_clubs_player_or_match(self):
        self.client.force_authenticate(self.coach_a)
        other_player = self.client.put(
            self._performance_url(player=self.player_b),
            self._performance_payload(),
            format='json',
        )
        self.assertEqual(other_player.status_code, 404)

        self.client.force_authenticate(self.coach_b)
        other_match = self.client.put(
            self._performance_url(), self._performance_payload(), format='json'
        )
        self.assertEqual(other_match.status_code, 404)

    def test_impossible_statistics_are_rejected(self):
        self.client.force_authenticate(self.coach_a)
        response = self.client.put(
            self._performance_url(),
            self._performance_payload(
                shots=2,
                shotsOnTarget=3,
                passesAttempted=10,
                passesCompleted=11,
            ),
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        self.assertFalse(PlayerMatchPerformance.objects.exists())

    def test_player_goal_totals_cannot_exceed_team_score(self):
        teammate = _player('teammate@match.test', self.club_a)
        self.client.force_authenticate(self.coach_a)
        first = self.client.put(
            self._performance_url(),
            self._performance_payload(goals=2, shots=3, shotsOnTarget=2),
            format='json',
        )
        self.assertEqual(first.status_code, 201)
        second = self.client.put(
            self._performance_url(player=teammate),
            self._performance_payload(goals=2, shots=3, shotsOnTarget=2),
            format='json',
        )
        self.assertEqual(second.status_code, 400)
        self.assertEqual(PlayerMatchPerformance.objects.count(), 1)

    def test_goalkeeper_fields_require_goalkeeper_position(self):
        self.client.force_authenticate(self.coach_a)
        response = self.client.put(
            self._performance_url(),
            self._performance_payload(position='CM', saves=3),
            format='json',
        )
        self.assertEqual(response.status_code, 400)

    def test_player_reads_own_summary_and_history(self):
        PlayerMatchPerformance.objects.create(
            match=self.match_a,
            player=self.player_a,
            position='CM',
            starter=True,
            minutes_played=80,
            goals=1,
            assists=2,
            shots=4,
            shots_on_target=3,
            passes_attempted=40,
            passes_completed=32,
            tackles=3,
            interceptions=2,
            coach_rating=8.5,
            recorded_by=self.coach_a,
        )
        self.client.force_authenticate(self.player_a)
        response = self.client.get(
            reverse('player-match-statistics', args=[self.player_a.id])
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['summary']['matchesPlayed'], 1)
        self.assertEqual(response.data['summary']['goals'], 1)
        self.assertEqual(response.data['summary']['assists'], 2)
        self.assertEqual(response.data['summary']['passCompletionRate'], 80.0)
        self.assertEqual(response.data['summary']['averageRating'], 8.5)
        self.assertEqual(response.data['performances'][0]['match']['id'], str(
            self.match_a.id
        ))

    def test_player_cannot_read_another_players_statistics(self):
        self.client.force_authenticate(self.player_b)
        response = self.client.get(
            reverse('player-match-statistics', args=[self.player_a.id])
        )
        self.assertEqual(response.status_code, 403)

    def test_coach_statistics_read_is_club_scoped(self):
        url = reverse('player-match-statistics', args=[self.player_a.id])
        self.client.force_authenticate(self.coach_a)
        self.assertEqual(self.client.get(url).status_code, 200)
        self.client.force_authenticate(self.coach_b)
        self.assertEqual(self.client.get(url).status_code, 403)

    def test_linked_guardian_reads_statistics_when_no_pin_exists(self):
        guardian = _user('guardian@match.test', Roles.GUARDIAN, self.club_a)
        GuardianLink.objects.create(guardian=guardian, player=self.player_a)
        url = reverse('player-match-statistics', args=[self.player_a.id])
        self.client.force_authenticate(guardian)
        self.assertEqual(self.client.get(url).status_code, 200)

    def test_linked_guardian_requires_player_unlock_when_pin_exists(self):
        guardian = _user('guardian@match.test', Roles.GUARDIAN, self.club_a)
        GuardianLink.objects.create(guardian=guardian, player=self.player_a)
        set_pin(self.player_a, '1234')
        url = reverse('player-match-statistics', args=[self.player_a.id])
        self.client.force_authenticate(guardian)

        self.assertEqual(self.client.get(url).status_code, 403)
        token = issue_player_unlock(guardian.id, self.player_a.id)
        response = self.client.get(url, HTTP_X_PLAYER_UNLOCK=token)
        self.assertEqual(response.status_code, 200)

    def test_unlinked_guardian_cannot_use_a_player_unlock(self):
        guardian = _user('guardian@match.test', Roles.GUARDIAN, self.club_a)
        url = reverse('player-match-statistics', args=[self.player_a.id])
        token = issue_player_unlock(guardian.id, self.player_a.id)
        self.client.force_authenticate(guardian)
        response = self.client.get(url, HTTP_X_PLAYER_UNLOCK=token)
        self.assertEqual(response.status_code, 403)
