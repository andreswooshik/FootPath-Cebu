from django.test import TestCase
from django.urls import reverse


class EmergencyConsoleUxTests(TestCase):
    def test_console_identifies_primary_admin_and_emergency_scope(self):
        response = self.client.get(reverse('console-index'))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Emergency operations console')
        self.assertContains(response, 'Open primary admin')
        self.assertContains(response, 'href="/admin/"', count=3)
        self.assertContains(response, 'Emergency only', count=2)

    def test_console_has_accessible_forms_and_responsive_table_regions(self):
        response = self.client.get(reverse('console-index'))

        self.assertContains(response, 'id="login-form"')
        self.assertContains(response, 'id="confirmation-dialog"')
        self.assertContains(response, 'aria-live="polite"')
        self.assertContains(response, 'class="table-scroll"', count=4)
        self.assertContains(response, 'console/console.css')
