"""Private Supabase Storage backend for club coach-license documents.

The browser submits the document to Django. Django alone holds the Supabase
secret key, stores the object in a private bucket, and exposes short-lived
signed URLs to authorized admin users through Django's FileField integration.
"""
import os
from urllib.parse import quote

import httpx
from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import FileSystemStorage, Storage
from django.core.exceptions import ImproperlyConfigured
from django.utils.deconstruct import deconstructible


def _auth_headers(key):
    if key.startswith('sb_secret_'):
        return {'apikey': key}
    if key.count('.') == 2:
        return {'apikey': key, 'Authorization': f'Bearer {key}'}
    raise ImproperlyConfigured(
        'SUPABASE_SERVICE_KEY must be an sb_secret_ key or legacy '
        'service-role JWT.'
    )


@deconstructible
class SupabaseCoachLicenseStorage(Storage):
    """Store coach licenses privately, with a local-only test/dev fallback."""

    def __init__(
        self,
        bucket_env='SUPABASE_LICENSE_BUCKET',
        default_bucket='coach-licenses',
        timeout=15.0,
    ):
        self.bucket_env = bucket_env
        self.default_bucket = default_bucket
        self.timeout = timeout

    def _config(self):
        return (
            os.environ.get('SUPABASE_URL', '').rstrip('/'),
            os.environ.get('SUPABASE_SERVICE_KEY', ''),
            os.environ.get(self.bucket_env, self.default_bucket),
        )

    def _local_storage(self):
        return FileSystemStorage()

    def _use_local(self):
        url, key, _bucket = self._config()
        if getattr(settings, 'TESTING', False):
            return True
        if url and key:
            return False
        if settings.DEBUG:
            return True
        raise ImproperlyConfigured(
            'Supabase coach-license storage is not configured.'
        )

    @staticmethod
    def _object_name(name):
        return name.replace('\\', '/').lstrip('/')

    def _save(self, name, content):
        if self._use_local():
            return self._local_storage().save(name, content)

        url, key, bucket = self._config()
        name = self._object_name(name)
        if hasattr(content, 'seek'):
            content.seek(0)
        payload = (
            b''.join(content.chunks())
            if hasattr(content, 'chunks')
            else content.read()
        )
        content_type = getattr(
            content, 'content_type', 'application/octet-stream'
        )
        endpoint = (
            f'{url}/storage/v1/object/{quote(bucket)}/'
            f'{quote(name, safe="/")}'
        )
        headers = _auth_headers(key)
        headers.update({
            'Content-Type': content_type,
            'x-upsert': 'false',
        })
        try:
            response = httpx.post(
                endpoint,
                content=payload,
                headers=headers,
                timeout=self.timeout,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise OSError(
                'Coach-license storage is temporarily unavailable.'
            ) from exc
        return name

    def _open(self, name, mode='rb'):
        if mode not in ('r', 'rb'):
            raise ValueError('Supabase coach-license files are read-only.')
        if self._use_local():
            return self._local_storage().open(name, mode)

        url, key, bucket = self._config()
        name = self._object_name(name)
        endpoint = (
            f'{url}/storage/v1/object/authenticated/{quote(bucket)}/'
            f'{quote(name, safe="/")}'
        )
        try:
            response = httpx.get(
                endpoint,
                headers=_auth_headers(key),
                timeout=self.timeout,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise OSError(
                'Coach-license storage is temporarily unavailable.'
            ) from exc
        return ContentFile(response.content, name=name)

    def exists(self, name):
        if self._use_local():
            return self._local_storage().exists(name)
        # coach_license_upload_to uses a UUID, so a preflight network request
        # would only add latency without meaningfully preventing collisions.
        return False

    def delete(self, name):
        if not name:
            return
        if self._use_local():
            return self._local_storage().delete(name)

        url, key, bucket = self._config()
        response = httpx.request(
            'DELETE',
            f'{url}/storage/v1/object/{quote(bucket)}',
            json={'prefixes': [self._object_name(name)]},
            headers=_auth_headers(key),
            timeout=self.timeout,
        )
        response.raise_for_status()

    def url(self, name):
        if self._use_local():
            return self._local_storage().url(name)

        url, key, bucket = self._config()
        name = self._object_name(name)
        endpoint = (
            f'{url}/storage/v1/object/sign/{quote(bucket)}/'
            f'{quote(name, safe="/")}'
        )
        try:
            response = httpx.post(
                endpoint,
                json={'expiresIn': 3600},
                headers=_auth_headers(key),
                timeout=self.timeout,
            )
            response.raise_for_status()
            signed = (
                response.json().get('signedURL')
                or response.json().get('signedUrl')
            )
        except httpx.HTTPError as exc:
            raise OSError(
                'Coach-license link is temporarily unavailable.'
            ) from exc
        if not signed:
            raise OSError('Supabase did not return a coach-license link.')
        return f'{url}/storage/v1{signed}'
