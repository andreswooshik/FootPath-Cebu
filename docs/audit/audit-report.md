# FootPath-Cebu — Full Audit Report

**Date:** 2026-07-16
**Scope:** `footpath_cebu/` (Flutter app) + `backend/` (Django REST API + admin console)
**Branch:** `feature-full-scale-audit`

---

## 0. Scope correction (read this first)

The audit brief describes a **Cebu public-transit app**: offline-first SQLite, route
polylines, Firebase↔SQLite sync with conflict resolution, and a Supabase backend.

**None of that exists in this repository.** This codebase is a **youth sports academy
portal**:

- **Flutter app** (`footpath_cebu/`) — Coach / Player / Guardian dashboards, squad
  roster, player ratings ("FUT" cards), training scheduling, attendance viewing.
- **Django REST backend** (`backend/`) — Firebase-ID-token auth, role-based access
  control (RBAC), admin account provisioning, guardian↔player links.
- **Auth:** Firebase Authentication (ID tokens verified server-side by Django Admin SDK).
- **Persistence:** Django ORM on SQLite (dev) or Postgres (prod, optionally Supabase-hosted).

Consequences for the brief:

| Brief section | Applicability | Why |
|---|---|---|
| Offline-first / SQLite schema / sync / cache invalidation | **N/A** | No on-device SQLite, no offline layer, no sync engine. App is online-only HTTP. |
| Route polylines / stops / N+M route queries | **N/A** | No transit domain in the code. |
| Supabase Auth / RLS | **N/A** | Supabase, if used, is only a Postgres host; auth is Firebase, authz is Django RBAC. |
| Firestore security rules / Cloud Functions / Storage buckets | **N/A** | No Firestore, Functions, or Storage in use — only Firebase **Auth**. |
| Layer separation / SOLID / DI | **Applies** | Audited below. |
| Firebase token handling, RBAC, secrets, deps | **Applies** | Audited below. |
| Widget rebuilds, query efficiency | **Applies (small scale)** | Audited below. |

Everything below reflects the code that is actually here. The single most important
finding (F1) is a direct consequence of this mismatch: the app's "live" data path
points at REST endpoints the backend does not implement, and the app currently ships
wired to a **mock auth repository that accepts a shared demo password for any email**.

---

## Verification status

- Backend tests: **22 passed** (`manage.py test`).
- Flutter tests: **48 passed** (`flutter test`).
- Flutter analyzer: **1 warning** (unused element), no errors.
- No secrets found in git history (`*service-account*`, `*.pem`, `.env`, `db.sqlite3` never committed); `.gitignore` is thorough.

Overall the code quality is **high**: clean layering, narrow interfaces, honest comments,
env-based config, disciplined secret hygiene. Most findings are about *unfinished* wiring
and *pre-production* toggles, not broken design.

---

## Findings

Severity uses: 🔴 CRITICAL · 🟠 HIGH · 🟡 MEDIUM · 🔵 LOW.

---

### 🟠 F1 — App ships wired to mock auth that accepts a shared password for any email
**CWE-798 (Hard-coded Credentials) / CWE-1188 (Insecure Default)**
`footpath_cebu/lib/main.dart:13`, `footpath_cebu/lib/data/repositories/mock_auth_repository.dart:25`

`main.dart` hardcodes `ServiceLocator.initMock()`. The mock auth repository authenticates
**any email** as long as the password is `demo123` (or matches a hardcoded map), and it
mints a role purely from the email string (`coach@…` → COACH, `admin@…` → ADMIN):

```dart
// mock_auth_repository.dart:25
final isValidAccount = mockAccounts[email] == password || password == 'demo123';
```

If a release build is cut from the current tree, the entire login + RBAC story is a
client-side illusion: anyone can sign in as an admin by typing `admin@anything / demo123`,
and no server ever validates it.

This is expected for UI development, but there is **no compile-time guard** preventing a
mock build from shipping. The switch is a hand-edited comment.

✅ **Fix** — gate the wiring on build mode so a release build cannot use mocks:

```dart
// main.dart
import 'package:flutter/foundation.dart' show kReleaseMode;

if (kReleaseMode) {
  ServiceLocator.initFirebase();
} else {
  // Flip locally for UI work; never in a release build.
  ServiceLocator.initMock();
}
```

