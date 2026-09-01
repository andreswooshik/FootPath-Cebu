from datetime import date, timedelta
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from accounts.models import Club, Roles, User

from .models import (
    AuditLog,
    AgeTier,
    Eligibility,
    FootballMatch,
    FixtureStatus,
    MatchVenue,
    PlayerMatchPerformance,
    PlayerProfile,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
    TournamentSquad,
    TournamentSquadEntry,
    TournamentSquadStatus,
)
from .storage import (
    signed_tournament_document_url,
    upload_tournament_document,
    validate_tournament_document,
)


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


def _pdf(name='schedule.pdf'):
    return SimpleUploadedFile(
        name,
        b'%PDF-1.7\nfixture data',
        content_type='application/pdf',
    )


class TournamentStorageTests(TestCase):
    def test_rejects_mime_signature_mismatch(self):
        upload = SimpleUploadedFile(
            'fake.pdf', b'not a pdf', content_type='application/pdf'
        )
        with self.assertRaisesMessage(ValueError, 'does not match'):
            validate_tournament_document(upload)

    @patch.dict('os.environ', {
        'SUPABASE_URL': 'https://project.supabase.co',
        'SUPABASE_SERVICE_KEY': 'sb_secret_test',
        'SUPABASE_SCHEDULE_BUCKET': 'private-schedules',
    }, clear=False)
    @patch('academy.storage.httpx.post')
    def test_supabase_upload_uses_private_schedule_bucket(self, post):
        post.return_value.raise_for_status.return_value = None
        path = upload_tournament_document(7, 11, b'%PDF-1.7', 'application/pdf')
        self.assertEqual(path, 'private-schedules/7/11.pdf')
        self.assertEqual(
            post.call_args.args[0],
            'https://project.supabase.co/storage/v1/object/'
            'private-schedules/7/11.pdf',
        )
        self.assertEqual(post.call_args.kwargs['headers']['apikey'], 'sb_secret_test')

    @patch.dict('os.environ', {
        'SUPABASE_URL': '',
        'SUPABASE_SERVICE_KEY': '',
    }, clear=False)
    @patch('academy.storage.default_storage')
    def test_local_storage_fallback(self, storage):
        storage.exists.return_value = False
        storage.save.return_value = 'tournament-schedules/2/3.png'
        path = upload_tournament_document(2, 3, b'png', 'image/png')
        self.assertEqual(path, 'local/tournament-schedules/2/3.png')

    @override_settings(TESTING=False, DEBUG=False)
    @patch.dict('os.environ', {
        'SUPABASE_URL': '',
        'SUPABASE_SERVICE_KEY': '',
    }, clear=False)
    def test_production_never_falls_back_to_local_storage(self):
        with self.assertRaisesMessage(RuntimeError, 'is not configured'):
            upload_tournament_document(2, 3, b'png', 'image/png')
        self.assertIsNone(
            signed_tournament_document_url(
                'local/tournament-schedules/2/3.png'
            )
        )

    @patch.dict('os.environ', {
        'SUPABASE_URL': 'https://project.supabase.co',
        'SUPABASE_SERVICE_KEY': 'sb_secret_test',
    }, clear=False)
    @patch('academy.storage.httpx.post')
    def test_signed_url_is_short_lived(self, post):
        post.return_value.raise_for_status.return_value = None
        post.return_value.json.return_value = {'signedURL': '/object/sign/token'}
        result = signed_tournament_document_url(
            'tournament-schedules/2/3.pdf', expires=900
        )
        self.assertEqual(
            result,
            'https://project.supabase.co/storage/v1/object/sign/token',
        )
        self.assertEqual(post.call_args.kwargs['json'], {'expiresIn': 900})


