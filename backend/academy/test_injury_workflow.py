from datetime import date, timedelta

from django.urls import reverse
from rest_framework.test import APITestCase

from accounts.models import Club, GuardianLink, Roles, User

from .models import (
    AgeTier,
    AuditLog,
    FootballMatch,
    InjuryRecord,
    InjuryReportStatus,
    InjuryStatus,
    InjuryStatusUpdateRequest,
    InjuryUpdateReviewStatus,
    PlayerProfile,
)


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
    player = _user(email, Roles.PLAYER, club)
    PlayerProfile.objects.create(
        user=player,
        age=15,
        class_year='Class of 2028',
        age_tier=AgeTier.DEVELOPMENT,
    )
    return player


class InjuryConfirmationWorkflowTests(APITestCase):
    def setUp(self):
        self.club = _club('Care Team FC')
        self.other_club = _club('Other Care FC')
        self.player = _player('player@care.test', self.club)
        self.other_player = _player('other-player@care.test', self.other_club)
        self.guardian = _user('guardian@care.test', Roles.GUARDIAN, self.club)
        GuardianLink.objects.create(
            guardian=self.guardian,
            player=self.player,
        )
        self.coach = _user('coach@care.test', Roles.COACH, self.club)
        self.other_coach = _user(
            'other-coach@care.test', Roles.COACH, self.other_club
        )
        self.coordinator = _user(
            'coordinator@care.test', Roles.COORDINATOR, self.club
        )
        self.other_coordinator = _user(
            'other-coordinator@care.test',
            Roles.COORDINATOR,
            self.other_club,
        )

    def _payload(self, **overrides):
        payload = {
            'playerId': str(self.player.id),
            'description': 'Sprained ankle',
            'bodyPart': 'Left ankle',
            'status': 'RECOVERED',
            'occurredOn': str(date.today() - timedelta(days=2)),
            'resolvedOn': str(date.today()),
            'notes': 'Pain after landing.',
        }
        payload.update(overrides)
        return payload

    def _report(self, reporter=None, **overrides):
        reporter = reporter or self.player
        self.client.force_authenticate(reporter)
        response = self.client.post(
            reverse('injuries'),
            self._payload(**overrides),
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        return InjuryRecord.objects.get(pk=response.data['id'])

    def _confirm(self, record):
        self.client.force_authenticate(self.coordinator)
        response = self.client.post(
            reverse('injury-review', args=[record.id]),
            {'action': 'CONFIRM'},
            format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        record.refresh_from_db()
        return record

    def _performance_payload(self, **overrides):
        payload = {
            'position': 'CM',
            'starter': True,
            'minutesPlayed': 70,
            'goals': 0,
            'assists': 1,
            'shots': 1,
            'shotsOnTarget': 0,
            'passesAttempted': 30,
            'passesCompleted': 24,
            'tackles': 2,
            'interceptions': 1,
            'yellowCards': 0,
            'redCards': 0,
            'saves': 0,
            'goalsConceded': 0,
            'cleanSheet': False,
        }
        payload.update(overrides)
        return payload

    def test_care_team_roles_can_report_and_new_reports_are_pending_active(self):
        for reporter in (
            self.player,
            self.guardian,
            self.coach,
            self.coordinator,
        ):
            record = self._report(reporter=reporter)
            self.assertEqual(record.reported_by, reporter)
            self.assertEqual(record.review_status, InjuryReportStatus.PENDING)
            self.assertEqual(record.status, InjuryStatus.ACTIVE)
            self.assertIsNone(record.resolved_on)

    def test_pending_reporter_and_coordinator_manage_but_other_care_member_cannot(self):
        record = self._report(reporter=self.player)
        detail = reverse('injury-detail', args=[record.id])

        self.client.force_authenticate(self.coach)
        self.assertEqual(
            self.client.put(
                detail, {'description': 'Coach edit'}, format='json'
            ).status_code,
            403,
        )

        self.client.force_authenticate(self.player)
        response = self.client.put(
            detail,
            {'description': 'Updated ankle report'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)

        self.client.force_authenticate(self.coordinator)
        response = self.client.delete(detail)
        self.assertEqual(response.status_code, 204)
        self.assertFalse(InjuryRecord.objects.filter(pk=record.pk).exists())

    def test_coordinator_confirms_and_confirmed_report_is_coordinator_owned(self):
        record = self._confirm(self._report())
        self.assertEqual(record.reviewed_by, self.coordinator)
        self.assertIsNotNone(record.reviewed_at)

        detail = reverse('injury-detail', args=[record.id])
        self.client.force_authenticate(self.player)
        self.assertEqual(
            self.client.put(
                detail, {'description': 'Player correction'}, format='json'
            ).status_code,
            403,
        )
        self.assertEqual(self.client.delete(detail).status_code, 403)

        self.client.force_authenticate(self.coordinator)
        response = self.client.put(
            detail,
            {'notes': 'Confirmed care-team restriction.'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['notes'], 'Confirmed care-team restriction.')

    def test_rejection_requires_reason_and_is_visible_only_to_reporter_coordinator(self):
        record = self._report(reporter=self.coach)
        review_url = reverse('injury-review', args=[record.id])
        self.client.force_authenticate(self.coordinator)
        self.assertEqual(
            self.client.post(
                review_url, {'action': 'REJECT'}, format='json'
            ).status_code,
            400,
        )
        response = self.client.post(
            review_url,
            {'action': 'REJECT', 'rejectionReason': 'Duplicate report.'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)

        same_club_coach = _user('second-coach@care.test', Roles.COACH, self.club)
        self.client.force_authenticate(same_club_coach)
        self.assertEqual(len(self.client.get(reverse('injuries')).data), 0)
        self.client.force_authenticate(self.coach)
        self.assertEqual(len(self.client.get(reverse('injuries')).data), 1)
        self.client.force_authenticate(self.coordinator)
        self.assertEqual(len(self.client.get(reverse('injuries')).data), 1)

    def test_care_team_requests_recovery_and_coordinator_approves(self):
        record = self._confirm(self._report())
        self.client.force_authenticate(self.coordinator)
        self.assertFalse(
            self.client.get(
                reverse('injury-detail', args=[record.id])
            ).data['canRequestStatusUpdate']
        )
        self.client.force_authenticate(self.guardian)
        self.assertTrue(
            self.client.get(
                f"{reverse('injuries')}?player={self.player.id}"
            ).data[0]['canRequestStatusUpdate']
        )
        response = self.client.post(
            reverse('injury-status-updates', args=[record.id]),
            {
                'proposedStatus': 'RECOVERED',
                'proposedResolvedOn': str(date.today()),
                'notes': 'Full movement restored.',
            },
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        update = InjuryStatusUpdateRequest.objects.get(pk=response.data['id'])
        self.assertEqual(update.review_status, InjuryUpdateReviewStatus.PENDING)

        self.client.force_authenticate(self.coordinator)
        response = self.client.post(
            reverse(
                'injury-status-update-review',
                args=[record.id, update.id],
            ),
            {'action': 'APPROVE'},
            format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        record.refresh_from_db()
        update.refresh_from_db()
        self.assertEqual(record.status, InjuryStatus.RECOVERED)
        self.assertEqual(record.resolved_on, date.today())
        self.assertEqual(update.review_status, InjuryUpdateReviewStatus.APPROVED)

    def test_only_one_pending_recovery_update_and_rejection_needs_reason(self):
        record = self._confirm(self._report())
        self.client.force_authenticate(self.coach)
        url = reverse('injury-status-updates', args=[record.id])
        first = self.client.post(
            url,
            {'proposedStatus': 'RECOVERING', 'notes': 'Light activity.'},
            format='json',
        )
        self.assertEqual(first.status_code, 201)
        self.assertEqual(
            self.client.post(
                url, {'proposedStatus': 'RECOVERING'}, format='json'
            ).status_code,
            400,
        )

        self.client.force_authenticate(self.coordinator)
        review_url = reverse(
            'injury-status-update-review',
            args=[record.id, first.data['id']],
        )
        self.assertEqual(
            self.client.post(
                review_url, {'action': 'REJECT'}, format='json'
            ).status_code,
            400,
        )
        self.assertEqual(
            self.client.post(
                review_url,
                {'action': 'REJECT', 'rejectionReason': 'Needs assessment.'},
                format='json',
            ).status_code,
            200,
        )

    def test_cross_club_accounts_cannot_view_report_or_review_it(self):
        record = self._report()
        self.client.force_authenticate(self.other_coach)
        self.assertEqual(len(self.client.get(reverse('injuries')).data), 0)
        self.assertEqual(
            self.client.get(reverse('injury-detail', args=[record.id])).status_code,
            403,
        )
        self.client.force_authenticate(self.other_coordinator)
        self.assertEqual(
            self.client.post(
                reverse('injury-review', args=[record.id]),
                {'action': 'CONFIRM'},
                format='json',
            ).status_code,
            403,
        )

    def test_confirmed_report_archives_without_deleting_history(self):
        record = self._confirm(self._report())
        archive_url = reverse('injury-archive', args=[record.id])
        self.assertEqual(self.client.post(archive_url).status_code, 400)
        response = self.client.put(
            reverse('injury-detail', args=[record.id]),
            {
                'status': 'RECOVERED',
                'resolvedOn': str(date.today()),
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200, response.data)
        response = self.client.post(archive_url)
        self.assertEqual(response.status_code, 200)
        record.refresh_from_db()
        self.assertEqual(record.review_status, InjuryReportStatus.ARCHIVED)
        self.assertIsNotNone(record.archived_at)
        self.assertEqual(len(self.client.get(reverse('injuries')).data), 0)
        self.assertEqual(
            len(
                self.client.get(
                    f"{reverse('injuries')}?includeArchived=true"
                ).data
            ),
            1,
        )

    def test_active_confirmed_injury_requires_audited_match_override(self):
        record = self._confirm(self._report())
        match = FootballMatch.objects.create(
            club=self.club,
            opponent='Cebu United',
            played_on=date.today(),
            venue='HOME',
            our_score=1,
            opponent_score=0,
            created_by=self.coordinator,
        )
        url = reverse(
            'match-performance-detail',
            args=[match.id, self.player.id],
        )
        roster = self.client.get(
            reverse('match-roster', args=[match.id])
        )
        self.assertEqual(roster.status_code, 200)
        self.assertEqual(roster.data[0]['activeInjuryStatus'], 'ACTIVE')
        response = self.client.put(
            url, self._performance_payload(), format='json'
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data['code'], 'ACTIVE_INJURY_WARNING')

        response = self.client.put(
            url,
            self._performance_payload(injuryOverrideAcknowledged=True),
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(
            AuditLog.objects.filter(
                action='match.injury_override',
                target=f'{match.id}:{self.player.id}',
            ).exists()
        )
        self.assertEqual(record.status, InjuryStatus.ACTIVE)

    def test_reportable_player_selector_is_minimal_and_club_scoped(self):
        self.client.force_authenticate(self.coordinator)
        response = self.client.get(reverse('injury-reportable-players'))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(set(response.data[0]), {'id', 'name', 'ageTier'})
