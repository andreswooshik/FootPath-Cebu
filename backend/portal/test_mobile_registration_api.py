from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse

from accounts.models import Club, Roles, User
from accounts.validators import (
    COACH_LICENSE_MAX_BYTES,
    MOBILE_COACH_LICENSE_MAX_BYTES,
)
from portal.forms import CoordinatorSignupForm
from test_uploads import pdf_bytes

PASSWORD = 'Str0ng!passphrase9'


def _license(name='license.pdf', content_type='application/pdf'):
    return SimpleUploadedFile(name, pdf_bytes(), content_type=content_type)


def _application_data(**overrides):
    data = {
        'club_name': 'Mobile United',
        'coordinator_name': 'Jamie Cruz',
        'head_coach_name': 'Coach Santos',
        'coach_license': _license(),
        'cvfa_membership': 'CVFA-MOBILE-1',
        'email': 'jamie@mobile.test',
        'password1': PASSWORD,
        'password2': PASSWORD,
    }
    data.update(overrides)
    return data


class MobileClubRegistrationApiTests(TestCase):
    def setUp(self):
        cache.clear()

    def test_submission_uses_existing_pending_club_workflow(self):
        response = self.client.post(
            reverse('mobile-club-registration'),
            _application_data(),
        )

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()['status'], 'PENDING')
        club = Club.objects.get(name='Mobile United')
        coordinator = club.coordinator
        self.assertEqual(coordinator.role, Roles.COORDINATOR)
        self.assertFalse(coordinator.is_active)
        self.assertIsNone(coordinator.firebase_uid)
        self.assertEqual(coordinator.email, 'jamie@mobile.test')
        self.assertTrue(club.coach_license.name.startswith('coach-licenses/'))

    def test_duplicate_email_and_club_are_rejected_without_new_records(self):
        first = self.client.post(
            reverse('mobile-club-registration'),
            _application_data(),
        )
        second = self.client.post(
            reverse('mobile-club-registration'),
            _application_data(coach_license=_license()),
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 400)
        self.assertEqual(Club.objects.filter(name='Mobile United').count(), 1)
        self.assertEqual(User.objects.filter(email='jamie@mobile.test').count(), 1)

    def test_school_affiliation_uses_existing_fields_and_requires_school_name(self):
        invalid = self.client.post(
            reverse('mobile-club-registration'),
            _application_data(is_school_affiliated='on'),
        )
        self.assertEqual(invalid.status_code, 400)
        self.assertIn('school_name', invalid.json()['errors'])

        valid = self.client.post(
            reverse('mobile-club-registration'),
            _application_data(
                club_name='Cebu School FC',
                email='school@mobile.test',
                coach_license=_license(),
                is_school_affiliated='on',
                school_name='Cebu High School',
            ),
        )
        self.assertEqual(valid.status_code, 201, valid.content)
        club = Club.objects.get(name='Cebu School FC')
        self.assertTrue(club.is_school_affiliated)
        self.assertEqual(club.school_name, 'Cebu High School')

    def test_mobile_limit_is_50_mb_while_portal_limit_stays_5_mb(self):
        between_limits = _license()
        between_limits.size = COACH_LICENSE_MAX_BYTES + 1
        web_form = CoordinatorSignupForm(
            data={key: value for key, value in _application_data().items() if key != 'coach_license'},
            files={'coach_license': between_limits},
        )
        self.assertFalse(web_form.is_valid())
        self.assertIn('5 MB', web_form.errors['coach_license'][0])

        mobile_file = _license()
        mobile_file.size = COACH_LICENSE_MAX_BYTES + 1
        mobile_form = CoordinatorSignupForm(
            data={key: value for key, value in _application_data().items() if key != 'coach_license'},
            files={'coach_license': mobile_file},
            coach_license_max_bytes=MOBILE_COACH_LICENSE_MAX_BYTES,
        )
        self.assertTrue(mobile_form.is_valid(), mobile_form.errors.as_text())
        self.assertEqual(
            mobile_form.fields['coach_license'].help_text,
            'JPG, PNG or PDF, max 50 MB.',
        )

        too_large = _license()
        too_large.size = MOBILE_COACH_LICENSE_MAX_BYTES + 1
        oversized_form = CoordinatorSignupForm(
            data={key: value for key, value in _application_data().items() if key != 'coach_license'},
            files={'coach_license': too_large},
            coach_license_max_bytes=MOBILE_COACH_LICENSE_MAX_BYTES,
        )
        self.assertFalse(oversized_form.is_valid())
        self.assertIn('50 MB', oversized_form.errors['coach_license'][0])

    def test_unsupported_license_type_returns_field_error(self):
        response = self.client.post(
            reverse('mobile-club-registration'),
            _application_data(
                coach_license=SimpleUploadedFile(
                    'license.txt',
                    b'not a license',
                    content_type='text/plain',
                )
            ),
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('coach_license', response.json()['errors'])
