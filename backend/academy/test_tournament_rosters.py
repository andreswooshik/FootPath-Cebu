from datetime import date

from django.urls import reverse
from rest_framework.test import APITestCase

from accounts.models import Club, Roles, User

from .models import (
    AuditLog,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    PlayerProfile,
    TournamentAgeBracket,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
)
from .tournament_rosters import roster_eligibility


def _club(name):
    return Club.objects.create(name=name, slug=name.lower().replace(' ', '-'))


def _user(email, role, club):
    return User.objects.create_user(
        username=email,
        email=email,
        password='Strong!Pass2026',
        role=role,
        club=club,
        firebase_uid=f'uid-{email}',
    )


def _player(email, club, born):
    user = _user(email, Roles.PLAYER, club)
    PlayerProfile.objects.create(user=user, date_of_birth=born)
    return user


class TournamentRosterEligibilityTests(APITestCase):
    def setUp(self):
        self.club = _club('Eligibility FC')
        self.schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Sinulog Cup',
            starts_on=date(2026, 9, 20),
        )
        self.u8 = TournamentAgeBracket.objects.create(
            schedule=self.schedule, max_age=8
        )
        self.u12 = TournamentAgeBracket.objects.create(
            schedule=self.schedule, max_age=12
        )

    def test_calendar_year_cutoff_and_play_up(self):
        cutoff = _player('cutoff@eligibility.test', self.club, date(2018, 12, 31))
        overage = _player('overage@eligibility.test', self.club, date(2017, 1, 1))
        younger = _player('younger@eligibility.test', self.club, date(2020, 1, 1))
        self.assertEqual(roster_eligibility(cutoff, self.u8).state, 'ELIGIBLE')
        self.assertEqual(roster_eligibility(overage, self.u8).code, 'OVERAGE')
        self.assertEqual(roster_eligibility(younger, self.u8).state, 'ELIGIBLE')
        self.assertEqual(roster_eligibility(younger, self.u12).state, 'ELIGIBLE')

    def test_missing_birth_date_is_blocked(self):
        player = _player('missing@eligibility.test', self.club, None)
        self.assertEqual(roster_eligibility(player, self.u8).code, 'DOB_REQUIRED')

    def test_pending_injury_warns_but_confirmed_injury_blocks(self):
        player = _player('injured@eligibility.test', self.club, date(2019, 1, 1))
        injury = InjuryRecord.objects.create(
            player=player,
            description='Ankle pain',
            occurred_on=date(2026, 8, 20),
            review_status=InjuryReportStatus.PENDING,
        )
        self.assertEqual(roster_eligibility(player, self.u8).state, 'WARNING')
        injury.review_status = InjuryReportStatus.CONFIRMED
        injury.status = InjuryStatus.ACTIVE
        injury.save()
        self.assertEqual(
            roster_eligibility(player, self.u8).code, 'CONFIRMED_INJURY'
        )
        injury.status = InjuryStatus.RECOVERED
        injury.resolved_on = date(2026, 8, 28)
        injury.save()
        self.assertEqual(roster_eligibility(player, self.u8).state, 'ELIGIBLE')


