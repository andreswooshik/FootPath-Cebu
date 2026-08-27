"""Security headers for the server-rendered portal pages.

Scoped to the ``/portal/`` path so the JSON API and Jazzmin admin remain
untouched. Portal CSS and JavaScript are served locally, allowing a restrictive
policy without runtime compilation, inline scripts, or third-party origins.
"""

_CSP = (
    "default-src 'self'; "
    "img-src 'self' data:; "
    "style-src 'self'; "
    "font-src 'self'; "
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
