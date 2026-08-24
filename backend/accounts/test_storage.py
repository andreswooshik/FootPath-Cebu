import os
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, override_settings

from .storage import SupabaseCoachLicenseStorage


@override_settings(TESTING=False, DEBUG=True)
class SupabaseCoachLicenseStorageTests(SimpleTestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {
            'SUPABASE_URL': 'https://project.supabase.co',
            'SUPABASE_SERVICE_KEY': 'sb_secret_test',
            'SUPABASE_LICENSE_BUCKET': 'coach-licenses',
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.storage = SupabaseCoachLicenseStorage()

    @patch('accounts.storage.httpx.post')
    def test_save_uploads_to_private_license_bucket(self, post):
        post.return_value.raise_for_status.return_value = None
        upload = SimpleUploadedFile(
            'license.pdf', b'%PDF-1.4 license', content_type='application/pdf',
        )

        name = self.storage.save('coach-licenses/random.pdf', upload)

        self.assertEqual(name, 'coach-licenses/random.pdf')
        self.assertEqual(
            post.call_args.args[0],
            'https://project.supabase.co/storage/v1/object/'
            'coach-licenses/coach-licenses/random.pdf',
        )
        self.assertEqual(
            post.call_args.kwargs['headers']['Content-Type'],
            'application/pdf',
        )

    @patch('accounts.storage.httpx.post')
    def test_url_is_a_short_lived_signed_link(self, post):
        post.return_value.raise_for_status.return_value = None
        post.return_value.json.return_value = {
            'signedURL': '/object/sign/coach-licenses/random.pdf?token=test',
        }

        result = self.storage.url('coach-licenses/random.pdf')

        self.assertEqual(
            result,
            'https://project.supabase.co/storage/v1/object/sign/'
            'coach-licenses/random.pdf?token=test',
        )
        self.assertEqual(post.call_args.kwargs['json'], {'expiresIn': 3600})

    @patch('accounts.storage.httpx.request')
    def test_delete_removes_the_private_object(self, request):
        request.return_value.raise_for_status.return_value = None

        self.storage.delete('coach-licenses/random.pdf')

        request.assert_called_once_with(
            'DELETE',
            'https://project.supabase.co/storage/v1/object/coach-licenses',
            json={'prefixes': ['coach-licenses/random.pdf']},
            headers={'apikey': 'sb_secret_test'},
            timeout=15.0,
        )