class TournamentPortalTests(TestCase):
    def setUp(self):
        self.club = _club('Portal FC')
        self.coordinator = _user(
            'coordinator@portal.test', Roles.COORDINATOR, self.club
        )
        self.coach = _user('coach@portal.test', Roles.COACH, self.club)
        self.client.force_login(self.coordinator)

    @patch(
        'portal.views.upload_tournament_document',
        return_value='tournament-schedules/1/1.pdf',
    )
    @patch(
        'portal.views.signed_tournament_document_url',
        return_value='https://signed.example/schedule',
    )
    def test_coordinator_creates_schedule_draft(self, signed, upload):
        response = self.client.post(reverse('portal:tournaments'), {
            'title': 'Cebu Youth Cup',
            'starts_on': '2026-09-15',
            'venue': 'Cebu City Sports Center',
            'document': _pdf(),
        })
        schedule = TournamentSchedule.objects.get()
        self.assertRedirects(
            response,
            reverse('portal:tournament-detail', args=[schedule.id]),
        )
        self.assertEqual(schedule.club, self.club)
        self.assertEqual(schedule.uploaded_by, self.coordinator)
        self.assertEqual(schedule.venue, 'Cebu City Sports Center')
        self.assertFalse(schedule.is_published)
        self.assertTrue(
            AuditLog.objects.filter(action='tournament.draft_created').exists()
        )
        upload.assert_called_once()

    def test_coordinator_adds_structured_fixture(self):
        schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Cup',
            document_path='local/schedule.pdf',
            uploaded_by=self.coordinator,
        )
        bracket = TournamentAgeBracket.objects.create(
            schedule=schedule,
            max_age=10,
        )
        kickoff = timezone.localtime() + timedelta(days=3)
        response = self.client.post(
            reverse('portal:tournament-detail', args=[schedule.id]),
            {
                'action': 'add-fixture',
                'fixture-age_bracket': bracket.id,
                'fixture-stage': 'Quarter-final',
                'fixture-opponent': 'TBD',
                'fixture-kickoff_at': kickoff.strftime('%Y-%m-%dT%H:%M'),
                'fixture-ends_at': (
                    kickoff + timedelta(hours=2)
                ).strftime('%Y-%m-%dT%H:%M'),
                'fixture-venue': MatchVenue.NEUTRAL,
                'fixture-location': 'Cebu City Sports Center',
                'fixture-status': FixtureStatus.SCHEDULED,
            },
        )
        self.assertRedirects(
            response,
            reverse('portal:tournament-detail', args=[schedule.id]),
        )
        fixture = TournamentFixture.objects.get()
        self.assertEqual(fixture.schedule, schedule)
        self.assertEqual(fixture.age_bracket, bracket)
        self.assertEqual(fixture.stage, 'Quarter-final')

        api = APIClient()
        api.force_authenticate(self.coordinator)
        mobile = api.get(reverse('tournament-schedules'))
        self.assertEqual(mobile.status_code, 200)
        shared_fixture = mobile.data[0]['fixtures'][0]
        self.assertEqual(str(shared_fixture['id']), str(fixture.id))
        self.assertEqual(shared_fixture['stage'], 'Quarter-final')

        api.patch(
            reverse('tournament-fixture-detail', args=[fixture.id]),
            {'stage': 'Semi-final'},
            format='json',
        )
        web = self.client.get(
            reverse('portal:tournament-detail', args=[schedule.id])
        )
        self.assertContains(web, 'Semi-final')

    def test_fixture_form_rejects_a_bracket_from_another_tournament(self):
        schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='First Cup',
            starts_on='2026-09-10',
        )
        other = TournamentSchedule.objects.create(
            club=self.club,
            title='Second Cup',
            starts_on='2026-10-10',
        )
        other_bracket = TournamentAgeBracket.objects.create(
            schedule=other,
            max_age=12,
        )
        response = self.client.post(
            reverse('portal:tournament-detail', args=[schedule.id]),
            {
                'action': 'add-fixture',
                'fixture-age_bracket': other_bracket.id,
                'fixture-stage': 'Group A',
                'fixture-opponent': 'Rivals FC',
                'fixture-kickoff_at': '2026-09-10T10:00',
                'fixture-venue': MatchVenue.NEUTRAL,
                'fixture-location': 'Pitch 1',
                'fixture-status': FixtureStatus.SCHEDULED,
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Select a valid choice')
        self.assertFalse(schedule.fixtures.exists())

    def test_coordinator_can_publish_without_document(self):
        response = self.client.post(reverse('portal:tournaments'), {
            'title': 'Fixture Later Cup',
            'starts_on': '2026-10-02',
            'venue': 'Abellana Field',
        })
        schedule = TournamentSchedule.objects.get(title='Fixture Later Cup')
        self.assertRedirects(
            response,
            reverse('portal:tournament-detail', args=[schedule.id]),
        )
        self.assertEqual(schedule.document_path, '')
        self.assertEqual(str(schedule.starts_on), '2026-10-02')

    def test_non_coordinator_cannot_manage_schedules(self):
        self.client.force_login(self.coach)
        response = self.client.get(reverse('portal:tournaments'))
        self.assertEqual(response.status_code, 403)

    def test_cross_club_schedule_is_not_found(self):
        other = _club('Other FC')
        schedule = TournamentSchedule.objects.create(
            club=other, title='Private Cup', document_path='private/path.pdf'
        )
        response = self.client.get(
            reverse('portal:tournament-detail', args=[schedule.id])
        )
        self.assertEqual(response.status_code, 404)

    def test_web_records_atomic_result_visible_to_mobile(self):
        player = _user('player@portal.test', Roles.PLAYER, self.club)
        PlayerProfile.objects.create(
            user=player,
            age=15,
            date_of_birth=date(2011, 5, 1),
            age_tier=AgeTier.DEVELOPMENT,
            position='CM',
            eligibility=Eligibility.ELIGIBLE,
        )
        schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Shared Result Cup',
            starts_on=date.today(),
            venue='Abellana Field',
            is_published=True,
            published_at=timezone.now(),
            uploaded_by=self.coordinator,
        )
        bracket = TournamentAgeBracket.objects.create(
            schedule=schedule,
            max_age=16,
        )
        fixture = TournamentFixture.objects.create(
            schedule=schedule,
            age_bracket=bracket,
            stage='Final',
            opponent='Mandaue FC',
            kickoff_at=timezone.now() - timedelta(hours=2),
            location='Pitch 1',
        )
        squad = TournamentSquad.objects.create(
            bracket=bracket,
            status=TournamentSquadStatus.PUBLISHED,
            published_at=timezone.now(),
            updated_by=self.coach,
        )
        TournamentSquadEntry.objects.create(
            squad=squad,
            player=player,
            position='CM',
            added_by=self.coach,
        )

        result_url = reverse(
            'portal:tournament-fixture-result', args=[fixture.id]
        )
        page = self.client.get(result_url)
        self.assertContains(page, 'Record tournament result')
        self.assertContains(page, player.email)
        response = self.client.post(result_url, {
            'our_score': 1,
            'opponent_score': 0,
            f'participant_{player.id}': 'on',
            f'position_{player.id}': 'CM',
            f'minutesPlayed_{player.id}': 80,
            f'goals_{player.id}': 1,
            f'shots_{player.id}': 2,
            f'shotsOnTarget_{player.id}': 1,
        })
        self.assertRedirects(
            response,
            reverse('portal:tournament-detail', args=[schedule.id]),
        )
        fixture.refresh_from_db()
        self.assertEqual(fixture.status, FixtureStatus.COMPLETED)
        self.assertEqual(fixture.completed_match.our_score, 1)
        self.assertTrue(PlayerMatchPerformance.objects.filter(
            match=fixture.completed_match,
            player=player,
            goals=1,
        ).exists())

        api = APIClient()
        api.force_authenticate(self.coordinator)
        mobile = api.get(reverse('tournament-schedules'))
        result = mobile.data[0]['fixtures'][0]['result']
        self.assertEqual(result['ourScore'], 1)
        self.assertEqual(result['match']['category'], 'TOURNAMENT')


class TournamentScheduleApiTests(APITestCase):
    def setUp(self):
        self.club = _club('Mobile FC')
        self.other_club = _club('Other Mobile FC')
        self.player = _user('player@mobile.test', Roles.PLAYER, self.club)
        self.schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Mobile Tournament',
            venue='Dynamic Herb Sports Stadium',
            document_path='tournament-schedules/1/1.pdf',
            is_published=True,
            published_at=timezone.now(),
        )
        TournamentFixture.objects.create(
            schedule=self.schedule,
            stage='Group A',
            opponent='Rivals FC',
            kickoff_at=timezone.now() + timedelta(days=1),
            location='Pitch 1',
        )
        TournamentSchedule.objects.create(
            club=self.other_club,
            title='Other Club Tournament',
            document_path='tournament-schedules/2/2.pdf',
        )

    @patch(
        'academy.serializers.signed_tournament_document_url',
        return_value='https://signed.example/schedule',
    )
    def test_club_member_reads_only_own_published_schedule(self, signed):
        self.client.force_authenticate(self.player)
        response = self.client.get(reverse('tournament-schedules'))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['title'], 'Mobile Tournament')
        self.assertEqual(
            response.data[0]['venue'], 'Dynamic Herb Sports Stadium'
        )
        self.assertEqual(
            response.data[0]['documentUrl'],
            'https://signed.example/schedule',
        )
        self.assertEqual(response.data[0]['fixtures'][0]['opponent'], 'Rivals FC')

    def test_school_staff_mobile_schedule_access_is_denied(self):
        staff = _user('staff@mobile.test', Roles.SCHOOL_STAFF, self.club)
        self.client.force_authenticate(staff)
        response = self.client.get(reverse('tournament-schedules'))
        self.assertEqual(response.status_code, 403)


