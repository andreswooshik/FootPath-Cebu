from datetime import timedelta
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase

from accounts.models import Club, Roles, User

from .models import (
    AuditLog,
    FixtureStatus,
    MatchVenue,
    TournamentAgeBracket,
    TournamentFixture,
    TournamentSchedule,
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
    def test_coordinator_publishes_schedule(self, signed, upload):
        response = self.client.post(reverse('portal:tournaments'), {
            'title': 'Cebu Youth Cup',
            'starts_on': '2026-09-15',
            'document': _pdf(),
        })
        schedule = TournamentSchedule.objects.get()
        self.assertRedirects(
            response,
            reverse('portal:tournament-detail', args=[schedule.id]),
        )
        self.assertEqual(schedule.club, self.club)
        self.assertEqual(schedule.uploaded_by, self.coordinator)
        self.assertTrue(
            AuditLog.objects.filter(action='tournament.created').exists()
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


class TournamentScheduleApiTests(APITestCase):
    def setUp(self):
        self.club = _club('Mobile FC')
        self.other_club = _club('Other Mobile FC')
        self.player = _user('player@mobile.test', Roles.PLAYER, self.club)
        self.schedule = TournamentSchedule.objects.create(
            club=self.club,
            title='Mobile Tournament',
            document_path='tournament-schedules/1/1.pdf',
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
            'startsOn': '2026-09-20',
        })
        self.assertEqual(response.status_code, 201)
        return TournamentSchedule.objects.get(pk=response.data['id'])

    def test_coordinator_creates_a_document_optional_draft(self):
        schedule = self._create_draft()
        self.assertFalse(schedule.is_published)
        self.assertIsNone(schedule.published_at)
        self.assertEqual(str(schedule.starts_on), '2026-09-20')
        self.assertEqual(schedule.document_path, '')
        self.assertTrue(
            AuditLog.objects.filter(action='tournament.draft_created').exists()
        )

    def test_coach_sees_same_club_draft_but_player_does_not(self):
        schedule = self._create_draft()
        self.client.force_authenticate(self.coach)
        coach_response = self.client.get(reverse('tournament-schedules'))
        self.assertEqual(
            [row['id'] for row in coach_response.data], [schedule.id]
        )
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
            {'maxAge': 8, 'scheduledAt': '2026-09-20T08:00:00Z'},
            format='json',
        )
        self.assertEqual(add_response.status_code, 201)
        self.assertEqual(add_response.data['ageBrackets'][0]['label'], 'U8')
        bracket = TournamentAgeBracket.objects.get(schedule=schedule)
        edit_response = self.client.patch(
            reverse('tournament-bracket-detail', args=[bracket.id]),
            {'maxAge': 10},
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
            self.client.post(url, {'maxAge': 8}, format='json').status_code,
            201,
        )
        self.assertEqual(
            self.client.post(url, {'maxAge': 8}, format='json').status_code,
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
            {'maxAge': 8},
            format='json',
        )
        bracket_id = add_response.data['ageBrackets'][0]['id']
        self.client.post(reverse('tournament-schedule-publish', args=[schedule.id]))
        response = self.client.delete(
            reverse('tournament-bracket-detail', args=[bracket_id])
        )
        self.assertEqual(response.status_code, 400)
