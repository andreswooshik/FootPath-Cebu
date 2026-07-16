# FootPath-Cebu — Pre-Deployment Security Checklist

Run through this before cutting any build that talks to the real backend. Items
map to findings in [audit-report.md](audit-report.md). ✅ = verified good in the
current tree, ⬜ = must be done, ⚠️ = conditional.

---

## Build & wiring

- ⬜ **`main.dart` selects Firebase wiring in release** — gate `initMock()` vs
  `initFirebase()` on `kReleaseMode` (F1). A release build must never use
  `MockAuthRepository` (it accepts `demo123` for any email and self-assigns roles).
- ⬜ **Live backend endpoints exist** before flipping to `initFirebase()` — the
  player/attendance/training REST endpoints are not implemented yet (F2).
- ✅ **No secrets in the client** — `firebase_options.dart` / `google-services.json`
  hold only public Firebase client config (not secret; access is gated server-side).

## Authentication & session

- ✅ **ID tokens verified server-side** — Django Admin SDK verifies every `Bearer`
  token; unknown/unprovisioned UID is rejected (`authentication.py`).
- ✅ **Role is server-assigned, never client-submitted** — role comes from the local
  `User` row via `/api/auth/me/`; the client never sends it.
- ✅ **Account creation is Admin-only** — `IsAdmin` on provisioning; no self-signup.
- ⬜ **Token revocation on sensitive routes** — set `check_revoked=True` for
  writes/admin so logout/disable takes effect immediately (F4). (The `is_active=True`
  filter already blocks deactivated users.)
- ⚠️ **Password reset** — handled by Firebase's own verified-email flow (`sendPasswordResetEmail`);
  no custom reset endpoint to audit. Confirm Firebase email templates are configured.

## Authorization (RBAC + object-level)

- ✅ **Endpoint-level RBAC** — `role_required` permission classes; covered by 22 backend tests.
- ⬜ **Object-level authz on domain reads** — when F2 endpoints land, enforce the
  guardian↔player `GuardianLink` check and coach↔squad scoping server-side (F3). Do NOT
  trust the client-supplied `?player=<id>`.
- ✅ **Least-privilege interfaces (client)** — narrow repository interfaces stop a Coach
  ViewModel from reaching guardian/player-self reads (defense in depth, not a substitute
  for server checks).

## Backend configuration

- ⬜ **CORS gated** — `CORS_ALLOW_ALL_ORIGINS` behind `if DEBUG:`; set explicit
  `CORS_ALLOWED_ORIGINS` in prod (F5).
- ⬜ **HTTPS hardening** — add `if not DEBUG:` block: `SECURE_SSL_REDIRECT`,
  `SECURE_HSTS_SECONDS`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`,
  `SECURE_PROXY_SSL_HEADER` (F6).
- ⬜ **`manage.py check --deploy` passes** with no W-series warnings.
- ✅ **`DEBUG` off by default** — only `DJANGO_DEBUG=1` enables it.
- ✅ **`SECRET_KEY` from environment** — `os.environ['DJANGO_SECRET_KEY']`, not hardcoded.
- ✅ **`ALLOWED_HOSTS` set** — not wildcard.
- ⬜ **Rotate the dev `SECRET_KEY` / DB creds** for the production environment; never
  reuse `.env` dev values.

## Secrets & credentials

- ✅ **Service-account key gitignored** — `secrets/`, `*service-account*.json`, `*.pem`,
  `*.key` all ignored (repo + backend `.gitignore`); confirmed **never** committed in history.
- ✅ **`db.sqlite3` and `.env` gitignored**; `.env.example` template tracked.
- ⬜ **Firebase service-account JSON deployed out-of-band** (secret manager / env-mounted
  file), never baked into an image layer.
- ⬜ **Seed/dev accounts removed or disabled** in prod — `seed_users` creates
  `*@footpathcebu.test` with a known password (`FootPath!2026`); ensure these do not exist
  in the production Firebase project.

## Injection & output handling

- ⬜ **Console: no `innerHTML` with server data** — replace with `textContent`/
  `createElement` to close latent stored-XSS via free-text name fields (F9).
- ✅ **ORM parameterization** — all DB access via Django ORM / DRF serializers; no raw SQL.
- ✅ **Client JSON parsing is defensive** — `fromJson` factories null-coalesce and
  validate enum wire values (`orElse:` fallbacks).

## Data exposure & logging

- ✅ **Error messages don't leak internals** — client shows generic copy
  ("Request failed (status)"); server auth errors are terse.
- ⚠️ **Confirm no `print`/verbose logging of tokens or PII** before prod (none found in
  the audited paths, but review any logging added later).

## Dependencies

- ✅ **Pinned & current** — `firebase_auth 6.5.4`, `firebase_core ^4.11.0`,
  `http ^1.6.0`; backend `Django~=5.2`, `djangorestframework~=3.16`,
  `firebase-admin>=6.5,<8`. No known-vulnerable versions at audit time.
- ⬜ **Add `flutter pub outdated` + `pip list --outdated` to CI** and review before each release.

## CI / process

- ⬜ **Add a CI workflow** — `flutter test`, `flutter analyze`, `manage.py test`,
  `manage.py check --deploy`. None exists today (`.github/workflows` is absent).
- ✅ **Test suites green** at audit: 22 backend + 48 Flutter passing; analyzer clean
  except one dead-code warning (F11).

---

### Not applicable (documented so reviewers don't chase them)

Firestore security rules, Cloud Functions input validation, Firebase Storage bucket
permissions, offline-SQLite encryption/isolation, and sync-merge conflict handling are
**not in scope** — this project uses Firebase **Auth only**, has no on-device database,
and has no offline sync layer. See the scope correction in the audit report.
