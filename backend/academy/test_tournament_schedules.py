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
        kickoff = timezone.localtime() + timedelta(days=3)
        response = self.client.post(
            reverse('portal:tournament-detail', args=[schedule.id]),
            {
                'action': 'add-fixture',
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
        self.assertEqual(fixture.stage, 'Quarter-final')

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
