from django.test import TestCase
from django.urls import reverse

from .models import Club, Roles, User


class ClubApplicationReviewAdminTests(TestCase):
    def setUp(self):
        self.super_admin = User.objects.create_superuser(
            username='application-review-admin',
            email='application-review-admin@footpath.test',
            password='Admin!Galaxy2026',
            role=Roles.ADMIN,
        )
        self.club = Club.objects.create(
            name='Submitted School FC',
            slug='submitted-school-fc',
            is_school_affiliated=True,
            school_name='Submitted National School',
            head_coach_name='Alex Santos',
            cvfa_membership='CVFA-2026-100',
        )
        self.coordinator = User.objects.create_user(
            username='coordinator@submitted.test',
            email='coordinator@submitted.test',
            password='Coordinator!Galaxy2026',
            role=Roles.COORDINATOR,
            club=self.club,
            is_active=False,
        )
        self.client.force_login(self.super_admin)
        self.url = reverse('admin:accounts_club_change', args=[self.club.pk])

    def test_pending_application_is_read_only_and_has_decision_buttons(self):
        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'The submitted details are read-only.')
        self.assertContains(response, 'name="_approve_application"', html=False)
        self.assertContains(response, 'name="_not_approve_application"', html=False)
        self.assertNotContains(response, 'name="name"', html=False)
        self.assertNotContains(
            response, 'name="is_school_affiliated"', html=False
        )
        self.assertContains(response, 'Submitted School FC')
        self.assertContains(response, 'Submitted National School')

    def test_approve_activates_coordinator_without_changing_application(self):
        response = self.client.post(
            self.url,
            {
                '_approve_application': '1',
                'name': 'Tampered Club Name',
                'is_school_affiliated': '',
                'school_name': '',
            },
        )

        self.assertRedirects(response, self.url)
        self.club.refresh_from_db()
        self.coordinator.refresh_from_db()
        self.assertTrue(self.club.is_active)
        self.assertTrue(self.coordinator.is_active)
        self.assertEqual(self.club.name, 'Submitted School FC')
        self.assertTrue(self.club.is_school_affiliated)
        self.assertEqual(self.club.school_name, 'Submitted National School')

    def test_not_approve_deactivates_application_without_changing_details(self):
        response = self.client.post(
            self.url,
            {
                '_not_approve_application': '1',
                'name': 'Tampered Club Name',
                'is_school_affiliated': '',
                'school_name': '',
            },
        )

        self.assertRedirects(response, self.url)
        self.club.refresh_from_db()
        self.coordinator.refresh_from_db()
        self.assertFalse(self.club.is_active)
        self.assertFalse(self.coordinator.is_active)
        self.assertEqual(self.club.name, 'Submitted School FC')
        self.assertTrue(self.club.is_school_affiliated)
        self.assertEqual(self.club.school_name, 'Submitted National School')
