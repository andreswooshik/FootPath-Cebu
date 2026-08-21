"""Supabase Storage helper for player photos.

The Flutter app never talks to Supabase — Django uploads with the service key
(server-only) and hands the client a short-lived signed URL. We call the
Storage REST API directly with httpx rather than pulling the full supabase-py
SDK for two endpoints.

Every function degrades gracefully when Supabase env vars are unset (local
dev / tests): uploads raise a clear error, signed-URL generation returns None
so `photoUrl` is simply null and the client shows its avatar fallback.
"""
import os

from django.core.cache import cache
import httpx

_TIMEOUT = 10.0
MAX_PHOTO_BYTES = 5 * 1024 * 1024
ALLOWED_PHOTO_TYPES = frozenset({'image/jpeg', 'image/png', 'image/webp'})


def _config():
    url = os.environ.get('SUPABASE_URL')
    key = os.environ.get('SUPABASE_SERVICE_KEY')
    bucket = os.environ.get('SUPABASE_PHOTO_BUCKET', 'player-photos')
    return url, key, bucket


def is_configured():
    url, key, _ = _config()
    return bool(url and key)


def _auth_headers(key):
    """Build Storage API headers for supported server-side Supabase keys.

    Current ``sb_secret_`` keys are opaque values and must be sent through
    ``apikey`` rather than parsed as bearer JWTs. Legacy service-role keys are
    JWTs; sending them in both headers preserves the authenticated service-role
    context while satisfying the API gateway. A publishable key is never an
    acceptable substitute for the backend-only service credential.
    """
    if key.startswith('sb_secret_'):
        return {'apikey': key}
    if key.count('.') == 2:
        return {'apikey': key, 'Authorization': f'Bearer {key}'}
    raise RuntimeError(
        'SUPABASE_SERVICE_KEY must be an sb_secret_ key or legacy '
        'service-role JWT.'
    )


def validate_photo_upload(upload):
    """Validate size, declared type, and file signature before storage upload."""
    content_type = (getattr(upload, 'content_type', '') or '').lower()
    if content_type not in ALLOWED_PHOTO_TYPES:
        raise ValueError('Only JPEG, PNG, and WebP photos are allowed.')
    size = getattr(upload, 'size', None)
    if size is not None and size > MAX_PHOTO_BYTES:
        raise ValueError('Photo must be 5 MB or smaller.')
    header = upload.read(16)
    upload.seek(0)
    signatures = {
        'image/jpeg': header.startswith(b'\xff\xd8\xff'),
        'image/png': header.startswith(b'\x89PNG\r\n\x1a\n'),
        'image/webp': header.startswith(b'RIFF') and header[8:12] == b'WEBP',
    }
    if not signatures[content_type]:
        raise ValueError('The uploaded file does not match its image type.')
    return content_type


def upload_photo(user_id, content, content_type='image/jpeg'):
    """Upload photo bytes for a user; return the storage object path.

    Overwrites any existing object at the same path (one photo per player).
    """
    url, key, bucket = _config()
    if not (url and key):
        raise RuntimeError('Supabase Storage is not configured (SUPABASE_URL / '
                           'SUPABASE_SERVICE_KEY unset).')
    ext = {'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp'}.get(
        content_type, 'jpg'
    )
    path = f'{user_id}.{ext}'
    endpoint = f'{url}/storage/v1/object/{bucket}/{path}'
    try:
        headers = _auth_headers(key)
        headers.update({
            'Content-Type': content_type,
            # Overwrite instead of erroring if the object already exists.
            'x-upsert': 'true',
        })
        resp = httpx.post(
            endpoint,
            content=content,
            headers=headers,
            timeout=_TIMEOUT,
        )
        resp.raise_for_status()
    except httpx.HTTPError as exc:
        raise RuntimeError(
            'Player photo storage is temporarily unavailable.'
        ) from exc
    return f'{bucket}/{path}'


def signed_photo_url(photo_path, expires=3600):
    """Return a signed URL for `photo_path` ("<bucket>/<object>"), or None when
    Supabase is unconfigured or the request fails (client falls back to the
    avatar initial)."""
    if not photo_path:
        return None
    cache_key = f'photo-signed-url:{expires}:{photo_path}'
    cached = cache.get(cache_key)
    if cached is not None:
        return cached
    url, key, _ = _config()
    if not (url and key):
        return None
    try:
        bucket, _, obj = photo_path.partition('/')
        endpoint = f'{url}/storage/v1/object/sign/{bucket}/{obj}'
        resp = httpx.post(
            endpoint,
            json={'expiresIn': expires},
            headers=_auth_headers(key),
            timeout=_TIMEOUT,
        )
        resp.raise_for_status()
        signed = resp.json().get('signedURL') or resp.json().get('signedUrl')
        result = f'{url}/storage/v1{signed}' if signed else None
        if result:
            cache.set(cache_key, result, timeout=max(1, expires - 60))
        return result
    except Exception:
        return None


def invalidate_signed_photo_url(photo_path, expires=3600):
    """Discard a cached signed URL after replacing its storage object."""
    if photo_path:
        cache.delete(f'photo-signed-url:{expires}:{photo_path}')