Optionally, make it explicit via a dart-define (`--dart-define=USE_MOCK=true`) and assert
it is never set in release. 🧪 Test: `test-cases.dart` → `main wiring never selects mock in release mode` (a
guard test asserting the selection function returns the Firebase wiring when `kReleaseMode` is true).

---

### 🟠 F2 — The "live" data layer calls REST endpoints the backend does not implement
**CWE-1059 (Incomplete Design) — availability/integrity, not a classic vuln**
`api_player_repository.dart:14,17,22`, `api_attendance_repository.dart:12`, `api_training_repository.dart:12` vs `backend/accounts/urls.py`

The Flutter live repositories GET/POST:

- `/api/players/`, `/api/players/linked/`, `/api/players/me/`
- `/api/attendance/?player=<id>`
- `/api/training-sessions/` (GET + POST)

The backend `urlpatterns` only expose: `auth/me/`, `health/`, `admin/users/`,
`admin/guardian-links/`, `admin/guardian-links/<pk>/`. **None** of the player,
attendance, or training endpoints exist. `ServiceLocator.initFirebase()` therefore
produces an app that 404s on every dashboard.

This is why the app is pinned to mocks (F1) — the live backend for the core domain is
not built yet. It's a roadmap gap, but it matters for the audit because **the security
properties the brief asks about (user isolation, guardian-can-only-see-their-child,
coach-can-only-edit-their-squad) do not exist server-side yet** — they are enforced only
by mock data shape.

✅ **Fix** — build the missing DRF viewsets with object-level authorization *before*
flipping to live (see F3 for the authorization requirement). Until then, keep the app on
mocks and treat "live mode" as non-functional. This is an **architectural** item (1–3 days).

---

### 🟠 F3 — No object-level authorization design for domain reads (when endpoints are built)
**CWE-639 (Authorization Bypass Through User-Controlled Key) / OWASP API1:2023 BOLA**
`api_attendance_repository.dart:21` (`?player=$playerId`), backend (endpoints absent)

The attendance read is keyed by a client-supplied `player` id. The guardian dashboard
passes `selectedChild.id`. There is currently no server code to check that the requesting
guardian is actually linked to that player (the `GuardianLink` table exists but nothing
consults it on a data read). When F2's endpoints are implemented, the naïve version
(`Attendance.objects.filter(player=request.GET['player'])`) is a textbook BOLA: any
authenticated guardian could read any player's attendance by changing the id.

✅ **Fix** — enforce the link server-side, e.g.:

```python
# when you build AttendanceListView
def get_queryset(self):
    user = self.request.user
    player_id = self.request.query_params.get('player')
    if user.role == Roles.GUARDIAN:
        if not GuardianLink.objects.filter(
            guardian=user, player_id=player_id
        ).exists():
            raise PermissionDenied('Not your linked player.')
    elif user.role == Roles.COACH:
        ...  # scope to the coach's squad
    return Attendance.objects.filter(player_id=player_id)
```

🧪 Test: `guardian cannot read a non-linked player's attendance` (403). This is a
**design requirement to record now**, implement with F2.

---

### 🟡 F4 — Signed-out / revoked Firebase tokens stay valid up to ~1 hour server-side
**CWE-613 (Insufficient Session Expiration)**
`backend/accounts/authentication.py:35-39`

`verify_id_token` is called with `check_revoked=False` (documented as a deliberate
perf tradeoff). Firebase ID tokens live ~1 hour. If a user signs out, or an admin
disables/revokes an account, any already-issued token keeps authenticating until it
expires. For an academy portal this is a low-to-moderate risk, but "logout properly
invalidates access" (a brief requirement) is **not** currently true on the server.

✅ **Fix** — enable revocation checking on sensitive/stateful routes (writes, admin),
keeping it off for cheap reads if you want the perf:

```python
decoded = firebase_auth.verify_id_token(
    token, clock_skew_seconds=10, check_revoked=True
)
except firebase_auth.RevokedIdTokenError:
    raise exceptions.AuthenticationFailed('Session revoked. Sign in again.')
```

Note the local-account gate already helps: `is_active=False` locally blocks the user at
`User.objects.get(..., is_active=True)` even without revocation checks. 🧪 Test:
`disabled user is rejected even with a still-valid token` (already effectively covered by
the `is_active` filter — add an explicit case).

