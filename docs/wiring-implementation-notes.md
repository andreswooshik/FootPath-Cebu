# Mock → Real Data Wiring — Implementation Notes

**Date:** 2026-07-16 · Follows [the approved plan](../../.claude/plans/) and the
[audit](audit/audit-report.md).

Topology (unchanged from ADR 0001): **Flutter → Django REST → Supabase Postgres**.
Firebase does identity + push; Supabase hosts Postgres and player-photo storage.
The Flutter client never talks to Supabase directly.

---

## What shipped

### Backend — new `academy` Django app
- **Models:** `PlayerProfile` (1:1 with a PLAYER user, six 0–99 ratings, tier,
  eligibility, photo path), `TrainingSession` (tiers as a JSON list, display-string
  times), `Attendance`, `DeviceToken` (FCM).
- **Endpoints** (all under `/api/`, Firebase-auth + role-scoped):
  `players/`, `players/me/`, `players/linked/`, `players/<id>/assessment/` (PUT),
  `attendance/?player=<id>`, `training-sessions/` (GET/POST), `devices/` (POST),
  `admin/players/<id>/photo/` (POST, Admin).
- **Object-level authz (audit F3):** a guardian can only read a player they are
  linked to; a player only themselves; coach/admin any. Enforced server-side, tested.
- **Serializers** emit the exact camelCase wire contract the existing Flutter
  `fromJson` factories parse — no client parser changes.
- **Push:** creating a training session fans out an FCM notification to players in
  the targeted tiers + their guardians (`academy/notifications.py`), best-effort,
  dead-token pruning.
- **Seed:** `python manage.py seed_academy` populates profiles, a schedule,
  attendance, and a guardian link for an instant demo.
- **Tests:** 24 new (RBAC, BOLA, wire-contract, assessment, sessions, devices,
  photo authz, notification fan-out). Backend total: **46 passing**.

### Flutter — flip to live + persistence
- **Release-safe wiring (audit F1):** the composition root
  (`core/di/providers.dart`, `useMockData`) selects live data whenever
  `kReleaseMode`; mock only in debug (override with `--dart-define=USE_MOCK=false`).
  A release build can no longer ship the demo-password mock auth.
- **Configurable API base:** `--dart-define=API_BASE_URL=…` (falls back to the
  localhost/emulator defaults).
- **Coach assessments persist:** new `AssessmentWriter` interface +
  `SavePlayerAssessment` use case + `EditPerformanceController`; the edit screen now
  PUTs to the backend instead of only showing a snackbar.
- **Device registration** through the existing layering (`DeviceRepository` →
  `RegisterDevice`, called once post-login).
- **State management is Riverpod** (ADR 0002, accepted): providers/controllers in
  `presentation/providers/`, `ConsumerWidget` screens, provider-based composition
  root replacing the static `ServiceLocator`.
- Tests total: **55 passing**; analyzer clean.

### Production hardening (audit F4–F6, F9–F11)
- CORS wildcard gated behind `DEBUG`; explicit `CORS_ORIGINS` in prod (F5).
- `if not DEBUG:` HTTPS/HSTS/secure-cookie block; `ALLOWED_HOSTS` from env;
  `manage.py check --deploy` clean apart from the intentional `X_FRAME_OPTIONS=SAMEORIGIN`
  (needed by Jazzmin admin) (F6).
- Token revocation checked on state-changing requests (F4).
- Admin console builds rows with `textContent`/`createElement` — no `innerHTML` with
  server data (F9).
- Player-card `Image.network` decodes at card size (F10); dead `_VerifiedFacilityCard`
  removed (F11).
- CI workflow added (`.github/workflows/ci.yml`): backend tests + `check --deploy`,
  Flutter analyze + test.

---

## Open decision — enabling on-device push (FCM)

The **backend push pipeline is complete and tested.** The only missing piece is the
on-device FCM **token source**, and it is blocked by a dependency conflict:

- `firebase_auth` is pinned to **exactly `6.5.4`**, which requires
  `firebase_core_platform_interface ^7.1.0`.
- The current `firebase_messaging` (16.4.2) is incompatible with that platform
  interface (it expects `firebase_core` to still export `FirebasePlugin` /
  `pluginConstants`, removed in `firebase_core 4.12.0`).

So `firebase_messaging` was **not** added. Instead the token source is an injected
seam: `ApiDeviceRepository([PushTokenProvider? tokenProvider])`. With no provider
(today's default) device registration is a logged no-op — the app works fully,
just without push. Everything else (permission flow shape, the POST to
`/api/devices/`, the backend fan-out) is in place.

**To turn push on**, pick one and then pass a token provider where
`deviceRepositoryProvider` builds `ApiDeviceRepository`
(`lib/core/di/providers.dart`):

1. **Unpin `firebase_auth`** (e.g. `^6.5.4` → let a newer `firebase_auth` +
   `firebase_core_platform_interface ^8` resolve), then add a compatible
   `firebase_messaging`. Re-run the full test suite — auth is well covered.
2. **Wait** for a `firebase_messaging` release compatible with
   `firebase_core_platform_interface 7.1.0`.

Then:
```dart
// core/di/providers.dart, deviceRepositoryProvider
ApiDeviceRepository(() async {
  await FirebaseMessaging.instance.requestPermission();
  return FirebaseMessaging.instance.getToken();
});
```
The Android manifest already declares `POST_NOTIFICATIONS`; the google-services
plugin is already applied.

---

## Go-live: point the backend at Supabase

Code needs **no change** — the Postgres block in `config/settings.py` activates when
`DB_HOST` is set. Steps:

1. Create the Supabase project. From **Project Settings → Database**, copy the pooler
   host/user/password.
2. Fill `backend/.env` from `backend/.env.example`: `DB_HOST`, `DB_NAME`, `DB_USER`,
   `DB_PASSWORD`, `DB_PORT` (and `DJANGO_SECRET_KEY`).
3. `python manage.py migrate`
4. `python manage.py seed_users` (needs Firebase service-account JSON in
   `backend/secrets/`), then `python manage.py seed_academy`.
5. Verify `/admin/` and `/console/` against the hosted DB.
6. For player photos: create a **private** `player-photos` bucket, set `SUPABASE_URL`
   and `SUPABASE_SERVICE_KEY` in `.env`, then upload via the admin console.

## Verify end to end

- Backend: `python manage.py test` (46) · `check --deploy`.
- Flutter: `flutter test` (53) · `flutter analyze`.
- Live: run debug with `--dart-define=USE_MOCK=false` against the running Django
  server; sign in as the seeded coach → roster loads from the DB → edit an
  assessment → relaunch, ratings persisted → schedule a session → sign in as the
  linked guardian → child's attendance visible; a non-linked guardian gets 403.
