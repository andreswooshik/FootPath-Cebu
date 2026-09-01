from datetime import datetime, time, timedelta

from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import Club, Roles, User

from .models import (
    AgeTier,
    AuditLog,
    FixtureStatus,
    MatchVenue,
    PlayerProfile,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
    TrainingSession,
    TrainingSessionStatus,
)


class TournamentTrainingPriorityTests(APITestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Priority FC', slug='priority-fc')
        self.coordinator = self._user('coordinator@priority.test', Roles.COORDINATOR)
        self.coach = self._user('coach@priority.test', Roles.COACH)
        self.player = self._user('player@priority.test', Roles.PLAYER)
        PlayerProfile.objects.create(
            user=self.player,
            date_of_birth=timezone.localdate().replace(year=2015),
        )
        self.day = timezone.localdate() + timedelta(days=10)
        self.schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Cebu Priority Cup',
            venue='Cebu City Sports Center',
            starts_on=self.day,
        )
        self.bracket = TournamentAgeBracket.objects.create(
            schedule=self.schedule,
            max_age=12,
            academy_tiers=[AgeTier.FOUNDATION],
        )
        self.fixture = TournamentFixture.objects.create(
            schedule=self.schedule,
            age_bracket=self.bracket,
            stage='Group A',
            opponent='Rivals FC',
            kickoff_at=self._at(16, 0),
            ends_at=self._at(18, 0),
            venue=MatchVenue.NEUTRAL,
            location='Pitch 1',
            status=FixtureStatus.SCHEDULED,
        )

    def _user(self, email, role):
        return User.objects.create_user(
            username=email,
            email=email,
            password='Strong!Pass2026',
            role=role,
            club=self.club,
            firebase_uid=f'uid-{email}',
        )

    def _at(self, hour, minute):
        return timezone.make_aware(datetime.combine(self.day, time(hour, minute)))

    def _training(self):
        return TrainingSession.objects.create(
            club=self.club,
            title='Foundation Technical',
            age_tiers=[AgeTier.FOUNDATION],
            date=self.day,
            start_time='04:30 PM',
            end_time='06:30 PM',
            location='Academy Pitch',
            focus='TECHNICAL',
        )

    def test_published_fixture_blocks_training_create_without_saving(self):
        self.schedule.is_published = True
        self.schedule.published_at = timezone.now()
        self.schedule.save()
        self.client.force_authenticate(self.coach)
        response = self.client.post(reverse('training-sessions'), {
            'title': 'Conflicting Session',
            'ageTiers': [AgeTier.FOUNDATION],
            'date': self.day.isoformat(),
            'startTime': '04:30 PM',
            'endTime': '06:30 PM',
            'location': 'Academy Pitch',
            'focus': 'TECHNICAL',
        }, format='json')
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data['code'], 'TOURNAMENT_SCHEDULE_CONFLICT')
        self.assertEqual(
            response.data['conflict']['fixtureId'], str(self.fixture.id)
        )
        self.assertFalse(TrainingSession.objects.exists())

    def test_publish_requires_confirmation_then_soft_cancels_atomically(self):
        session = self._training()
        self.client.force_authenticate(self.coordinator)
        url = reverse('tournament-schedule-publish', args=[self.schedule.id])

        warning = self.client.post(url, {}, format='json')
        self.assertEqual(warning.status_code, 409)
        self.assertEqual(
            warning.data['code'],
            'TRAINING_CANCELLATION_CONFIRMATION_REQUIRED',
        )
        self.schedule.refresh_from_db()
        session.refresh_from_db()
        self.assertFalse(self.schedule.is_published)
        self.assertEqual(session.status, TrainingSessionStatus.SCHEDULED)

        confirmed = self.client.post(
            url, {'confirmTrainingCancellations': True}, format='json'
        )
        self.assertEqual(confirmed.status_code, 200)
        session.refresh_from_db()
        self.assertEqual(session.status, TrainingSessionStatus.CANCELLED)
        self.assertEqual(session.conflicting_tournament_id, self.schedule.id)
        self.assertEqual(session.conflicting_fixture_id, self.fixture.id)
        self.assertEqual(session.cancelled_by_action, 'tournament.published')
        self.assertTrue(
            AuditLog.objects.filter(
                action='session.tournament_conflict_cancelled',
                target=session.title,
            ).exists()
        )

    def test_boundary_touch_is_not_an_overlap(self):
        self.schedule.is_published = True
        self.schedule.published_at = timezone.now()
        self.schedule.save()
        self.client.force_authenticate(self.coach)
        response = self.client.post(reverse('training-sessions'), {
            'title': 'Starts after fixture',
            'ageTiers': [AgeTier.FOUNDATION],
            'date': self.day.isoformat(),
            'startTime': '06:00 PM',
            'endTime': '07:00 PM',
            'location': 'Academy Pitch',
            'focus': 'TECHNICAL',
        }, format='json')
        self.assertEqual(response.status_code, 201)

    def test_cancelled_session_rejects_attendance(self):
        session = self._training()
        session.status = TrainingSessionStatus.CANCELLED
        session.cancellation_reason = 'Tournament conflict.'
        session.cancelled_at = timezone.now()
        session.save()
        self.client.force_authenticate(self.coach)
        response = self.client.get(
            reverse('attendance-session', args=[session.id])
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data['code'], 'SESSION_CANCELLED')


