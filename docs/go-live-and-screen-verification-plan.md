# Go-Live & Screen Verification Plan — Real Firebase + Supabase, Zero Mock Data

**Goal:** run every Flutter screen against the real stack — Firebase Auth (identity) →
Django REST → Supabase Postgres — with `USE_MOCK=false`, and prove each screen loads,
reads, and writes real data.

**Architecture (unchanged, per [ADR 0001](decisions/0001-roles-source-of-truth.md)):**
Flutter → Django REST → Supabase Postgres. Firebase = identity only. Supabase = Postgres
host + private photo storage, always *behind* Django. The Flutter app never calls
Supabase or Firestore directly. This plan changes **config and one code gap**, not the
architecture.

---

## 1. Reality check — where each screen stands today

The mock/live switch is a single flag: `useMockData` in
[`lib/core/di/providers.dart`](../footpath_cebu/lib/core/di/providers.dart). It is
`false` in release builds and can be forced in debug with `--dart-define=USE_MOCK=false`.
When live, each screen hits these Django endpoints:

| # | Screen | Role | Backend endpoint(s) | Live-ready today? |
|---|--------|------|---------------------|-------------------|
| 1 | `login_screen` | all | Firebase Auth + `GET /api/auth/me/` | ✅ |
| 2 | `home_screen` (role router) | all | (routes on `profile.role`) | ✅ — Admin/School-Staff fall to a placeholder (no Flutter UI by design) |
| 3 | `coach_dashboard_screen` | Coach | `GET /api/players/` | ✅ |
| 4 | `coach_profile_screen` | Coach | profile + Firebase change-password | ✅ |
| 5 | `player_profile_screen` (coach view) | Coach | from squad list | ✅ |
| 6 | `edit_performance_data_screen` | Coach | `PUT /api/players/<id>/assessment/` | ✅ |
| 7 | `training_schedule_screen` | Coach | `GET /api/training-sessions/` | ✅ |
| 8 | `schedule_session_screen` | Coach | `POST /api/training-sessions/` | ✅ |
| 9 | **`log_attendance_screen`** | Coach | session attendance GET/POST | ❌ **BLOCKED — endpoint missing + repo throws `UnimplementedError`** |
| 10 | `player_dashboard_screen` | Player | `GET /api/players/me/`, `/api/attendance/?player=`, `/api/training-sessions/` | ✅ |
| 11 | `guardian_dashboard_screen` | Guardian | `GET /api/players/linked/`, `/api/attendance/?player=` | ✅ |

**The single blocker (screen 9):**
[`api_attendance_repository.dart`](../footpath_cebu/lib/data/repositories/api_attendance_repository.dart)
`fetchAttendanceForSession` / `saveSessionAttendance` throw
`UnimplementedError('pending backend wiring')`, and
[`backend/academy/urls.py`](../backend/academy/urls.py) has no per-session attendance
route. So with `USE_MOCK=false` this screen either errors or silently reads stale mock
state. **Phase 3 closes this gap** — until then, "all screens on real data" is not
achievable.

> Not blockers for screen testing: on-device push (device registration is a logged no-op
> until `firebase_messaging` is unpinned — screens still work), and the absence of
> Admin/School-Staff Flutter screens (out of scope by decision — those roles use
> `/admin/` and `/console/`).

---

## 2. Phases

### Phase 0 — Prerequisites (local, ~10 min)
- Backend: `cd backend`, create venv, `pip install -r requirements.txt`, copy
  `.env.example` → `.env`, set `DJANGO_SECRET_KEY`. Confirm `python manage.py test`
  is green (46 tests) on SQLite before touching anything.
- Flutter: `cd footpath_cebu && flutter pub get`, then `flutter test` (55) and
  `flutter analyze` clean.
- Confirm `backend/secrets/firebase-service-account.json` exists (Admin SDK key; needed
  by `seed_users` and by token verification). It is gitignored — never commit it.

