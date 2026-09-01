from django.test import TestCase

class EmergencyConsoleRemovalTests(TestCase):
    def test_emergency_console_is_not_publicly_routed(self):
        response = self.client.get('/console/')

        self.assertEqual(response.status_code, 404)