class PublishedTournamentRosterLockTests(APITestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Roster Lock FC', slug='roster-lock-fc')
        self.coach = User.objects.create_user(
            username='coach@lock.test',
            email='coach@lock.test',
            password='Strong!Pass2026',
            role=Roles.COACH,
            club=self.club,
            firebase_uid='uid-coach-lock',
        )
        self.player = User.objects.create_user(
            username='player@lock.test',
            email='player@lock.test',
            password='Strong!Pass2026',
            role=Roles.PLAYER,
            club=self.club,
            firebase_uid='uid-player-lock',
        )
        PlayerProfile.objects.create(
            user=self.player,
            date_of_birth=timezone.localdate().replace(year=2015),
        )
        schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Locked Cup',
            venue='Pitch 1',
            starts_on=timezone.localdate() + timedelta(days=20),
            is_published=True,
            published_at=timezone.now(),
        )
        self.bracket = TournamentAgeBracket.objects.create(
            schedule=schedule,
            max_age=12,
            academy_tiers=[AgeTier.FOUNDATION],
        )
        squad = TournamentSquad.objects.create(
            bracket=self.bracket,
            status=TournamentSquadStatus.DRAFT,
            updated_by=self.coach,
        )
        TournamentSquadEntry.objects.create(
            squad=squad,
            player=self.player,
            position='CM',
        )
        self.client.force_authenticate(self.coach)

    def test_publish_is_once_only_and_published_roster_is_immutable(self):
        publish_url = reverse('tournament-squad-publish', args=[self.bracket.id])
        first = self.client.post(publish_url, {}, format='json')
        self.assertEqual(first.status_code, 200)
        published_at = first.data['publishedAt']

        second = self.client.post(publish_url, {}, format='json')
        self.assertEqual(second.status_code, 409)
        self.assertEqual(second.data['code'], 'ROSTER_ALREADY_PUBLISHED')

        update = self.client.put(
            reverse('tournament-squad-detail', args=[self.bracket.id]),
            {'entries': []},
            format='json',
        )
        self.assertEqual(update.status_code, 409)
        self.assertEqual(update.data['code'], 'ROSTER_LOCKED')
        squad = TournamentSquad.objects.get(bracket=self.bracket)
        self.assertEqual(
            squad.published_at,
            datetime.fromisoformat(published_at),
        )
        self.assertEqual(squad.entries.count(), 1)