### Phase 1 — Firebase project (identity)
The client is already configured for project `footpath-cebu`
([`firebase_options.dart`](../footpath_cebu/lib/firebase_options.dart),
`android/app/google-services.json`). You need to confirm the **console** side:
1. In the [Firebase console](https://console.firebase.google.com/) for `footpath-cebu`,
   enable **Authentication → Email/Password** sign-in.
2. Under **Project settings → Service accounts**, confirm the service-account JSON in
   `backend/secrets/` matches this project (it must, for token verification to succeed).
3. Configure the **password-reset email template** (Authentication → Templates) so the
   login screen's "forgot password" flow sends a real email.
4. (iOS only, if you test iOS) add `GoogleService-Info.plist` — currently absent. Not
   needed for Android/web testing.

### Phase 2 — Supabase project (Postgres host)
No code changes — [`settings.py`](../backend/config/settings.py) switches to Postgres the
moment `DB_HOST` is set.
1. Create a Supabase project. **Project Settings → Database** → copy the **connection
   pooler** host, port, database, user, password.
2. Fill `backend/.env`:
   ```
   DB_HOST=<pooler-host>.supabase.com
   DB_NAME=postgres
   DB_USER=postgres.<project-ref>
   DB_PASSWORD=<your-db-password>
   DB_PORT=6543          # transaction pooler; settings.py auto-disables server-side cursors on 6543
   ```
3. `python manage.py migrate` — creates all tables in Supabase Postgres.

### Phase 3 — Close the attendance blocker (screen 9)
This is the one piece of new code required for full screen coverage. Two parts:
- **Backend** — add a session-attendance endpoint pair following the exact patterns in
  [`academy/views.py`](../backend/academy/views.py):
  - `GET /api/attendance/?session=<id>` → coach reads what was marked (RBAC: coach/admin
    only; reuse the `request.user.role` guard style already used in `PlayerAssessmentView`).
  - `POST /api/attendance/session/<id>/` body `{"records":[{playerId,status,effort,note}]}`
    → upsert `Attendance` rows (`update_or_create` on `(player, session)`), set
    `recorded_by=request.user`. Coach-only write.
  - Register both in [`academy/urls.py`](../backend/academy/urls.py); extend
    `AttendanceSerializer` to carry `sessionId/effort/note` (fields already exist on the
    Flutter [`Attendance`](../footpath_cebu/lib/domain/entities/attendance.dart) entity).
  - Add tests to [`academy/tests.py`](../backend/academy/tests.py) mirroring the existing
    RBAC + wire-contract style (non-coach POST → 403; round-trip GET matches POST).
- **Flutter** — replace the two `UnimplementedError` stubs in
  [`api_attendance_repository.dart`](../footpath_cebu/lib/data/repositories/api_attendance_repository.dart)
  with real HTTP calls (copy the `_requireIdToken()` + error-handling pattern already in
  that file's `fetchAttendanceForPlayer`). No interface, use-case, provider, or screen
  changes — the wiring above them is already complete.

> If you want to test the other 10 screens *before* building this, you can — just skip
> screen 9 in the checklist and come back. But "all screens" needs Phase 3 done.

### Phase 4 — Seed real data
1. `python manage.py seed_users` — creates Firebase Auth accounts (via Admin SDK) +
   matching Django users for each role. Default accounts are `*@footpathcebu.test` with a
   known dev password (see [`DJANGO_ADMIN_GUIDE.md`](DJANGO_ADMIN_GUIDE.md); rotate/remove
   before any real deployment).
2. `python manage.py seed_academy` — player profiles, a training schedule, attendance
   history, and a guardian↔player link. **Run after `seed_users`.**
3. `python manage.py createsuperuser` if you want `/admin/` access.

### Phase 5 — Run live and verify every screen
Start the backend, then launch Flutter pointed at it with mocks off.

```bash
# Terminal 1 — backend
cd backend && python manage.py runserver 0.0.0.0:8000

# Terminal 2 — Flutter (Android emulator; host reachable at 10.0.2.2)
cd footpath_cebu
flutter run --dart-define=USE_MOCK=false
#   web:            add --dart-define=API_BASE_URL=http://localhost:8000
#   physical device: --dart-define=API_BASE_URL=http://<your-LAN-IP>:8000
#                    and add that IP to DJANGO_ALLOWED_HOSTS in backend/.env
```
`API_BASE_URL` defaults are per-platform (`10.0.2.2:8000` on Android emulator,
`localhost:8000` on web/desktop) — override only when they don't match your setup
([`api_config.dart`](../footpath_cebu/lib/core/config/api_config.dart)).

**Verification checklist** (sign in as each seeded role; every row must use live data):

*Coach*
- [ ] Log in as the coach account → lands on Coach dashboard (screen 3)
- [ ] Roster loads from DB; search + age-tier filter work
- [ ] Open a player (5) → edit ratings (6) → save → **relaunch app → ratings persisted**
- [ ] Training schedule (7) shows seeded sessions
- [ ] Schedule a new session (8) → it appears in the list (and DB `/admin/`)
- [ ] Open Log Attendance for a session (9) → mark Present/Absent/Excused + effort/note →
      save → reopen the session → **marks persisted from the DB** *(requires Phase 3)*
- [ ] Coach profile (4) → change password succeeds via Firebase

*Player*
- [ ] Log in as a seeded player → Player dashboard (10) shows own profile, tier, ratings
- [ ] Attendance record + schedule + eligibility status (status only, no grades) display

*Guardian*
- [ ] Log in as the seeded guardian → Guardian dashboard (11) lists the linked child
- [ ] Child's attendance/ratings/eligibility visible (read-only)
- [ ] **Negative test:** confirm a guardian cannot read a non-linked player — hit
      `GET /api/attendance/?player=<unlinked-id>` with their token → **403** (BOLA guard)

*Auth / cross-cutting*
- [ ] Sign out → returns to login; relaunch requires sign-in
- [ ] Wrong password shows a friendly error (not a stack trace)
- [ ] A Firebase user with no provisioned Django account is rejected at login

### Phase 6 — Player photos (optional, only if testing photo display)
Photos flow through Django to Supabase Storage
([`academy/storage.py`](../backend/academy/storage.py)):
1. In Supabase, create a **private** bucket `player-photos`.
2. Add to `backend/.env`: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SUPABASE_PHOTO_BUCKET=player-photos`.
3. Upload a photo via `/console/` (Admin) → the player's card shows the signed URL.

---

## 3. Definition of done
- `python manage.py test` green against SQLite; **also** run the app manually against the
  live Supabase DB (the test suite intentionally always uses SQLite).
- `flutter analyze` clean; `flutter test` green including the new attendance-repo path.
- Every checkbox in Phase 5 passes with `USE_MOCK=false`.
- No mock repository is reachable: a release build (`flutter build apk --release`) uses
  live data unconditionally — build one and smoke-test login as a final guard.

## 4. Security reminders (from [security-checklist.md](audit/security-checklist.md))
- Never commit `backend/.env` or `backend/secrets/*.json` (already gitignored — keep it so).
- The seed accounts use a shared known password — fine for local testing, must be removed
  from any Firebase project you'd expose.
- `firebase_options.dart` / `google-services.json` hold only public client config — safe
  to keep in the repo; access is gated server-side by Django.
