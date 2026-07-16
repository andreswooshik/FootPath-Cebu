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

import httpx

_TIMEOUT = 10.0


def _config():
    url = os.environ.get('SUPABASE_URL')
    key = os.environ.get('SUPABASE_SERVICE_KEY')
    bucket = os.environ.get('SUPABASE_PHOTO_BUCKET', 'player-photos')
    return url, key, bucket


def is_configured():
    url, key, _ = _config()
    return bool(url and key)


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
    resp = httpx.post(
        endpoint,
        content=content,
        headers={
            'Authorization': f'Bearer {key}',
            'Content-Type': content_type,
            # Overwrite instead of erroring if the object already exists.
            'x-upsert': 'true',
        },
        timeout=_TIMEOUT,
    )
    resp.raise_for_status()
    return f'{bucket}/{path}'


def signed_photo_url(photo_path, expires=3600):
    """Return a signed URL for `photo_path` ("<bucket>/<object>"), or None when
    Supabase is unconfigured or the request fails (client falls back to the
    avatar initial)."""
    if not photo_path:
        return None
    url, key, _ = _config()
    if not (url and key):
        return None
    try:
        bucket, _, obj = photo_path.partition('/')
        endpoint = f'{url}/storage/v1/object/sign/{bucket}/{obj}'
        resp = httpx.post(
            endpoint,
            json={'expiresIn': expires},
            headers={'Authorization': f'Bearer {key}'},
            timeout=_TIMEOUT,
        )
        resp.raise_for_status()
        signed = resp.json().get('signedURL') or resp.json().get('signedUrl')
        return f'{url}/storage/v1{signed}' if signed else None
    except Exception:
        return None
