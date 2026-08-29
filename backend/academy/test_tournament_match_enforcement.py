from datetime import date, timedelta

from django.core.exceptions import ValidationError as DjangoValidationError
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import Club, Roles, User

from .models import (
    AuditLog,
    FootballMatch,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    PlayerMatchPerformance,
    PlayerProfile,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
)


def _club(name):
    return Club.objects.create(name=name, slug=name.lower().replace(' ', '-'))


def _user(email, role, club):
    return User.objects.create_user(
        username=email,
        email=email,
        password='Strong!Pass2026',
        firebase_uid=f'uid-{email}',
        role=role,
        club=club,
    )


def _player(email, club, born):
    player = _user(email, Roles.PLAYER, club)
    PlayerProfile.objects.create(
        user=player,
        date_of_birth=born,
        position='CM',
    )
    return player


class TournamentMatchEnforcementTests(APITestCase):
    def setUp(self):
        self.club = _club('Enforcement FC')
        self.other_club = _club('Other Enforcement FC')
        self.coordinator = _user(
            'coordinator@enforcement.test', Roles.COORDINATOR, self.club
        )
        self.coach = _user('coach@enforcement.test', Roles.COACH, self.club)
        self.member = _player(
            'member@enforcement.test', self.club, date(2018, 12, 31)
        )
        self.pending = _player(
            'pending@enforcement.test', self.club, date(2019, 1, 1)
        )
        self.blocked_member = _player(
            'blocked@enforcement.test', self.club, date(2018, 1, 1)
        )
        self.out_of_squad = _player(
            'exception@enforcement.test', self.club, date(2020, 1, 1)
        )
        self.overage = _player(
            'overage@enforcement.test', self.club, date(2017, 12, 31)
        )
        self.missing_dob = _player(
            'missing@enforcement.test', self.club, None
        )
        self.injured = _player(
            'injured@enforcement.test', self.club, date(2018, 6, 1)
        )
        self.schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Sinulog Cup',
            starts_on=date(2026, 9, 20),
            is_published=True,
        )
        self.bracket = TournamentAgeBracket.objects.create(
            schedule=self.schedule,
            max_age=8,
        )
        self.squad = TournamentSquad.objects.create(
            bracket=self.bracket,
            status=TournamentSquadStatus.PUBLISHED,
            published_at=timezone.now(),
            updated_by=self.coach,
        )
        for player in (self.member, self.pending, self.blocked_member):
            TournamentSquadEntry.objects.create(
                squad=self.squad,
                player=player,
                position='CM',
                added_by=self.coach,
            )
        InjuryRecord.objects.create(
            player=self.pending,
            description='Awaiting review',
            occurred_on=date.today() - timedelta(days=1),
            review_status=InjuryReportStatus.PENDING,
        )
        for player in (self.blocked_member, self.injured):
            InjuryRecord.objects.create(
                player=player,
                description='Confirmed injury',
                occurred_on=date.today() - timedelta(days=1),
                review_status=InjuryReportStatus.CONFIRMED,
                status=InjuryStatus.ACTIVE,
            )
        self.match = FootballMatch.objects.create(
            club=self.club,
            opponent='Cebu United',
            competition=self.schedule.title,
            played_on=date.today(),
            venue='NEUTRAL',
            our_score=3,
            opponent_score=1,
            created_by=self.coordinator,
        )
        self.fixture = TournamentFixture.objects.create(
            schedule=self.schedule,
            age_bracket=self.bracket,
            opponent='Cebu United',
            kickoff_at=timezone.now() - timedelta(hours=2),
            completed_match=self.match,
        )

    def _performance_payload(self, **overrides):
        payload = {
            'position': 'CM',
            'starter': True,
            'minutesPlayed': 60,
            'goals': 1,
            'assists': 0,
            'shots': 2,
            'shotsOnTarget': 1,
            'passesAttempted': 20,
            'passesCompleted': 15,
            'tackles': 1,
            'interceptions': 1,
            'yellowCards': 0,
            'redCards': 0,
            'saves': 0,
            'goalsConceded': 0,
            'cleanSheet': False,
        }
        payload.update(overrides)
        return payload

    def _performance_url(self, player):
        return reverse(
            'match-performance-detail', args=[self.match.id, player.id]
        )

    def test_fixture_bracket_must_belong_to_the_same_tournament(self):
        other_schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Other Cup',
            starts_on=date(2026, 10, 1),
        )
        other_bracket = TournamentAgeBracket.objects.create(
            schedule=other_schedule,
            max_age=10,
        )
        fixture = TournamentFixture(
            schedule=self.schedule,
            age_bracket=other_bracket,
            opponent='Invalid FC',
            kickoff_at=timezone.now(),
        )
        with self.assertRaises(DjangoValidationError):
            fixture.save()

    def test_match_and_fixture_contract_expose_the_linked_bracket(self):
        self.client.force_authenticate(self.coordinator)
        matches = self.client.get(reverse('football-matches'))
        self.assertEqual(matches.status_code, 200)
        row = next(item for item in matches.data if item['id'] == str(self.match.id))
        self.assertEqual(row['ageBracketId'], str(self.bracket.id))
        self.assertEqual(row['ageBracketLabel'], 'U8')

        schedules = self.client.get(reverse('tournament-schedules'))
        fixture = schedules.data[0]['fixtures'][0]
        self.assertEqual(fixture['ageBracketId'], str(self.bracket.id))
        self.assertEqual(fixture['ageBracketLabel'], 'U8')

    def test_default_roster_is_the_current_valid_published_squad(self):
        self.client.force_authenticate(self.coordinator)
        response = self.client.get(reverse('match-roster', args=[self.match.id]))
        self.assertEqual(response.status_code, 200)
        by_id = {row['id']: row for row in response.data}
        self.assertEqual(set(by_id), {str(self.member.id), str(self.pending.id)})
        self.assertTrue(by_id[str(self.member.id)]['inTournamentSquad'])
        self.assertEqual(by_id[str(self.pending.id)]['availability'], 'WARNING')
        self.assertTrue(by_id[str(self.pending.id)]['isSelectable'])
        self.assertNotIn(str(self.blocked_member.id), by_id)
        self.assertNotIn(str(self.out_of_squad.id), by_id)

    def test_only_coordinator_can_request_eligible_out_of_squad_candidates(self):
        url = (
            f"{reverse('match-roster', args=[self.match.id])}"
            '?includeOutOfSquad=true'
        )
        self.client.force_authenticate(self.coordinator)
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        by_id = {row['id']: row for row in response.data}
        self.assertTrue(by_id[str(self.out_of_squad.id)]['requiresSquadOverride'])
        self.assertNotIn(str(self.overage.id), by_id)
        self.assertNotIn(str(self.missing_dob.id), by_id)
        self.assertNotIn(str(self.injured.id), by_id)

        self.client.force_authenticate(self.coach)
        self.assertEqual(self.client.get(url).status_code, 403)

    def test_out_of_squad_statistics_require_and_audit_a_reason(self):
        self.client.force_authenticate(self.coordinator)
        url = self._performance_url(self.out_of_squad)
        missing = self.client.put(url, self._performance_payload(), format='json')
        self.assertEqual(missing.status_code, 400)
        self.assertIn('squadOverrideReason', missing.data)

        saved = self.client.put(
            url,
            self._performance_payload(
                squadOverrideReason='Late replacement approved by organizer.'
            ),
            format='json',
        )
        self.assertEqual(saved.status_code, 201, saved.data)
        performance = PlayerMatchPerformance.objects.get(
            match=self.match,
            player=self.out_of_squad,
        )
        self.assertEqual(
            performance.squad_override_reason,
            'Late replacement approved by organizer.',
        )
        self.assertEqual(performance.squad_override_by, self.coordinator)
        self.assertIsNotNone(performance.squad_override_at)
        self.assertTrue(
            AuditLog.objects.filter(
                action='match.squad_override',
                target=f'{self.match.id}:{self.out_of_squad.id}',
            ).exists()
        )

    def test_published_squad_member_does_not_need_an_exception(self):
        self.client.force_authenticate(self.coordinator)
        response = self.client.put(
            self._performance_url(self.member),
            self._performance_payload(),
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        performance = PlayerMatchPerformance.objects.get(player=self.member)
        self.assertEqual(performance.squad_override_reason, '')

    def test_hard_eligibility_failures_can_never_be_overridden(self):
        self.client.force_authenticate(self.coordinator)
        for player, expected_code in (
            (self.overage, 'OVERAGE'),
            (self.missing_dob, 'DOB_REQUIRED'),
            (self.injured, 'CONFIRMED_INJURY'),
        ):
            response = self.client.put(
                self._performance_url(player),
                self._performance_payload(
                    squadOverrideReason='Attempted exception',
                    injuryOverrideAcknowledged=True,
                ),
                format='json',
            )
            self.assertEqual(response.status_code, 400)
            self.assertEqual(response.data['player']['code'], expected_code)
        self.assertFalse(PlayerMatchPerformance.objects.exists())

    def test_existing_performance_remains_visible_but_not_selectable(self):
        performance = PlayerMatchPerformance.objects.create(
            match=self.match,
            player=self.blocked_member,
            position='CM',
            recorded_by=self.coordinator,
        )
        self.client.force_authenticate(self.coordinator)
        response = self.client.get(reverse('match-roster', args=[self.match.id]))
        row = next(
            item for item in response.data
            if item['id'] == str(self.blocked_member.id)
        )
        self.assertFalse(row['isSelectable'])
        self.assertEqual(row['performance']['id'], str(performance.id))

    def test_coach_can_rate_an_audited_squad_exception(self):
        performance = PlayerMatchPerformance.objects.create(
            match=self.match,
            player=self.out_of_squad,
            position='CM',
            recorded_by=self.coordinator,
            squad_override_reason='Organizer replacement.',
            squad_override_by=self.coordinator,
            squad_override_at=timezone.now(),
        )
        self.client.force_authenticate(self.coach)
        response = self.client.put(
            reverse(
                'match-performance-rating',
                args=[self.match.id, self.out_of_squad.id],
            ),
            {'coachRating': 8.5, 'notes': 'Strong impact.'},
            format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        performance.refresh_from_db()
        self.assertEqual(float(performance.coach_rating), 8.5)
        self.assertNotIn('squadOverrideReason', response.data)

    def test_fixture_link_prevents_draft_bracket_deletion(self):
        self.schedule.is_published = False
        self.schedule.published_at = None
        self.schedule.save()
        self.client.force_authenticate(self.coordinator)
        response = self.client.delete(
            reverse('tournament-bracket-detail', args=[self.bracket.id])
        )
        self.assertEqual(response.status_code, 400)
        self.assertTrue(TournamentAgeBracket.objects.filter(pk=self.bracket.id).exists())
