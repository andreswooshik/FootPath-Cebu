"""A tiny cache-backed fixed-window rate limiter for the public, unauthenticated
portal endpoints (audit finding S3).

This is deliberately not a general-purpose limiter — it exists so the anonymous
signup form cannot be scripted to mass-create clubs or spool large uploads.
Fixed-window counting per (scope, client IP) is enough for that.

The cache is LocMemCache in development (settings.CACHES), which is per-process,
so a multi-worker deployment should point it at a shared backend (Redis /
Memcached) for the counter to hold across workers. Disabled under the test
suite via `RATELIMIT_ENABLE` so unrelated tests that post repeatedly are not
throttled.
"""
from ipaddress import ip_address

from django.conf import settings
from django.core.cache import cache


def _client_ip(request):
    # Trust forwarding headers only when operators declare the exact proxy
    # depth. Otherwise a client could spoof X-Forwarded-For to evade limits.
    remote = request.META.get('REMOTE_ADDR', '') or ''
    try:
        remote = str(ip_address(remote))
    except ValueError:
        return 'unknown'
    trusted_count = getattr(settings, 'TRUSTED_PROXY_COUNT', 0)
    if trusted_count <= 0:
        return remote
    forwarded = [part.strip() for part in request.META.get(
        'HTTP_X_FORWARDED_FOR', ''
    ).split(',') if part.strip()]
    chain = forwarded + [remote]
    if len(chain) <= trusted_count:
        return remote
    try:
        return str(ip_address(chain[-(trusted_count + 1)]))
    except ValueError:
        return remote


def is_rate_limited(request, *, scope, limit, window_seconds):
    """Increment and test a per-(scope, client-IP) counter.

    Returns True once the caller has made more than `limit` requests within
    `window_seconds`. A no-op (always False) when RATELIMIT_ENABLE is off.
    """
    if not getattr(settings, 'RATELIMIT_ENABLE', True):
        return False

    key = f'ratelimit:{scope}:{_client_ip(request)}'
    # add() only sets when the key is absent, so the first hit of a window
    # starts the TTL; subsequent hits increment without extending it.
    if cache.add(key, 1, timeout=window_seconds):
        count = 1
    else:
        try:
            count = cache.incr(key)
        except ValueError:
            # Expired between add() and incr(): treat as a fresh window.
            cache.set(key, 1, timeout=window_seconds)
            count = 1
    return count > limit
