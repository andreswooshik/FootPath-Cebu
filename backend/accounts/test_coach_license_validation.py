import json

from django.contrib.admin.sites import site
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse

from .admin import ClubAdmin
from .models import Club, Roles, User


class CoachLicenseAdminValidationTests(TestCase):
    def _admin_form(self, upload):
        model_admin = ClubAdmin(Club, site)
        form_class = model_admin.get_form(request=None)
        return form_class(
            data={
                'name': 'Hermanos FC',
                'slug': 'hermanos-fc',
                'head_coach_name': 'Wilbert Racines',
                'cvfa_membership': '2023031887',
                'coordinator_name': 'Andrea Santos',
                'coordinator_email': 'andrea@hermanos.test',
                'coordinator_password1': 'Zebra!Galaxy2026',
                'coordinator_password2': 'Zebra!Galaxy2026',
            },
            files={'coach_license': upload},
        )

    def test_admin_rejects_mov_before_supabase_upload(self):
        upload = SimpleUploadedFile(
            'IMG_9678.MOV',
            b'not-a-coach-license',
            content_type='video/quicktime',
        )

        form = self._admin_form(upload)

        self.assertFalse(form.is_valid())
        self.assertEqual(
            form.errors['coach_license'],
            ['Upload a JPG, PNG or PDF file.'],
        )

    def test_admin_accepts_a_real_pdf(self):
        upload = SimpleUploadedFile(
            'license.pdf',
            b'%PDF-1.4 coach license',
            content_type='application/pdf',
        )

        form = self._admin_form(upload)

        self.assertTrue(form.is_valid(), form.errors.as_text())


class ClubAdminCoordinatorCreationTests(TestCase):
    def setUp(self):
        self.super_admin = User.objects.create_superuser(
            username='superadmin',
            email='superadmin@footpath.test',
            password='Admin!Galaxy2026',
            role=Roles.ADMIN,
        )
        self.client.force_login(self.super_admin)

    @staticmethod
    def _club_data(**overrides):
        data = {
            'name': 'New United FC',
            'slug': 'new-united-fc',
            'head_coach_name': 'Head Coach',
            'cvfa_membership': 'CVFA-2026',
            'coordinator_name': 'Andrea Santos',
            'coordinator_email': 'andrea@new-united.test',
            'coordinator_password1': 'Zebra!Galaxy2026',
            'coordinator_password2': 'Zebra!Galaxy2026',
            '_save': 'Save',
        }
        data.update(overrides)
        return data

    def test_add_page_requires_coordinator_and_loads_live_password_feedback(self):
        response = self.client.get(reverse('admin:accounts_club_add'))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Coordinator account')
        self.assertContains(response, 'name="coordinator_email"', html=False)
        self.assertContains(response, 'coordinator-password-requirements')
        self.assertNotContains(response, 'name="is_active"', html=False)

    def test_add_club_creates_and_links_active_coordinator(self):
        response = self.client.post(
            reverse('admin:accounts_club_add'),
            self._club_data(),
        )

        self.assertEqual(response.status_code, 302)
        club = Club.objects.get(slug='new-united-fc')
        coordinator = club.coordinator
        self.assertIsNotNone(coordinator)
        self.assertEqual(coordinator.username, 'andrea@new-united.test')
        self.assertEqual(coordinator.email, 'andrea@new-united.test')
        self.assertEqual(coordinator.role, Roles.COORDINATOR)
        self.assertTrue(coordinator.is_active)
        self.assertTrue(coordinator.check_password('Zebra!Galaxy2026'))

    def test_mismatched_passwords_do_not_create_club_or_coordinator(self):
        response = self.client.post(
            reverse('admin:accounts_club_add'),
            self._club_data(coordinator_password2='Different!Password2026'),
        )

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'passwords do not match')
        self.assertFalse(Club.objects.filter(slug='new-united-fc').exists())
        self.assertFalse(
            User.objects.filter(email='andrea@new-united.test').exists()
        )

    def test_existing_incomplete_club_can_be_given_a_coordinator(self):
        club = Club.objects.create(name='Incomplete FC', slug='incomplete-fc')

        response = self.client.post(
            reverse('admin:accounts_club_change', args=[club.pk]),
            self._club_data(name='Incomplete FC', slug='incomplete-fc'),
        )

        self.assertEqual(response.status_code, 302)
        self.assertEqual(club.members.filter(role=Roles.COORDINATOR).count(), 1)

    def test_password_check_uses_django_validators(self):
        response = self.client.post(
            reverse('admin:accounts_club_password_check'),
            data=json.dumps({
                'password': '12345678',
                'email': 'andrea@new-united.test',
                'name': 'Andrea Santos',
            }),
            content_type='application/json',
        )

        self.assertEqual(response.status_code, 200)
        rules = response.json()['rules']
        self.assertTrue(rules['minimum_length'])
        self.assertFalse(rules['common'])
        self.assertFalse(rules['numeric'])