class TournamentCoordinatorMobileApiTests(APITestCase):
    def setUp(self):
        self.club = _club('Coordinator Mobile FC')
        self.other_club = _club('Other Coordinator FC')
        self.coordinator = _user(
            'coordinator@mobile-management.test', Roles.COORDINATOR, self.club
        )
        self.coach = _user('coach@mobile-management.test', Roles.COACH, self.club)
        self.player = _user(
            'player@mobile-management.test', Roles.PLAYER, self.club
        )
        self.other_schedule = TournamentSchedule.objects.create(
            club=self.other_club,
            title='Other Club Draft',
            starts_on='2026-10-01',
            is_published=False,
            published_at=None,
        )

    def _create_draft(self):
        self.client.force_authenticate(self.coordinator)
        response = self.client.post(reverse('tournament-schedules'), {
            'title': 'Sinulog Cup',
            'venue': 'Cebu City Sports Center',
            'startsOn': '2026-09-20',
        })
        self.assertEqual(response.status_code, 201)
        return TournamentSchedule.objects.get(pk=response.data['id'])

    def _add_fixture(self, schedule, *, max_age=12, kickoff_at=None):
        kickoff_at = kickoff_at or timezone.now() + timedelta(days=2)
        bracket = TournamentAgeBracket.objects.create(
            schedule=schedule,
            max_age=max_age,
            academy_tiers=[AgeTier.FOUNDATION],
        )
        response = self.client.post(
            reverse('tournament-fixture-create', args=[schedule.id]),
            {
                'ageBracketId': bracket.id,
                'stage': 'Group Stage',
                'opponent': 'Rivals FC',
                'kickoffAt': kickoff_at.isoformat(),
                'endsAt': (kickoff_at + timedelta(hours=2)).isoformat(),
                'venue': MatchVenue.NEUTRAL,
                'location': 'Pitch 1',
                'status': FixtureStatus.SCHEDULED,
            },
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        return bracket, TournamentFixture.objects.get(schedule=schedule)

    def test_coordinator_creates_a_document_optional_draft(self):
        schedule = self._create_draft()
        self.assertFalse(schedule.is_published)
        self.assertIsNone(schedule.published_at)
        self.assertEqual(str(schedule.starts_on), '2026-09-20')
        self.assertEqual(schedule.venue, 'Cebu City Sports Center')
        self.assertEqual(schedule.document_path, '')
        self.assertTrue(
            AuditLog.objects.filter(action='tournament.draft_created').exists()
        )

    def test_coach_and_player_do_not_see_same_club_draft(self):
        schedule = self._create_draft()
        self.client.force_authenticate(self.coach)
        coach_response = self.client.get(reverse('tournament-schedules'))
        self.assertEqual(coach_response.data, [])
        self.client.force_authenticate(self.player)
        player_response = self.client.get(reverse('tournament-schedules'))
        self.assertEqual(player_response.data, [])

    def test_non_coordinator_cannot_create_or_mutate_tournament(self):
        self.client.force_authenticate(self.coach)
        create_response = self.client.post(reverse('tournament-schedules'), {
            'title': 'Denied Cup', 'startsOn': '2026-09-20',
        })
        self.assertEqual(create_response.status_code, 403)
        patch_response = self.client.patch(
            reverse('tournament-schedule-detail', args=[self.other_schedule.id]),
            {'title': 'Changed'},
            format='json',
        )
        self.assertEqual(patch_response.status_code, 403)

    def test_coordinator_adds_edits_and_removes_draft_bracket(self):
        schedule = self._create_draft()
        add_response = self.client.post(
            reverse('tournament-bracket-create', args=[schedule.id]),
            {
                'maxAge': 8,
                'academyTiers': [AgeTier.FOUNDATION],
                'scheduledAt': '2026-09-20T08:00:00Z',
            },
            format='json',
        )
        self.assertEqual(add_response.status_code, 201)
        self.assertEqual(add_response.data['ageBrackets'][0]['label'], 'U8')
        bracket = TournamentAgeBracket.objects.get(schedule=schedule)
        edit_response = self.client.patch(
            reverse('tournament-bracket-detail', args=[bracket.id]),
            {'maxAge': 10, 'academyTiers': [AgeTier.FOUNDATION]},
            format='json',
        )
        self.assertEqual(edit_response.status_code, 200)
        bracket.refresh_from_db()
        self.assertEqual(bracket.max_age, 10)
        delete_response = self.client.delete(
            reverse('tournament-bracket-detail', args=[bracket.id])
        )
        self.assertEqual(delete_response.status_code, 204)

    def test_duplicate_bracket_and_cross_club_mutation_are_rejected(self):
        schedule = self._create_draft()
        url = reverse('tournament-bracket-create', args=[schedule.id])
        self.assertEqual(
            self.client.post(
                url,
                {'maxAge': 8, 'academyTiers': [AgeTier.FOUNDATION]},
                format='json',
            ).status_code,
            201,
        )
        self.assertEqual(
            self.client.post(
                url,
                {'maxAge': 8, 'academyTiers': [AgeTier.FOUNDATION]},
                format='json',
            ).status_code,
            400,
        )
        self.assertEqual(
            self.client.post(url, {'maxAge': 22}, format='json').status_code,
            400,
        )
        other_url = reverse(
            'tournament-bracket-create', args=[self.other_schedule.id]
        )
        self.assertEqual(
            self.client.post(other_url, {'maxAge': 10}, format='json').status_code,
            404,
        )

    def test_publish_requires_bracket_and_exposes_tournament_to_player(self):
        schedule = self._create_draft()
        publish_url = reverse('tournament-schedule-publish', args=[schedule.id])
        self.assertEqual(self.client.post(publish_url).status_code, 400)
        self.client.post(
            reverse('tournament-bracket-create', args=[schedule.id]),
            {'maxAge': 12},
            format='json',
        )
        self.assertEqual(self.client.post(publish_url).status_code, 400)
        bracket = TournamentAgeBracket.objects.get(schedule=schedule)
        self.assertEqual(
            self.client.post(
                reverse('tournament-fixture-create', args=[schedule.id]),
                {
                    'ageBracketId': bracket.id,
                    'stage': 'Group Stage',
                    'opponent': 'TBD',
                    'kickoffAt': '2026-09-20T08:00:00Z',
                    'endsAt': '2026-09-20T10:00:00Z',
                    'venue': MatchVenue.NEUTRAL,
                    'location': 'Pitch 1',
                    'status': FixtureStatus.SCHEDULED,
                },
                format='json',
            ).status_code,
            201,
        )
        publish_response = self.client.post(publish_url)
        self.assertEqual(publish_response.status_code, 200)
        self.assertTrue(publish_response.data['isPublished'])
        self.client.force_authenticate(self.player)
        rows = self.client.get(reverse('tournament-schedules')).data
        self.assertEqual([row['title'] for row in rows], ['Sinulog Cup'])

    def test_published_bracket_cannot_be_removed(self):
        schedule = self._create_draft()
        add_response = self.client.post(
            reverse('tournament-bracket-create', args=[schedule.id]),
            {'maxAge': 8, 'academyTiers': [AgeTier.FOUNDATION]},
            format='json',
        )
        bracket_id = add_response.data['ageBrackets'][0]['id']
        self.client.post(
            reverse('tournament-fixture-create', args=[schedule.id]),
            {
                'ageBracketId': bracket_id,
                'stage': 'Group Stage',
                'opponent': 'TBD',
                'kickoffAt': '2026-09-20T08:00:00Z',
                'endsAt': '2026-09-20T10:00:00Z',
                'venue': MatchVenue.NEUTRAL,
                'location': 'Pitch 1',
                'status': FixtureStatus.SCHEDULED,
            },
            format='json',
        )
        self.client.post(reverse('tournament-schedule-publish', args=[schedule.id]))
        response = self.client.delete(
            reverse('tournament-bracket-detail', args=[bracket_id])
        )
        self.assertEqual(response.status_code, 400)

    @patch(
        'academy.views.upload_tournament_document',
        return_value='tournament-schedules/1/8.pdf',
    )
    @patch(
        'academy.serializers.signed_tournament_document_url',
        return_value='https://example.test/schedule.pdf',
    )
    def test_mobile_creation_with_valid_optional_document(self, _signed, upload):
        self.client.force_authenticate(self.coordinator)
        response = self.client.post(
            reverse('tournament-schedules'),
            {
                'title': 'Document Cup',
                'venue': 'Abellana Field',
                'startsOn': '2026-10-10',
                'document': _pdf(),
            },
            format='multipart',
        )
        self.assertEqual(response.status_code, 201, response.data)
        schedule = TournamentSchedule.objects.get(title='Document Cup')
        self.assertFalse(schedule.is_published)
        self.assertTrue(response.data['hasDocument'])
        upload.assert_called_once()

    def test_mobile_document_rejects_invalid_type_and_oversize(self):
        schedule = self._create_draft()
        url = reverse('tournament-schedule-document', args=[schedule.id])
        invalid = SimpleUploadedFile(
            'schedule.txt', b'plain text', content_type='text/plain'
        )
        response = self.client.post(url, {'document': invalid}, format='multipart')
        self.assertEqual(response.status_code, 400)
        oversized = SimpleUploadedFile(
            'large.pdf',
            b'%PDF-' + b'x' * (5 * 1024 * 1024),
            content_type='application/pdf',
        )
        response = self.client.post(
            url, {'document': oversized}, format='multipart'
        )
        self.assertEqual(response.status_code, 400)

    def test_coordinator_adds_edits_and_deletes_manual_fixture(self):
        schedule = self._create_draft()
        bracket, fixture = self._add_fixture(schedule)
        edit = self.client.patch(
            reverse('tournament-fixture-detail', args=[fixture.id]),
            {
                'ageBracketId': bracket.id,
                'stage': 'Quarterfinal',
                'opponent': 'TBD',
                'kickoffAt': (timezone.now() + timedelta(days=4)).isoformat(),
                'endsAt': (
                    timezone.now() + timedelta(days=4, hours=2)
                ).isoformat(),
                'venue': MatchVenue.AWAY,
                'location': 'Mandaue Sports Complex',
                'status': FixtureStatus.POSTPONED,
            },
            format='json',
        )
        self.assertEqual(edit.status_code, 200, edit.data)
        fixture.refresh_from_db()
        self.assertEqual(fixture.stage, 'Quarterfinal')
        self.assertEqual(fixture.status, FixtureStatus.POSTPONED)
        delete = self.client.delete(
            reverse('tournament-fixture-detail', args=[fixture.id])
        )
        self.assertEqual(delete.status_code, 204)
        self.assertTrue(
            AuditLog.objects.filter(action='tournament.fixture_deleted').exists()
        )

    def test_fixture_mutation_is_coordinator_only_and_club_scoped(self):
        schedule = self._create_draft()
        bracket, _fixture = self._add_fixture(schedule)
        self.client.force_authenticate(self.coach)
        response = self.client.post(
            reverse('tournament-fixture-create', args=[schedule.id]),
            {
                'ageBracketId': bracket.id,
                'stage': 'Final',
                'opponent': 'Rivals FC',
                'kickoffAt': timezone.now().isoformat(),
                'venue': MatchVenue.HOME,
                'location': 'Home Pitch',
                'status': FixtureStatus.SCHEDULED,
            },
            format='json',
        )
        self.assertEqual(response.status_code, 403)
        self.client.force_authenticate(self.coordinator)
        cross_club = self.client.post(
            reverse('tournament-fixture-create', args=[self.other_schedule.id]),
            {},
            format='json',
        )
        self.assertEqual(cross_club.status_code, 404)

    def test_result_is_atomic_links_history_and_protects_completed_fixture(self):
        schedule = self._create_draft()
        bracket, fixture = self._add_fixture(
            schedule,
            max_age=12,
            kickoff_at=timezone.now() - timedelta(days=1),
        )
        publish = self.client.post(
            reverse('tournament-schedule-publish', args=[schedule.id])
        )
        self.assertEqual(publish.status_code, 200, publish.data)
        player = _user('result-player@mobile.test', Roles.PLAYER, self.club)
        PlayerProfile.objects.create(
            user=player,
            date_of_birth=date(2016, 1, 1),
            position='CM',
        )
        squad = TournamentSquad.objects.create(
            bracket=bracket,
            status=TournamentSquadStatus.PUBLISHED,
            published_at=timezone.now(),
            updated_by=self.coach,
        )
        TournamentSquadEntry.objects.create(
            squad=squad,
            player=player,
            position='CM',
            added_by=self.coach,
        )
        payload = {
            'ourScore': 2,
            'opponentScore': 1,
            'participants': [{
                'playerId': player.id,
                'statistics': {
                    'position': 'CM',
                    'starter': True,
                    'minutesPlayed': 80,
                    'goals': 1,
                    'assists': 1,
                    'shots': 2,
                    'shotsOnTarget': 1,
                    'passesAttempted': 30,
                    'passesCompleted': 24,
                    'tackles': 3,
                    'interceptions': 2,
                    'yellowCards': 0,
                    'redCards': 0,
                    'saves': 0,
                    'goalsConceded': 0,
                    'cleanSheet': False,
                },
            }],
        }
        url = reverse('tournament-fixture-result', args=[fixture.id])
        response = self.client.post(url, payload, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        fixture.refresh_from_db()
        self.assertEqual(fixture.status, FixtureStatus.COMPLETED)
        match = FootballMatch.objects.get(pk=fixture.completed_match_id)
        self.assertEqual(match.category, 'TOURNAMENT')
        performance = PlayerMatchPerformance.objects.get(
            match=match, player=player,
        )
        self.assertEqual(performance.goals, 1)
        self.assertEqual(performance.recorded_by, self.coordinator)
        self.assertEqual(response.data['lifecycleStatus'], 'COMPLETED')
        self.assertTrue(AuditLog.objects.filter(
            action='tournament.fixture_result_recorded'
        ).exists())
        self.assertEqual(self.client.post(url, payload, format='json').status_code, 400)
        self.assertEqual(
            self.client.patch(
                reverse('tournament-fixture-detail', args=[fixture.id]),
                {'stage': 'Changed'},
                format='json',
            ).status_code,
            400,
        )
        self.assertEqual(
            self.client.delete(
                reverse('tournament-fixture-detail', args=[fixture.id])
            ).status_code,
            400,
        )
        self.assertEqual(
            self.client.delete(
                reverse('tournament-schedule-detail', args=[schedule.id])
            ).status_code,
            400,
        )

    def test_result_requires_published_squad_and_prevents_generic_bypass(self):
        schedule = self._create_draft()
        _bracket, fixture = self._add_fixture(
            schedule,
            kickoff_at=timezone.now() - timedelta(days=1),
        )
        self.client.post(reverse('tournament-schedule-publish', args=[schedule.id]))
        response = self.client.post(
            reverse('tournament-fixture-result', args=[fixture.id]),
            {'ourScore': 1, 'opponentScore': 0, 'participants': []},
            format='json',
        )
        self.assertEqual(response.status_code, 400)
        bypass = self.client.post(
            reverse('football-matches'),
            {'fixtureId': fixture.id, 'ourScore': 1, 'opponentScore': 0},
            format='json',
        )
        self.assertEqual(bypass.status_code, 400)
        self.assertFalse(FootballMatch.objects.exists())
