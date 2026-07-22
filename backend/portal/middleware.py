"""Security headers for the server-rendered portal pages.

Scoped to the `/portal/` path so the JSON API, the Jazzmin `/admin/` site and
the `/console/` SPA (which load cross-origin CDN assets) are untouched. All
portal assets are same-origin, so a strict `default-src 'self'` policy holds
with no inline styles or scripts (OWASP A03 injection / A05 misconfiguration).
"""

_CSP = (
    "default-src 'self'; "
    "img-src 'self' data:; "
    "style-src 'self'; "
    "script-src 'self'; "
    "form-action 'self'; "
    "frame-ancestors 'none'; "
    "base-uri 'self'; "
    "object-src 'none'"
)


class PortalSecurityHeadersMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        if request.path.startswith('/portal/'):
            response.setdefault('Content-Security-Policy', _CSP)
            response.setdefault('Referrer-Policy', 'same-origin')
            response['X-Content-Type-Options'] = 'nosniff'
        return response