class TournamentRosterApiTests(APITestCase):
    def setUp(self):
        self.club = _club('Roster FC')
        self.other_club = _club('Other Roster FC')
        self.coordinator = _user('coordinator@roster.test', Roles.COORDINATOR, self.club)
        self.coach = _user('coach@roster.test', Roles.COACH, self.club)
        self.second_coach = _user('coach2@roster.test', Roles.COACH, self.club)
        self.player_viewer = _player(
            'viewer@roster.test', self.club, date(2018, 2, 1)
        )
        self.eligible = _player(
            'eligible@roster.test', self.club, date(2018, 12, 31)
        )
        self.younger = _player(
            'younger@roster.test', self.club, date(2020, 1, 1)
        )
        self.overage = _player(
            'overage@roster.test', self.club, date(2017, 12, 31)
        )
        self.no_dob = _player('nodob@roster.test', self.club, None)
        self.schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Sinulog Cup',
            starts_on=date(2026, 9, 20),
            is_published=False,
            published_at=None,
        )
        self.u8 = TournamentAgeBracket.objects.create(
            schedule=self.schedule, max_age=8
        )
        self.u10 = TournamentAgeBracket.objects.create(
            schedule=self.schedule, max_age=10
        )

    def _save(self, entries, user=None, bracket=None):
        self.client.force_authenticate(user or self.coach)
        return self.client.put(
            reverse('tournament-squad-detail', args=[(bracket or self.u8).id]),
            {'entries': entries},
            format='json',
        )

    def test_candidates_explain_age_and_missing_dob_without_exposing_dates(self):
        self.client.force_authenticate(self.coach)
        response = self.client.get(
            reverse('tournament-squad-candidates', args=[self.u8.id])
        )
        self.assertEqual(response.status_code, 200)
        by_id = {row['playerId']: row for row in response.data}
        self.assertEqual(by_id[str(self.eligible.id)]['eligibility'], 'ELIGIBLE')
        self.assertEqual(by_id[str(self.overage.id)]['eligibilityCode'], 'OVERAGE')
        self.assertEqual(by_id[str(self.no_dob.id)]['eligibilityCode'], 'DOB_REQUIRED')
        self.assertNotIn('dateOfBirth', by_id[str(self.eligible.id)])

    def test_coach_saves_shared_multi_bracket_rosters(self):
        first = self._save([
            {'playerId': self.eligible.id, 'position': 'CM'},
            {'playerId': self.younger.id, 'position': 'ST'},
        ])
        self.assertEqual(first.status_code, 200)
        shared_update = self._save(
            [{'playerId': self.younger.id, 'position': 'LW'}],
            user=self.second_coach,
        )
        self.assertEqual(shared_update.status_code, 200)
        u8_squad = TournamentSquad.objects.get(bracket=self.u8)
        self.assertEqual(u8_squad.updated_by, self.second_coach)
        self.assertEqual(list(u8_squad.entries.values_list('player_id', flat=True)), [
            self.younger.id,
        ])
        second = self._save(
            [{'playerId': self.younger.id, 'position': 'LW'}],
            user=self.second_coach,
            bracket=self.u10,
        )
        self.assertEqual(second.status_code, 200)
        self.assertEqual(
            TournamentSquadEntry.objects.filter(player=self.younger).count(), 2
        )
        self.assertTrue(
            AuditLog.objects.filter(action='tournament.squad_saved').exists()
        )

    def test_blocked_players_and_duplicate_entries_are_rejected(self):
        blocked = self._save([
            {'playerId': self.overage.id},
            {'playerId': self.no_dob.id},
        ])
        self.assertEqual(blocked.status_code, 400)
        duplicate = self._save([
            {'playerId': self.eligible.id},
            {'playerId': self.eligible.id},
        ])
        self.assertEqual(duplicate.status_code, 400)
        self.assertFalse(TournamentSquadEntry.objects.exists())

    def test_pending_injury_warns_and_is_still_selectable(self):
        InjuryRecord.objects.create(
            player=self.eligible,
            description='Pending check',
            occurred_on=date(2026, 8, 28),
            review_status=InjuryReportStatus.PENDING,
        )
        response = self._save([{'playerId': self.eligible.id}])
        self.assertEqual(response.status_code, 200)
        self.client.force_authenticate(self.coach)
        candidates = self.client.get(
            reverse('tournament-squad-candidates', args=[self.u8.id])
        ).data
        row = next(row for row in candidates if row['playerId'] == str(self.eligible.id))
        self.assertEqual(row['eligibility'], 'WARNING')

    def test_coordinator_reviews_but_cannot_edit(self):
        self._save([{'playerId': self.eligible.id, 'position': 'CM'}])
        self.client.force_authenticate(self.coordinator)
        read = self.client.get(
            reverse('tournament-squad-detail', args=[self.u8.id])
        )
        self.assertEqual(read.status_code, 200)
        self.assertEqual(read.data['status'], TournamentSquadStatus.DRAFT)
        write = self._save([], user=self.coordinator)
        self.assertEqual(write.status_code, 403)

    def test_publish_requires_published_tournament_then_becomes_privacy_safe(self):
        self._save([{'playerId': self.eligible.id, 'position': 'CM'}])
        self.client.force_authenticate(self.coach)
        publish_url = reverse('tournament-squad-publish', args=[self.u8.id])
        self.assertEqual(self.client.post(publish_url).status_code, 400)
        self.schedule.is_published = True
        self.schedule.save(update_fields=['is_published', 'updated_at'])
        self.assertEqual(self.client.post(publish_url).status_code, 200)
        self.client.force_authenticate(self.player_viewer)
        public = self.client.get(
            reverse('tournament-squad-detail', args=[self.u8.id])
        )
        self.assertEqual(public.status_code, 200)
        entry = public.data['entries'][0]
        self.assertEqual(entry['playerName'], 'eligible')
        self.assertNotIn('availability', entry)
        self.assertNotIn('availabilityReason', entry)
        schedule_rows = self.client.get(reverse('tournament-schedules')).data
        embedded = schedule_rows[0]['ageBrackets'][0]['squad']['entries'][0]
        self.assertEqual(embedded['playerName'], 'eligible')
        self.assertNotIn('availabilityReason', embedded)

    def test_confirmed_injury_marks_existing_member_unavailable_to_managers(self):
        self._save([{'playerId': self.eligible.id}])
        InjuryRecord.objects.create(
            player=self.eligible,
            description='Confirmed injury',
            occurred_on=date(2026, 8, 28),
            review_status=InjuryReportStatus.CONFIRMED,
            status=InjuryStatus.ACTIVE,
        )
        self.client.force_authenticate(self.coordinator)
        response = self.client.get(
            reverse('tournament-squad-detail', args=[self.u8.id])
        )
        self.assertEqual(
            response.data['entries'][0]['availability'], 'BLOCKED'
        )

    def test_tournament_date_and_bracket_changes_revalidate_age(self):
        self._save([{'playerId': self.eligible.id}])
        self.client.force_authenticate(self.coordinator)
        date_change = self.client.patch(
            reverse('tournament-schedule-detail', args=[self.schedule.id]),
            {'startsOn': '2027-09-20'},
            format='json',
        )
        self.assertEqual(date_change.status_code, 400)
        bracket_change = self.client.patch(
            reverse('tournament-bracket-detail', args=[self.u8.id]),
            {'maxAge': 7},
            format='json',
        )
        self.assertEqual(bracket_change.status_code, 400)
        self.schedule.refresh_from_db()
        self.u8.refresh_from_db()
        self.assertEqual(self.schedule.starts_on.year, 2026)
        self.assertEqual(self.u8.max_age, 8)

    def test_cross_club_coach_cannot_read_or_write_roster(self):
        other_coach = _user('other@roster.test', Roles.COACH, self.other_club)
        self.client.force_authenticate(other_coach)
        url = reverse('tournament-squad-detail', args=[self.u8.id])
        self.assertEqual(self.client.get(url).status_code, 404)
        self.assertEqual(
            self.client.put(url, {'entries': []}, format='json').status_code,
            404,
        )
