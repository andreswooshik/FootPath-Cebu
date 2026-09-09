# Backend security operations

## Audit evidence

Application audit rows are append-only and cryptographically chained. Run this
after deployment and as a scheduled integrity check:

```powershell
python manage.py verify_audit_log
```

The `footpath.audit` logger emits a JSON proof for each event. Production must
ship that named log stream to an access-controlled, append-only sink (for
example, a SIEM or object storage with retention lock). Retain security audit
events for at least one year, or longer when school/league policy requires it.
Alert on a failed chain check, missing log-delivery windows, repeated 401/403/429
responses, and account lifecycle changes.

## Reverse proxy

Set `TRUSTED_PROXY_COUNT` to the exact number of trusted reverse proxies between
the public client and Django. Keep it at `0` when Django is directly exposed.
The backend ignores `X-Forwarded-For` unless this value is positive.

## API throttling

Defaults are `1200/hour` per authenticated user, `30/hour` for privacy-PIN
operations, `20/hour` for uploads, and `120/hour` for account administration.
Override them with `API_USER_RATE`, `API_PIN_RATE`, `API_UPLOAD_RATE`, and
`API_ACCOUNT_ADMIN_RATE`. Production must use the shared Redis cache so limits
are consistent across Gunicorn workers.

## Uploads

All photos, tournament documents, and coach licenses are capped at 5 MiB.
Images are fully decoded and re-encoded without metadata; PDFs are parsed,
rewritten, served as attachments, and rejected if encrypted or if they contain
scripts, launch actions, forms, rich media, or embedded files.
