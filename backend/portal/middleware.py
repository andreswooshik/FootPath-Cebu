"""Security headers for the server-rendered portal pages.

Scoped to the `/portal/` path so the JSON API and the Jazzmin `/admin/` site
are untouched.

The portal's design system runs on Tailwind's Play CDN and Alpine.js, both of
which compile/evaluate expressions at runtime (`new Function`-style eval) —
there is no way to allow them without `'unsafe-eval'`, and Tailwind's
JS-injected <style> tag needs `'unsafe-inline'` on style-src. This is a real,
conscious loosening of the original `default-src 'self'` policy (OWASP A03
injection / A05 misconfiguration), accepted specifically to allow these named
CDN origins — not a blanket relaxation.
"""

_CSP = (
    "default-src 'self'; "
    "img-src 'self' data:; "
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
    "font-src 'self' https://fonts.gstatic.com; "
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' "
    "https://cdn.tailwindcss.com https://unpkg.com; "
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
