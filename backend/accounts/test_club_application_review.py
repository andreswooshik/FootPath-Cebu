import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier
from types import SimpleNamespace
from unittest import skipUnless
from unittest.mock import patch

from django.conf import settings
from django.contrib import messages
from django.contrib.admin.sites import site
from django.contrib.auth.models import Permission
from django.contrib.staticfiles.testing import StaticLiveServerTestCase
from django.db import DatabaseError, close_old_connections, connection, connections
from django.test import Client, TestCase, TransactionTestCase
from django.urls import reverse

from .admin import ClubAdmin
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
            firebase_uid='submitted-coordinator-uid',
        )
        self.firebase_state = patch(
            'accounts.admin.set_coordinator_firebase_disabled',
            return_value=True,
        ).start()
        self.addCleanup(patch.stopall)
        self.client.force_login(self.super_admin)
        self.url = reverse('admin:accounts_club_change', args=[self.club.pk])

    def test_pending_application_is_read_only_and_has_decision_buttons(self):
        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'The submitted details are read-only.')
        self.assertContains(response, 'name="_approve_application"', html=False)
        self.assertContains(response, 'name="_not_approve_application"', html=False)
        self.assertNotContains(response, 'name="name"', html=False)
        self.assertNotContains(response, 'name="is_school_affiliated"', html=False)
        self.assertContains(response, 'Submitted School FC')
        self.assertContains(response, 'Submitted National School')

    def test_approve_activates_coordinator_without_changing_application(self):
        response = self.client.post(
            self.url,
            {
                '_approve_application': '1',
                '_confirm_application': '1',
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
        self.firebase_state.assert_called_once_with(self.coordinator, disabled=False)
        self.assertEqual(User.objects.filter(club=self.club).count(), 1)
        self.assertEqual(self.coordinator.role, Roles.COORDINATOR)

    def test_failed_firebase_enable_keeps_application_pending(self):
        self.firebase_state.side_effect = RuntimeError('Firebase unavailable')

        response = self.client.post(
            self.url, {'_approve_application': '1', '_confirm_application': '1'}, follow=True
        )

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Club application approval failed.')
        self.assertNotContains(response, 'approved successfully')
        self.club.refresh_from_db()
        self.coordinator.refresh_from_db()
        self.assertTrue(self.club.is_active)
        self.assertFalse(self.coordinator.is_active)

    def test_not_approve_deactivates_application_without_changing_details(self):
        response = self.client.post(
            self.url,
            {
                '_not_approve_application': '1',
                '_confirm_application': '1',
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
        self.firebase_state.assert_called_once_with(self.coordinator, disabled=True)

    def assert_pending(self):
        self.club.refresh_from_db()
        self.coordinator.refresh_from_db()
        self.assertTrue(self.club.is_active)
        self.assertFalse(self.coordinator.is_active)

    def test_first_click_only_requests_confirmation_for_both_decisions(self):
        for field, title in (
            ('_approve_application', 'Approve Club Application?'),
            ('_not_approve_application', 'Reject Club Application?'),
        ):
            with self.subTest(field=field):
                response = self.client.post(self.url, {field: '1'})
                self.assertEqual(response.status_code, 200)
                self.assertTemplateUsed(response, 'admin/accounts/club/review_confirmation.html')
                self.assertContains(response, title)
                self.assertContains(response, 'Submitted School FC')
                self.assertContains(response, f'href="{self.url}" class="btn btn-secondary">Cancel')
                self.assert_pending()
        self.firebase_state.assert_not_called()

    def test_cancel_returns_to_details_without_any_write(self):
        for field in ('_approve_application', '_not_approve_application'):
            self.client.post(self.url, {field: '1'})
            response = self.client.get(self.url)
            self.assertContains(response, 'Pending review')
            self.assert_pending()
        self.firebase_state.assert_not_called()

    def test_confirmation_requires_the_explicit_marker(self):
        for marker in ('', '0', 'true'):
            response = self.client.post(
                self.url, {'_approve_application': '1', '_confirm_application': marker}
            )
            self.assertEqual(response.status_code, 200)
            self.assert_pending()
        self.firebase_state.assert_not_called()

    def test_dialog_is_available_and_club_name_is_html_escaped(self):
        self.club.name = 'School "FC" <script>alert(1)</script>'
        self.club.save(update_fields=['name'])
        response = self.client.get(self.url)
        self.assertContains(response, 'data-review-dialog')
        self.assertContains(response, 'footpath/club_review.js')
        self.assertContains(response, 'data-club-name="School &quot;FC&quot; &lt;script&gt;')
        self.assertNotContains(response, 'School "FC" <script>')

    def test_rejection_firebase_failure_leaves_application_pending(self):
        self.firebase_state.side_effect = RuntimeError('Firebase unavailable')
        response = self.client.post(
            self.url,
            {'_not_approve_application': '1', '_confirm_application': '1'},
            follow=True,
        )
        self.assertContains(response, 'Club application rejection failed.')
        self.assertNotContains(response, 'rejected successfully')
        self.assert_pending()

    def test_database_failure_rolls_back_and_restores_firebase_for_both_decisions(self):
        for field, disabled in (
            ('_approve_application', False),
            ('_not_approve_application', True),
        ):
            with self.subTest(field=field):
                self.firebase_state.reset_mock()
                with patch.object(User, 'save', side_effect=DatabaseError('database unavailable')):
                    response = self.client.post(
                        self.url, {field: '1', '_confirm_application': '1'}, follow=True
                    )
                self.assert_pending()
                self.assertContains(
                    response, 'No approval was saved' if not disabled else 'No rejection was saved'
                )
                self.assertEqual(self.firebase_state.call_count, 2)
                self.assertEqual(
                    self.firebase_state.call_args_list[0].kwargs, {'disabled': disabled}
                )
                self.assertEqual(self.firebase_state.call_args_list[1].kwargs, {'disabled': True})

    def test_repeated_and_opposite_decisions_are_blocked_after_review(self):
        for first in ('_approve_application', '_not_approve_application'):
            with self.subTest(first=first):
                Club.objects.filter(pk=self.club.pk).update(is_active=True)
                User.objects.filter(pk=self.coordinator.pk).update(is_active=False)
                self.firebase_state.reset_mock()
                self.client.post(self.url, {first: '1', '_confirm_application': '1'})
                for repeated in ('_approve_application', '_not_approve_application'):
                    response = self.client.post(
                        self.url, {repeated: '1', '_confirm_application': '1'}, follow=True
                    )
                    self.assertContains(response, 'already been reviewed')
                    self.assertNotContains(response, 'data-review-dialog')
                self.assertEqual(self.firebase_state.call_count, 1)
                self.club.refresh_from_db()
                self.coordinator.refresh_from_db()
                self.assertEqual(self.club.is_active, first == '_approve_application')
                self.assertEqual(self.coordinator.is_active, first == '_approve_application')

    def test_non_admin_roles_cannot_review_even_with_django_permissions(self):
        change_permission = Permission.objects.get(
            codename='change_club', content_type__app_label='accounts'
        )
        for role in (Roles.COORDINATOR, Roles.COACH, Roles.GUARDIAN, Roles.PLAYER):
            with self.subTest(role=role):
                user = User.objects.create_user(username=f'review-{role}', role=role, is_staff=True)
                user.user_permissions.add(change_permission)
                self.client.force_login(user)
                page = self.client.get(self.url)
                self.assertEqual(page.status_code, 200)
                self.assertNotContains(page, 'name="_approve_application"')
                for field in ('_approve_application', '_not_approve_application'):
                    response = self.client.post(self.url, {field: '1', '_confirm_application': '1'})
                    self.assertEqual(response.status_code, 403)
                self.assert_pending()
        self.firebase_state.assert_not_called()

    def test_anonymous_decision_is_redirected_and_does_not_write(self):
        self.client.logout()
        response = self.client.post(
            self.url, {'_approve_application': '1', '_confirm_application': '1'}
        )
        self.assertEqual(response.status_code, 302)
        self.assertIn('/admin/login/', response.url)
        self.assert_pending()
        self.firebase_state.assert_not_called()

    def test_confirmed_decisions_require_csrf(self):
        client = Client(enforce_csrf_checks=True)
        client.force_login(self.super_admin)
        for field in ('_approve_application', '_not_approve_application'):
            response = client.post(self.url, {field: '1', '_confirm_application': '1'})
            self.assertEqual(response.status_code, 403)
        self.assert_pending()
        self.firebase_state.assert_not_called()

    def test_success_refreshes_detail_state_messages_and_pending_list(self):
        list_url = reverse('admin:accounts_club_changelist')
        for field, state, success in (
            ('_approve_application', 'APPROVED', 'approved'),
            ('_not_approve_application', 'NOT_APPROVED', 'rejected'),
        ):
            with self.subTest(field=field):
                Club.objects.filter(pk=self.club.pk).update(is_active=True)
                User.objects.filter(pk=self.coordinator.pk).update(is_active=False)
                pending = self.client.get(list_url, {'registration_state': 'PENDING'})
                self.assertContains(pending, self.club.name)
                response = self.client.post(
                    self.url, {field: '1', '_confirm_application': '1'}, follow=True
                )
                self.assertContains(response, f'data-state="{state}"')
                self.assertContains(response, f'Club application {success} successfully.')
                self.assertNotContains(response, 'data-review-dialog')
                levels = [message.level for message in response.context['messages']]
                self.assertIn(messages.SUCCESS, levels)
                pending = self.client.get(list_url, {'registration_state': 'PENDING'})
                self.assertNotContains(pending, self.club.name)
                reviewed = self.client.get(list_url, {'registration_state': state})
                self.assertContains(reviewed, self.club.name)


@skipUnless(
    os.environ.get('FOOTPATH_PLAYWRIGHT_MODULE'), 'Requires optional local Playwright module'
)
class ClubApplicationReviewBrowserTests(StaticLiveServerTestCase):
    """Exercise the real admin templates/JavaScript against an isolated test server."""

    def test_confirmation_loading_failures_and_refresh_in_browser(self):
        admin = User.objects.create_superuser(
            username='browser-review-admin', password='Browser!Galaxy2026', role=Roles.ADMIN
        )
        self.client.force_login(admin)
        urls = {}
        for scenario in (
            'approve',
            'reject',
            'approve-failure',
            'reject-failure',
            'network-failure',
            'lost-response',
            'stale',
            'no-javascript',
        ):
            club = Club.objects.create(name=f'{scenario} "FC" <Cebu>', slug=scenario)
            User.objects.create_user(
                username=f'{scenario}@browser.test',
                email=f'{scenario}@browser.test',
                role=Roles.COORDINATOR,
                club=club,
                is_active=False,
                firebase_uid=f'browser-{scenario}',
            )
            urls[scenario] = self.live_server_url + reverse(
                'admin:accounts_club_change', args=[club.pk]
            )

        def firebase_result(coordinator, *, disabled):
            if coordinator.email.startswith(('approve-failure', 'reject-failure')):
                raise RuntimeError('Simulated Firebase outage')
            return True

        environment = {
            **os.environ,
            'FOOTPATH_REVIEW_URLS': json.dumps(urls),
            'FOOTPATH_SESSION_COOKIE': self.client.cookies[settings.SESSION_COOKIE_NAME].value,
            'FOOTPATH_SESSION_COOKIE_NAME': settings.SESSION_COOKIE_NAME,
        }
        with patch(
            'accounts.admin.set_coordinator_firebase_disabled', side_effect=firebase_result
        ) as firebase:
            result = subprocess.run(
                ['node', str(Path(__file__).parent / 'browser_tests' / 'club_review.cjs')],
                env=environment,
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(firebase.call_count, 8)  # Six decisions plus two simulated failures.
        for scenario in ('approve-failure', 'reject-failure'):
            club = Club.objects.get(slug=scenario)
            self.assertTrue(club.is_active)
            self.assertFalse(club.coordinator.is_active)


@skipUnless(connection.vendor == 'postgresql', 'Requires isolated PostgreSQL test settings')
class ClubApplicationReviewConcurrencyTests(TransactionTestCase):
    def test_two_reviewers_execute_only_one_pending_decision(self):
        super_admin = User.objects.create_superuser(
            username='concurrent-review-admin', role=Roles.ADMIN
        )
        club = Club.objects.create(name='Concurrent Review FC', slug='concurrent-review-fc')
        coordinator = User.objects.create_user(
            username='concurrent-review-coordinator',
            role=Roles.COORDINATOR,
            club=club,
            is_active=False,
            firebase_uid='concurrent-review-uid',
        )
        model_admin = ClubAdmin(Club, site)
        barrier = Barrier(2)

        def decide(approve):
            close_old_connections()
            try:
                with connection.cursor() as cursor:
                    cursor.execute("SET lock_timeout = '10s'")
                barrier.wait(timeout=10)
                handler = (
                    model_admin.approve_registrations
                    if approve
                    else model_admin.disapprove_registrations
                )
                return handler(
                    SimpleNamespace(user=super_admin),
                    Club.objects.filter(pk=club.pk),
                    pending_only=True,
                )
            finally:
                connections.close_all()

        with (
            patch.object(model_admin, 'message_user'),
            patch(
                'accounts.admin.set_coordinator_firebase_disabled', return_value=True
            ) as firebase,
            ThreadPoolExecutor(max_workers=2) as executor,
        ):
            futures = [executor.submit(decide, approve) for approve in (True, False)]
            self.assertEqual(sorted(future.result(timeout=30) for future in futures), [0, 1])
            firebase.assert_called_once()
        club.refresh_from_db()
        coordinator.refresh_from_db()
        self.assertEqual(club.is_active, coordinator.is_active)
