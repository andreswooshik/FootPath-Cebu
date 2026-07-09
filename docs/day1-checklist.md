# Day 1 — Checklist

Foundation day. Note: this project is **Django-aligned** — data and roles live in Django (Postgres/SQLite), Firebase is used for auth. So a few PDF items labelled "Firestore / Custom Claims / Security Rules" are realized in their Django equivalents (noted below).

## Dev A — Backend

- [x] **Firebase project setup** — Admin SDK init (`accounts/firebase.py`), service-account credentials, Flutter `firebase_options.dart` / `google-services.json`
- [x] **Data collections** — *Django models* instead of Firestore: `User` (with `firebase_uid`, `role`) + `GuardianLink` (`accounts/models.py`)
- [x] **Authentication** — `FirebaseAuthentication` verifies the Firebase ID token → maps to the provisioned Django user (`accounts/authentication.py`)
- [x] **Custom Claims** — *realized as `User.role`* (`Roles`: ADMIN/COACH/PLAYER/SCHOOL_STAFF/GUARDIAN). Django is the source of truth for roles, not Firebase claims
- [x] **Security Rules skeleton** — *realized as DRF permission classes* `role_required(...)` → `IsAdmin` / `IsCoach` / `IsPlayer` / `IsSchoolStaff` / `IsGuardian` (`accounts/permissions.py`)

**Verify before closing Day 1**
- [x] The role→source-of-truth decision (Django, not Firebase claims) is written down so the team is aligned — see [decisions/0001-roles-source-of-truth.md](decisions/0001-roles-source-of-truth.md)
- [x] `role_required` permissions are applied to every non-public API endpoint — audited: `admin/*` → `IsAdmin`, `auth/me/` → `IsAuthenticated` (default), `health/` → `AllowAny` (intentionally public)
- [x] A provisioned test user of each role can authenticate end-to-end — covered by `backend/accounts/tests.py` (6 tests, Firebase verification mocked). For a real run: `python manage.py seed_users` then log in per role
- [x] Sensitive data is git-ignored — `backend/.env`, `backend/secrets/` (service account), plus repo-wide secret patterns in root `.gitignore`; nothing sensitive is tracked

## Dev B — Coach/Admin

- [x] **MVVM project setup** — `lib/` split into `models / viewmodels / repositories / widgets / screens`
- [x] **Admin Login UI** — Django admin console (`backend/console/`) + shared Flutter `LoginScreen`
- [x] **Coach Dashboard UI** — Active Squad Roster (`screens/coach_dashboard_screen.dart` + `widgets/player_card.dart`)
- [x] **Repository Interfaces** — `AuthRepository`, `PlayerRepository` (abstract, with mock + live implementations)

## Dev C — Player/Guardian

- [x] **Login UI** — `screens/login_screen.dart` (+ forgot-password / reset email)
- [x] **Player Dashboard UI** — `screens/player_dashboard_screen.dart` (own card, eligibility, schedule/attendance/feedback sections)
- [x] **Guardian Dashboard UI** — `screens/guardian_dashboard_screen.dart` (read-only linked children)
- [x] **Mock repositories** — `MockAuthRepository`, `MockPlayerRepository`; switch mock↔live via `ServiceLocator.initMock()` / `initFirebase()`

## Day 1 exit criteria

- [x] App runs on mock data with no backend (`ServiceLocator.initMock()`)
- [x] Each role routes to its own dashboard (`HomeScreen` role switch)
- [x] Repository interfaces exist so backends are swappable (mock → Django/Supabase/Firestore)
- [x] Test suite green (`flutter test` → 21 passing; `python manage.py test accounts` → 6 passing)
- [x] Day 1 branch merged to `main`
