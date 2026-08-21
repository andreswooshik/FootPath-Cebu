from unittest.mock import patch

from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase


class ReadinessProbeTests(APITestCase):
    def test_readiness_checks_database_and_cache(self):
        response = self.client.get(reverse('readiness'))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'ready')
        self.assertEqual(
            response.data['checks'], {'database': True, 'cache': True},
        )

    @patch('accounts.views.cache.get', side_effect=RuntimeError('cache down'))
    def test_readiness_returns_503_without_exposing_error(self, _cache_get):
        response = self.client.get(reverse('readiness'))
        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(response.data['status'], 'unavailable')
        self.assertFalse(response.data['checks']['cache'])
        self.assertNotIn('cache down', str(response.data))