---

### 🟡 F5 — `CORS_ALLOW_ALL_ORIGINS = True` must not reach production
**CWE-942 (Overly Permissive CORS)**
`backend/config/settings.py:170`

Correctly commented as dev-only (Flutter web uses a random localhost port). But it is
unconditional — there is no environment gate, so a careless deploy ships wildcard CORS.

✅ **Fix** — gate on DEBUG / env:

```python
if DEBUG:
    CORS_ALLOW_ALL_ORIGINS = True
else:
    CORS_ALLOWED_ORIGINS = os.environ.get('CORS_ORIGINS', '').split(',')
```

---

### 🟡 F6 — No production settings hardening (HTTPS/HSTS/secure cookies)
**CWE-16 (Configuration)**
`backend/config/settings.py`

`DEBUG` and `SECRET_KEY` are correctly env-driven, and `ALLOWED_HOSTS` is set — good.
But there is no production block for `SECURE_SSL_REDIRECT`, `SECURE_HSTS_SECONDS`,
`SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `SECURE_PROXY_SSL_HEADER`. The Django
admin (`/admin/`) and console (`/console/`) are session-cookie based and would be served
over plaintext without these.

✅ **Fix** — add a `if not DEBUG:` hardening block setting the above. 🧪 Verify with
`manage.py check --deploy` (currently would emit several W-series warnings).

---

### 🔵 F7 — Admin provisioning silently adopts a pre-existing Firebase account by email
**CWE-286 (Incorrect User Management) — low, admin-only path**
`backend/accounts/services.py:37-45`

`link_or_create_firebase_user` adopts any existing Firebase account matching the email
and leaves its password untouched. In a shared Firebase project this is intended
behavior (and clearly noted to the admin), but it means a local role can be bound to a
Firebase identity the academy never created a password for. Low risk because the endpoint
is `IsAdmin`-only and the note surfaces it, but worth a confirmation step in the UI.

✅ **Fix (optional)** — require an explicit `adopt_existing=true` flag before linking a
pre-existing Firebase account, so adoption is never silent.

---

### 🔵 F8 — Admin user/link lists are unpaginated
**Performance / CWE-770 (Resource Allocation) — negligible at current scale**
`backend/accounts/views.py:44,70`; `console/static/console/app.js:44` renders all rows

`AdminUserListCreateView` and the guardian-link list return the full table and the
console renders every row with `innerHTML`. Fine for an academy (dozens–hundreds of
users); would degrade at thousands. No DRF pagination is configured globally.

✅ **Fix** — add `REST_FRAMEWORK['DEFAULT_PAGINATION_CLASS']` +
`PAGE_SIZE`. The Flutter list parsers already handle a paginated `{results: [...]}`
shape, so the app side is ready.

---

### 🔵 F9 — Console renders server strings via `innerHTML` (latent XSS if data becomes user-controlled)
**CWE-79 (XSS) — latent; currently admin-only data**
`backend/console/static/console/app.js:55-59, 79-83`

User emails/names are interpolated into `tr.innerHTML` without escaping. Today all values
come from admin-provisioned records and the console is admin-only, so exploitability is
low. But `first_name`/`last_name` are free-text fields — an admin who pastes
`<img onerror>` into a name, or any future self-service field, becomes stored XSS in the
console.

✅ **Fix** — build rows with `textContent`/`createElement` instead of `innerHTML`, or
escape interpolated values.

---

### 🔵 F10 — `Image.network` for player photos has no caching or size bounds
**Performance — minor**
`footpath_cebu/lib/presentation/widgets/player_card.dart:165`, `edit_performance_data_screen.dart:182`

Player photos use raw `Image.network` (has an `errorBuilder` — good) but no disk cache
and no `cacheWidth`, so the roster grid re-fetches and decodes full-resolution images on
every rebuild/scroll.

✅ **Fix** — add `cached_network_image` (or at least `cacheWidth:`/`cacheHeight:` on the
`Image.network` calls) once real photo URLs exist.

---

### 🔵 F11 — Unused private widget (`_VerifiedFacilityCard`)
**Dead code — analyzer warning**
`footpath_cebu/lib/presentation/screens/schedule_session_screen.dart:424`

Only analyzer issue in the tree. Remove it.

---

## SOLID / architecture scorecard

The app is a clean textbook Clean-Architecture + MVVM implementation. Verified against
the brief's SOLID checklist:

| Principle | Verdict | Evidence |
|---|---|---|
| **Single Responsibility** | ✅ Pass | Entities are pure immutable data (`player.dart`, `attendance.dart`); ViewModels hold only presentation state; repos do only I/O; `services.provision_user` isolates the multi-step provisioning transaction. |
| **Open/Closed** | ✅ Pass | Adding a 4th age tier is one enum case + switch arms; every tier-aware widget iterates `AgeTier.values` (`age_tier.dart:7`, comment at `training_session.dart:50`). Adding a transit-type-equivalent = extend, don't modify. |
| **Liskov** | ✅ Pass | `Mock*`, `Api*`, `Firebase*` repos are substitutable behind the same interfaces; `ServiceLocator` swaps them at the composition root with no downstream change. |
| **Interface Segregation** | ✅ Strong | Reads are split into `SquadRepository`, `PlayerProfileRepository`, `LinkedPlayersRepository`, `PlayerAttendanceReader`; each use case depends on the *narrow* one so a Coach VM literally cannot reach a guardian's reads (`player_repository.dart:20-28`). |
| **Dependency Inversion** | ✅ Pass | ViewModels depend on use cases → abstract repositories. `firebase_auth`/`http`/JSON never leak past the data layer; the presentation layer never imports Firebase. |

**Layer separation:** presentation → domain ← data, Dependency Rule respected. Domain is
pure Dart (no Flutter/Firebase/HTTP imports). Business logic is not leaking into widgets
(screens are thin; the one exception is deliberate — form field state lives in the View
and is handed back as a draft, documented in `edit_performance_data_screen.dart:9`).

**Circular dependencies:** none found. Entities don't import repositories; ViewModels
don't import each other.

**DI consistency:** one composition root (`ServiceLocator`) using constructor injection
into use cases. It is a static service locator rather than an injected container — fine
for this size, but note ViewModels are constructed directly in `initState` (e.g.
`coach_dashboard_screen.dart:27`), which couples each screen to `ServiceLocator`. Acceptable;
if you later add scoped/testable widget DI (e.g. `provider`), route it through here.

**Won't-scale patterns from the brief:** the "load all routes into SQLite at startup",
"missing DB indices on route search", "polylines as JSON strings" concerns are **N/A** —
no such subsystem. The one real scale note is F8 (unpaginated admin lists).

---

## Top-3 performance bottlenecks (per brief)

At current scale (academy: tens–hundreds of players) performance is a non-issue. Ranked
by *future* impact:

1. **Unpaginated admin list + full-table `innerHTML` render** (F8/F9) — **effort: S.**
2. **Uncached `Image.network` in the roster grid** (F10) — **effort: S.**
3. **`getIdToken()` on every repository call** (`api_*_repository.dart`) — the Firebase
   SDK caches and only refreshes hourly, so this is effectively free; no action. **effort: n/a.**

No N+1 queries (the domain reads are single GETs), no `setState` in loops, no oversized
`Consumer`/`ListenableBuilder` scopes (they wrap only the reactive column, not the whole
tree).

---

## Test-coverage gaps

- **RBAC (backend): well covered** — 22 tests exercise every admin endpoint against every
  role, auth-required paths, and token→user mapping (with Firebase mocked).
- **Provisioning: covered** — `test_provisioning.py` (16 tests) including the
  orphaned-Firebase-account compensation path.
- **Flutter: good** — entity round-trips, ViewModel filter/error paths, dashboard/widget
  tests (48 tests).
- **Gaps:**
  - No test asserting **mock wiring can't ship in release** (F1) — add the guard test.
  - No **object-level authz** tests (F3) — because the endpoints don't exist yet; add
    with F2.
  - No `manage.py check --deploy` gate in CI (there is **no CI at all** — `.github/` has
    no workflows). Add one.
  - The brief's "sync conflict resolution" and "offline→online transition" tests are
    **N/A** (no sync layer).

See `test-cases.dart` for runnable unit tests covering the top issues.
