# Production Operations

This repository contains a production-oriented container definition, database
and Redis services, dependency-aware readiness checks, optional Sentry error
reporting, and guarded PostgreSQL backup/restore scripts. These artifacts make
deployment repeatable; they are not evidence that a live environment or restore
drill has already succeeded.

## Deployment

1. Copy `backend/.env.example` to a secret environment store. Never commit the
   populated file or Firebase service-account JSON.
2. Set `DJANGO_SECRET_KEY`, `DB_PASSWORD`, real allowed hosts/CORS origins, and
   Firebase/Supabase values as needed.
   The default `WEB_BIND_ADDRESS=127.0.0.1` expects a host reverse proxy to
   terminate TLS and forward requests to port 8000. Do not expose plain
   Gunicorn directly to the public internet.
3. Run `docker compose -f compose.production.yml build`.
4. Run `docker compose -f compose.production.yml run --rm web python manage.py check --deploy`.
5. Run `docker compose -f compose.production.yml up -d`.
6. Verify `/api/health/` for process liveness and `/api/ready/` for database
   and Redis readiness through HTTPS. Readiness intentionally covers only
   those required synchronous dependencies; verify Firebase delivery and
   Supabase Storage separately with the smoke tests below.

The container uses Gunicorn and WhiteNoise. Production logs go to stdout/stderr
for collection by the hosting platform. Setting `SENTRY_DSN` enables exception
and performance reporting without default PII capture. It runs as UID/GID
10001; ensure the mounted Firebase service-account JSON is readable by that
identity while remaining inaccessible to untrusted host users.

The `media_data` volume persists private coach-license uploads across container
recreation. Django intentionally does not expose `/media/` when `DEBUG=0`;
configure an authenticated application route or access-controlled deployment
proxy/object store for authorized retrieval. Never publish that volume as an
unauthenticated static directory.

## Monitoring and alerts

- Probe `/api/health/` every minute and alert after three failures.
- Probe `/api/ready/` every minute; it must report both `database` and `cache`
  as true.
- Alert on sustained HTTP 5xx responses, Gunicorn worker restarts, database
  storage pressure, Redis memory pressure, and backup failure.
- Configure Sentry issue alerts only after supplying the production DSN.
- Record the production URL, monitor URL, alert test date, release SHA, and
  responsible operator in the release evidence table below.

## Push delivery smoke test

Code-level foreground, inbox, unread-badge, token-refresh, and push-open paths
are automated, but transport must be checked against the real Firebase project.
For Apple builds, enable the **Push Notifications** and **Background Modes**
capabilities in Xcode and upload the APNs authentication key to Firebase; the
tracked Info.plist enables background fetch and remote-notification modes, but
the signed entitlement/provisioning profile belongs to the deployment team.
Install a non-mock build on supported Android and physical iOS devices, accept
notification permission, trigger each supported event, and record delivery,
foreground feedback, inbox creation, and push-open focus in the evidence table.

## PostgreSQL backups

Run from `backend/` with the same `DB_*` variables used by Django:

```powershell
python scripts/postgres_backup.py --output-dir D:\secure-footpath-backups --retain 14
```

Schedule it daily outside the application container. Store backups encrypted
in a separate account/location and monitor the command exit code. The default
retention is fourteen archives. PostgreSQL dumps contain only the
`coach_license` database path, not the uploaded file itself: schedule a separate
encrypted backup/snapshot of the Compose `media_data` volume and retain it with
the matching database recovery point.

## Restore drill

Restores are destructive. Use a disposable recovery database first and supply
its exact name as confirmation. The target database must already exist; the
script deliberately does not pass `--create`, so create the empty disposable
database with your PostgreSQL/provider tooling before running it:

```powershell
$env:DB_NAME = 'footpath_restore_drill'
python scripts/postgres_restore.py D:\secure-footpath-backups\footpath-YYYYMMDDTHHMMSSZ.dump --confirm-database footpath_restore_drill
python manage.py check
```

After restoration, verify record counts, a test login, Club isolation, Player
profiles, schedules, attendance, eligibility history, and notification inbox
records. Restore the matching private-media snapshot separately and verify an
authorized coach-license retrieval. Do not restore over production during a
drill.

## Release evidence

| Evidence | Result | Date/operator |
|---|---|---|
| Production URL and release SHA | Not yet supplied | — |
| Health/readiness monitor and alert test | Not yet supplied | — |
| Latest automated database and private-media backups | Not yet supplied | — |
| Successful isolated restore drill | Not yet supplied | — |
| Firebase device delivery smoke test | Not yet supplied | — |

Only replace “Not yet supplied” with links or logs from an actually executed
environment.
