# FootPath Cebu — Study Notes for Defense

> Per-file study notes: what each file does, its most important lines, and the core logic.
> Order: **backend (Django)** first, then **frontend (Flutter/Dart)**.

---

## 0. Big Picture (say this first in the defense)

**FootPath Cebu** is a youth football academy management system with two clients and one backend:

- **Flutter mobile app** (`footpath_cebu/`) — used by **Coach, Player, Guardian** (Firebase-authenticated).
- **Django web portal + admin** (`backend/portal/`, `/admin/`, `/console/`) — used by **Club Coordinator, School Staff, Superadmin** (Django session-authenticated).
- **Django REST API** (`backend/accounts/`, `backend/academy/`) — the single source of truth for all data and authorization.

**Auth flow:** the app signs in with **Firebase Auth** (email/password) → gets a Firebase **ID token** → sends it as `Authorization: Bearer <token>` to Django → Django verifies it with the Firebase **Admin SDK** and maps the UID to a local provisioned `User` row with a **role**. Roles are decided server-side, never by the client.

**Key architectural decisions to mention:**
1. **Clean Architecture on the client** — domain entities/use-cases know nothing about Firebase/HTTP; repository interfaces are swapped (mock ↔ live) at one composition root.
2. **Server-side RBAC + object-level authorization** — every endpoint re-checks who may see which player (guardian only linked children, coach only own club, etc.).
3. **Multi-tenancy by Club** — every account belongs to a `Club`; all queries are scoped by `user.club`.
4. **Offline-first attendance** — a coach can take roll call with no internet; a sqflite outbox replays saves when connectivity returns.
5. **Append-only audit trails** — eligibility history and dispute threads are never edited or deleted.

---

# PART 1 — BACKEND (Django)

## 1.1 `backend/config/` — project configuration

### `config/settings.py` (274 lines)
**Purpose:** central Django configuration — apps, database, auth, security hardening.

| Lines | What it does |
|---|---|
| 27 | `TESTING = 'test' in sys.argv` — tests always use SQLite, never touch the shared Supabase Postgres. |
| 105–126 | **Database switch**: if `DB_HOST` env var is set → Postgres (Supabase) with `sslmode=require`; else local SQLite. Line 117: disables server-side cursors on port 6543 (Supabase transaction pooler limitation). |
| 178 | `AUTH_USER_MODEL = 'accounts.User'` — the custom user model with `role` and `club` (must exist before first migrate). |
| 193–199 | **CORS**: allow-all only in DEBUG (Flutter web uses random ports); in production only explicit `CORS_ORIGINS` (audit fix F5 — never wildcard in prod). |
| 201–208 | **DRF defaults**: every API endpoint uses `FirebaseAuthentication` + `IsAuthenticated` unless it opts out. This is the single line that makes the whole API Firebase-protected. |
| 214–222 | **Production hardening (audit fix F6)**: SSL redirect, HSTS 1 year, secure cookies — applied only when `DEBUG` is off. |
| 230–274 | Jazzmin theme config for the `/admin/` site. |

**Core logic:** one settings file serves three environments (local SQLite, Supabase Postgres, test) by env vars — zero-setup for a fresh clone.

### `config/urls.py`
**Purpose:** root URL router. Lines 22–28: `/admin/` (Django admin), `/api/` (accounts + academy REST), `/console/` (SPA console), `/portal/` (coordinator/staff web portal). Line 33: serves uploaded media (coach licenses) only in DEBUG.

### `config/wsgi.py` / `config/asgi.py`
**Purpose:** standard Django server entrypoints (WSGI for production servers, ASGI for async). Boilerplate — just expose `application`.

### `backend/manage.py`
**Purpose:** Django's CLI entrypoint (`runserver`, `migrate`, `test`, `seed_users`, `seed_academy`).

---

## 1.2 `backend/accounts/` — identity, roles, provisioning

### `accounts/models.py` (116 lines)
**Purpose:** who exists in the system — users, roles, clubs, guardian↔player links.

| Lines | What it does |
|---|---|
| 8–14 | `class Roles(TextChoices)` — the six roles: `ADMIN, COORDINATOR, COACH, PLAYER, SCHOOL_STAFF, GUARDIAN`. **The whole authorization system keys off this one enum.** |
| 17–24 | `coach_license_upload_to()` — uploaded license files are renamed to a random UUID with a whitelisted extension. **Security: never trust a client filename** (path traversal / spoofing guard). |
| 27–70 | `class Club` — **the tenancy boundary**. Every coordinator owns one club; every provisioned account belongs to one. Lines 61–64: `coordinator` property (the one COORDINATOR member). Lines 66–70: `allows_school_staff` — school-staff accounts only exist for school-affiliated clubs. |
| 73–94 | `class User(AbstractUser)` — adds `firebase_uid` (line 76, unique, maps Firebase logins to local rows), `role` (line 79), and `club` (line 85, `SET_NULL` so deleting a club never deletes people). |
| 97–116 | `class GuardianLink` — the guardian↔player relation; line 113 `unique_together` prevents duplicate links. **This table is what lets a guardian see only their own children.** |

### `accounts/authentication.py` (66 lines) ⭐ most important security file
**Purpose:** the DRF authentication class that turns a Firebase ID token into a Django user.

| Lines | What it does |
|---|---|
| 20–24 | Reads the `Authorization: Bearer` header; falls through to session auth if absent (so `/admin/` still works). |
| 38 | `check_revoked = request.method not in ('GET','HEAD','OPTIONS')` — **revocation is checked only on writes** (audit fix F4): a disabled account loses write access immediately without paying an extra Firebase round trip on every read. |
| 40–42 | `firebase_auth.verify_id_token(...)` — **the core line**: cryptographically verifies the token with the Firebase Admin SDK. |
| 53–60 | Maps `decoded['uid']` → local `User` with `is_active=True`. **A valid Firebase login with no provisioned local row is rejected** — accounts only exist if an admin/coordinator created them. |

**Defense line:** "authentication is Firebase, authorization is Django — the token proves *who you are*, our `User.role` row decides *what you may do*."

### `accounts/firebase.py` (18 lines)
**Purpose:** initialize the Firebase Admin SDK exactly once per process from the service-account JSON (`ensure_initialized()`, line 7). Raises a clear error if the credentials file is missing.

### `accounts/permissions.py` (27 lines)
**Purpose:** role-based DRF permission factory.
- Lines 6–20: `role_required(*roles)` builds a permission class checking `request.user.role in roles`.
- Lines 23–27: ready-made `IsAdmin`, `IsCoach`, `IsPlayer`, `IsSchoolStaff`, `IsGuardian`.
**Core logic:** endpoint-level RBAC in one reusable function instead of repeated if-statements.

### `accounts/services.py` (128 lines) ⭐ provisioning core
**Purpose:** the *only* code paths that create accounts.

| Lines | What it does |
|---|---|
| 10 | `_PASSWORD_CHARS` excludes ambiguous characters (0/O, 1/l/I) — temp passwords are relayed by hand. |
| 17–49 | `link_or_create_firebase_user()` — ensures the email has a Firebase account: **adopts** an existing one (password untouched) or **creates** one with a temp password; marks the local Django password unusable (app users authenticate via Firebase only). |
| 52–95 | `provision_user()` — creates Firebase account + local `User` for app users (player/coach/guardian). **Lines 79–88 are the highlight: compensation logic** — if the DB save fails after a Firebase account was just created, the Firebase account is deleted so no orphaned identity remains (a mini distributed transaction). |
| 98–128 | `provision_web_user()` — coordinator/school-staff accounts get a *Django session* password and **no Firebase identity** (web-portal-only users). `is_active=False` holds a coordinator signup pending superadmin approval. |

### `accounts/serializers.py` (54 lines)
**Purpose:** wire shapes for the accounts API. `UserSerializer` (user + `role_display`), `AdminCreateUserSerializer` (email/name/role, role restricted to the four creatable roles, line 5–10), `GuardianLinkSerializer` (read: nested users; write: `guardian_id`/`player_id` PKs restricted by role, lines 41–50).

### `accounts/views.py` (78 lines)
**Purpose:** account endpoints.
- Lines 18–26: `MeView` — `GET /api/auth/me/` returns the profile+role; **reaching it at all proves login** (this is what the app calls right after Firebase sign-in).
- Lines 29–32: `health` — unauthenticated liveness check.
- Lines 35–65: `AdminUserListCreateView` — admin-only list/create; create delegates to `provision_user` and returns the one-time temp password.
- Lines 68–78: guardian-link list/create/delete (admin-only).

### `accounts/urls.py`
Routes: `auth/me/`, `health/`, `admin/users/`, `admin/guardian-links/`, `admin/guardian-links/<pk>/`.

### `accounts/admin.py` (235 lines)
**Purpose:** the customized Django admin for users/clubs/links.
- Line 12: unregisters `Group` — authorization uses `User.role`, not Django groups.
- Lines 72–94: `approve_coordinators` bulk action — **the superadmin approval gate** flipping pending coordinator signups to `is_active=True`.
- Lines 96–149: `save_model` — when an admin creates an app account in the admin site, it **auto-syncs a Firebase identity** (same provisioning as the API) and reports the outcome via admin messages.
- Rest: role/status color pills for a scannable registry (`role_badge`, `status_chip`, `access_chip`, `ClubAdmin` chips).

### `accounts/apps.py`
`ready()` initializes Firebase eagerly at boot but only warns if credentials are missing (so `migrate`/tests still run).

### `accounts/management/commands/seed_users.py` (54 lines)
**Purpose:** dev command creating the five demo role accounts (`admin@…`, `coach@…`, `player@…`, `staff@…`, `guardian@…`) in **both** Firebase and the local DB. Idempotent (`update_or_create` keyed on `firebase_uid`).

---

## 1.3 `backend/academy/` — the football domain (the biggest app)

### `academy/models.py` (406 lines) ⭐ the data model
**Purpose:** all football-domain tables. Wire enums are UPPERCASE to mirror the Flutter entities exactly (no translation layer).

| Lines | Model | Key points |
|---|---|---|
| 15–43 | Enums | `AgeTier` (FOUNDATION 10–12 / DEVELOPMENT 13–15 / PATHWAY 16–18), `Eligibility`, `SessionFocus`, `AttendanceStatus`, `ConfirmationStatus`. |
| 45–93 | `PlayerProfile` | One-to-one with a PLAYER user (line 54). Six FUT-style 0–99 ratings (lines 67–72). **Line 62: tier is *stored*, not derived from age** — a birthday mid-season never shifts a player's tier. `coach_notes` (77) = the coach's standing evaluation. `photo_path` (84) = Supabase object path (API serves a signed URL, never the raw path). |
| 96–103 | `PlayerEligibility` | **proxy model** — a narrow admin screen showing only eligibility, hiding ratings. |
| 106–152 | `EligibilityHistory` | **Append-only audit trail** of eligibility transitions, written by a model signal so *every* write path is captured. Stores only status enums, never grades. `changed_by` (127) is stashed on the instance by the write path because signals have no request context. |
| 155–193 | `TrainingSession` | Times are display strings (line 161 — client never parses them). `age_tiers` is an explicit JSON list (line 169 — a new tier never silently absorbs old sessions). `club` FK (line 180) = tenancy. |
| 196–238 | `Attendance` | One player × one session. `effort` 0–100 (line 219, session-scoped, unlike profile ratings). **Line 235 `unique_together ('player','session')` — the DB constraint behind the upsert; no duplicate roll-call rows.** |
| 241–272 | `SessionConfirmation` | The player's RSVP — "intent", vs Attendance which is "fact". Also unique per (player, session); re-confirming flips the same row. |
| 275–307 | `InjuryRecord` | Player-owned medical data; least-privilege enforced in views (player CRUD, coach/admin read, guardians nothing). |
| 310–389 | `Dispute` + `DisputeResponse` | A status ticket raised by a coach; the response thread is **append-only** (no update/delete anywhere) → the thread *is* the audit trail. `status_change_to` on a response moves the parent. |
| 392–406 | `DeviceToken` | FCM push tokens, unique per token, many per user. |

### `academy/serializers.py` (432 lines)
**Purpose:** translates models ⇄ the exact **camelCase JSON contract** the Flutter `fromJson` factories parse. "Field names here ARE the API contract."

| Lines | Serializer | Key logic |
|---|---|---|
| 38–74 | `PlayerSerializer` | **Line 44: player `id` = the underlying User id** — attendance, guardian links and profiles all key off one id. `ratings` nested object (63–71); `photoUrl` = short-lived signed URL (73–74). |
| 77–112 | `AssessmentSerializer` | Write side of the coach assessment. **Lines 101–112 `to_internal_value`: flattens the client's nested `{"ratings": {...}, "coachNotes": ...}` body** — and explicitly carries the note across (the note used to get dropped here — a real fixed bug worth mentioning). |
| 115–129 | `PlayerPositionSerializer` | Validates position against the ten legal codes (GK…ST). |
| 132–177 | `TrainingSessionSerializer` | `attendeeCount` = count of PRESENT records (151–153); validates tiers/focus/date — **line 171–176 rejects past dates**. |
| 179–209 | `AttendanceSerializer` | Coerces int PKs to strings (the client hard-casts); blank note → null (207–209). |
| 227–258 | `EligibilityHistorySerializer` | ⭐ **Privacy-aware `changedBy` (248–258): Staff/Admin see the person's name; Player/Guardian see only the role** ("School Staff") — families get accountability without staff identities. |
| 350–390 | `DisputeCreateSerializer` / `DisputeResponseCreateSerializer` | Validate category/status enums; `raised_by`/`author` are **always the request user, never client-supplied**. |
| 393–415 | `SessionAttendanceRecordSerializer` | One roll-call row: validates the player exists with PLAYER role, status enum, effort 0–100. |
| 418–433 | `AdminCreatePlayerSerializer` | The console's Add Player: name/DOB/middle-initial genuinely required; optional `guardian_id` restricted to GUARDIAN users. |

### `academy/views.py` (699 lines) ⭐ the API + authorization heart
**Purpose:** every academy REST endpoint. Two-layer authorization: role checks + object-level scoping ("never trust the client").

**Authorization helpers (memorize these):**
| Lines | Helper | Rule |
|---|---|---|
| 58–66 | `_in_same_club()` | Club match including NULL==NULL for legacy rows. |
| 69–82 | `_guardian_may_read()` | **The BOLA fix (audit F3)**: admin→anyone; coach→own club; player→self only; guardian→only `GuardianLink`ed players. |
| 85–103 | `_may_read_eligibility()` | Narrower still: **the coach is deliberately excluded** — academics belong to School Staff, not the coach. |
| 106–120 | `_sessions_for()` / `_session_in_user_scope()` | Club-scoped session visibility (admin sees all). |
| 372–383 | `_dispute_in_user_scope()` | A dispute's club = its raiser's club. |

**Endpoints:**
| Lines | View | Feature it powers |
|---|---|---|
| 123–133 | `SquadListView` | Coach dashboard roster (`GET /api/players/`), coach filtered to own club (line 131–132). |
| 136–145 | `MyProfileView` | Player dashboard (`/api/players/me/`). |
| 148–160 | `LinkedPlayersView` | Guardian dashboard — ids come from `GuardianLink` (154–156). |
| 163–181 | `PlayerAssessmentView` | Coach saves the six ratings + note. **Line 180: `transaction.on_commit(...notify_assessment_saved)` — push fires only after the DB commit** (a rolled-back save never notifies). |
| 184–204 | `PlayerPositionView` | Coach assigns a position (used to be an unimplemented client stub — now a real endpoint). |
| 207–224 | `AttendanceListView` | Player/guardian attendance history, guarded by `_guardian_may_read` (219). |
| 227–297 | `SessionAttendanceView` | ⭐ Roll call. **Lines 257–261: attendance may only be logged from the session day to 2 days after** (mirrors client `isAttendanceOpen`). Lines 269–276: every submitted player must be in the coach's club. **Lines 277–293: atomic wholesale replace — `update_or_create` per player then delete rows not in the payload** → re-finalising corrects instead of duplicating. |
| 300–322 | `TrainingSessionListCreateView` | Schedule list/create; club + creator set server-side (315–317); push on commit (319). |
| 325–369 | `SessionConfirmationView` | Player RSVP; player taken from request (361–365, upsert). |
| 386–477 | Dispute views | Coach flags (POST), staff/admin respond; **lines 465–474: response + status change applied atomically**; thread is append-only. |
| 480–509 | `EligibilityHistoryView` | Timeline read; 404-vs-403 logic (493–500) avoids leaking whether a player id exists to unauthorized callers. |
| 512–608 | Injury views | Least-privilege medical data: reads role-scoped (521–543), **writes owner-only** (`_get_record` write branch 566–569). |
| 611–628 | `DeviceRegisterView` | FCM token upsert (idempotent by token). |
| 631–652 | `PlayerPhotoUploadView` | Admin-only multipart photo upload → Supabase, stores the object path. |
| 655–699 | `AdminCreatePlayerView` | ⭐ The only way a player account is born: **one atomic transaction creates User + PlayerProfile + optional GuardianLink** (674–687), wrapped around `provision_user`. |

### `academy/urls.py` (68 lines)
Maps all the above under `/api/…` — players, attendance, training-sessions, session-confirmations, disputes, injuries, devices, admin/players.

### `academy/signals.py` (49 lines) ⭐ the audit-trail mechanism
**Purpose:** eligibility change detection on the model save cycle so *any* write path (admin site, portal, future API) is captured.
- Lines 17–26: `pre_save` stashes the currently-stored eligibility on the instance.
- Lines 29–49: `post_save` compares; if changed → **creates the append-only `EligibilityHistory` row in the same transaction** (39–44) and schedules the push via `transaction.on_commit` (47–49) so a rolled-back edit neither records nor notifies.
**Defense line:** "we hooked the model, not the views, so no future code path can bypass the audit trail."

### `academy/notifications.py` (142 lines)
**Purpose:** FCM push fan-out. Best-effort by design — **a push failure must never fail the write that triggered it**.
- Lines 20–36: `_recipients_for_session()` — players in the session's club whose tier is targeted, plus their guardians (club-scoped so tenants never cross).
- Lines 54–86: `_send_to_users()` — collects `DeviceToken`s, sends one `MulticastMessage`, swallows and logs all errors, returns success count.
- Lines 89–128: the three notification events: `notify_session_scheduled`, `notify_assessment_saved` (fires per assessment, *not* per roll-call row — 20 players ≠ 20 pushes), `notify_eligibility_changed`.
- Lines 131–142: `_prune_dead_tokens()` — deletes tokens Firebase reports unregistered.

### `academy/storage.py` (82 lines)
**Purpose:** Supabase Storage via plain `httpx` (no SDK). **The Flutter app never talks to Supabase** — Django uploads with the server-only service key and hands out short-lived signed URLs.
- Lines 31–57: `upload_photo()` — `x-upsert: true` header overwrites (one photo per player); path is `<user_id>.<ext>`.
- Lines 60–82: `signed_photo_url()` — returns a 1-hour signed URL, or `None` when unconfigured/failing (client falls back to an avatar initial). Graceful degradation for local dev.

### `academy/admin.py` (85 lines)
**Purpose:** admin surfaces for review workflows.
- Lines 12–31: `PlayerEligibilityAdmin` — the narrow eligibility screen; add disabled (24–25); **`save_model` stashes `obj._changed_by = request.user`** (27–31) so the signal's history row is attributed.
- Lines 34–52: `EligibilityHistoryAdmin` — fully read-only (no add/change/delete) — append-only even for admins.
- Lines 55–74: `DisputeAdmin` with an inline response thread ("Admin review" in one screen).

### `academy/apps.py`
`ready()` imports `signals` so the eligibility signal is registered on boot.

### `academy/management/commands/seed_academy.py` (144 lines)
**Purpose:** idempotent demo data — 6 roster players with realistic ratings, 3 sessions (2 upcoming, 1 past), attendance on the past session, and a guardian link, so all three dashboards demo instantly.

### `academy/tests.py` (1345 lines)
19 test classes covering every endpoint: role gating (Squad/MyProfile/LinkedPlayers), the guardian BOLA guard (`AttendanceAuthorizationTests`), the roll-call replace + date-window (`SessionAttendanceTests`), assessment note persistence, dispute lifecycle, injury least-privilege, device idempotency, photo upload, push fan-out targeting, the eligibility signal + endpoint privacy shaping, atomic player creation, and club tenancy (`SessionTenancyTests`).

---

## 1.4 `backend/portal/` — coordinator & school-staff web portal

### `portal/views.py` (201 lines)
**Purpose:** thin controllers — parse request, call a service, render. Club always derived from `request.user.club`, **never from client input**.
- Lines 44–68: `signup` — public club registration → `register_coordinator` → pending account.
- Lines 80–129: `create_account` ⭐ — the coordinator's tabbed Create Account page (player/coach/staff/guardian). **Lines 85–87: the staff tab is *removed server-side* for non-school clubs** (can neither render nor be submitted). On success shows the one-time credential.
- Lines 132–174: `players` / `coaches` / `guardians` — club-scoped listings (note comment on 148–153: club is the only tenancy boundary — every coach coaches every club player).
- Lines 177–201: `staff_eligibility` — school staff pick a player + status; delegates to `set_player_eligibility`.

### `portal/forms.py` (177 lines) — *currently open in your editor*
**Purpose:** the input-validation boundary for the portal.
- Lines 16–18: coach-license guardrails — 50 MB cap, extension **and** content-type allowlist.
- Lines 21–89: `CoordinatorSignupForm` — ⭐ `clean_email` (48–54) uses the generic "This email cannot be used." wording to **avoid user enumeration (OWASP A07)**; `clean_coach_license` (62–73) triple-checks ext/type/size; `clean` (80–89) enforces password match and school-name-if-affiliated.
- Lines 92–111: `_BaseCreateAccountForm` — shared identity fields; accepts a `club` kwarg so pickers can be scoped.
- Lines 122–155: `CreatePlayerForm` / `CreateGuardianForm` — **the guardian/player dropdowns only ever offer members of the coordinator's own club** (136–138, 152–154).
- Lines 158–172: `EligibilityUpdateForm` — player picker scoped to the staff member's club.

### `portal/services.py` (141 lines)
**Purpose:** portal use-cases (application layer) — transactions and tenancy rules, testable without HTTP.
- Lines 27–54: `register_coordinator` — **one atomic transaction** creates the Club (with registration evidence) + a pending (`is_active=False`) coordinator.
- Lines 57–121: `create_club_account` — provisions one account per type; staff blocked for non-school clubs (77–79, defence in depth); player creation also creates `PlayerProfile` and optional `GuardianLink`; **`_assert_same_club` (139–141) rejects cross-club links even if a form was tampered with**.
- Lines 124–136: `set_player_eligibility` — checks the club boundary, stashes `_changed_by`, saves → the academy signal writes history + push.

### `portal/decorators.py` (27 lines)
`portal_role_required(*roles)` — session-side mirror of the DRF permission: anonymous → redirect to login; wrong role → 403 (OWASP A01 Broken Access Control).

### `portal/middleware.py` (39 lines)
`PortalSecurityHeadersMiddleware` — a strict **Content-Security-Policy** + Referrer-Policy + nosniff applied only to `/portal/` paths (lines 34–38). The docstring honestly documents the conscious CSP loosening (`unsafe-eval` for Tailwind Play CDN / Alpine.js) — good defense talking point about explicit trade-offs.

### `portal/urls.py`
Dashboard, signup, login/logout (Django auth views with portal templates), create-account, players, coaches, guardians, eligibility.

### `portal/tests.py` (399 lines)
7 classes: signup creates club+pending coordinator, license type/size rejection, duplicate email & password mismatch, **pending coordinator cannot log in until approved**, school-staff gating (tab hidden, POST rejected, service refuses), role access control, account creation per type, **club isolation** (coordinator A never sees club B), staff eligibility flow, and the admin approval action.

## 1.5 `backend/console/` — the admin console shell
- `console/views.py` (5 lines): renders `console/index.html` — the console is a static SPA page that calls the `/api/admin/...` endpoints with the admin's Firebase token.
- `console/urls.py`: single route `''` → index.

---

# PART 2 — FRONTEND (Flutter / Dart)

**Layering (Clean Architecture / MVVM):**
```
presentation (screens & widgets = View, Riverpod providers = ViewModel)
    ↓ watches
domain (entities + repository INTERFACES + use-cases)   ← pure Dart, no Flutter/Firebase/HTTP imports
    ↑ implemented by
data (api_* live repos, mock_* repos, local outbox)
    ↑ wired in
core/di/providers.dart (composition root)
```

## 2.1 Entry point & core

### `lib/main.dart` (82 lines)
**Purpose:** boot the app.
- Lines 12–13: global `messengerKey` so push handlers can show SnackBars without a widget context.
- Lines 19–27: `Firebase.initializeApp` wrapped in try/catch — a missing config shows a setup screen instead of crashing.
- **Line 32: `runApp(ProviderScope(...))` — the Riverpod container that holds every provider; tests override providers on their own scope.**
- Lines 42–50: `MaterialApp` with `AppTheme.light()`, home = `LoginScreen` (or `_SetupErrorScreen`).

### `lib/core/config/api_config.dart` (19 lines)
**Purpose:** one place for the backend base URL.
- Line 10: `--dart-define=API_BASE_URL` build-time override for real devices/hosted backends.
- Line 16: `10.0.2.2` — Android emulator's loopback to the host machine (a classic defense question!).

### `lib/core/di/providers.dart` (262 lines) ⭐ the composition root
**Purpose:** the single place where abstractions are bound to implementations.
- **Lines 74–77: `useMockData` — `if (kReleaseMode) return false;`** — a release build can NEVER ship the mock auth (audit fix F1: the mock accepts a shared demo password). Debug defaults to mocks; `--dart-define=USE_MOCK=false` runs debug against the live backend.
- Lines 83–162: one `Provider` per repository interface choosing mock vs live. **Lines 100–109: live attendance is wrapped in `OfflineFirstAttendanceRepository`** (decorator + outbox). Lines 114–122: `attendanceSyncServiceProvider` drains the outbox post-login. Lines 152–162: the FCM plugin dependency is injected *here*, not in the repository (the seam keeps `firebase_messaging` out of the data layer).
- Lines 168–262: one `Provider` per **use case**, each wiring a domain class to its repository provider.

**Defense line:** "swapping the whole data source is one boolean in one file; tests do the same with `ProviderScope(overrides:)`."

### `lib/core/utils/date_format.dart` (15 lines)
Tiny date formatters (`Jul 8`, `Jul 8, 2026`) with a hand-rolled month table — no intl dependency.

### `lib/firebase_options.dart`
Generated by `flutterfire configure` — per-platform Firebase keys. Not hand-written.

---

## 2.2 Domain layer — entities (the business rules)

### `lib/domain/entities/player.dart` (253 lines) ⭐
- Lines 6–43: `EligibilityStatus` enum + `wire`/`label`/`fromWire` — the wire mapping mirrors Django exactly.
- Lines 52–139: `PlayerRatings` — the outfield six + optional GK six. **Lines 98–106: `overall` and `gkOverall` — each averages its own six and rounds.**
- Lines 142–253: `Player` — immutable model. **Lines 192–194: `overall` picks `gkOverall` for goalkeepers, outfield otherwise — the single source of the card's corner number.** Lines 202–220: `copyWith` — note the doc: null means "unchanged", so a position can never be *cleared* (a coach assigns/changes, never un-assigns). Lines 222–239: `fromJson` parses the exact serializer contract.

### `lib/domain/entities/age_tier.dart` (61 lines)
- Line 7: the three tiers. Lines 23–32: inclusive age bounds per tier.
- **Lines 55–60: `forAge()` — the default at registration only; tier is *stored*, so nobody shifts tier on a birthday** (same rationale documented on the Django model — client and server agree).

### `lib/domain/entities/training_session.dart` (134 lines)
- Lines 55: `ageTiers` as an explicit `Set<AgeTier>` (a new tier never absorbs old sessions).
- **Lines 77–83: `isAttendanceOpen` — roll call allowed from session day through 2 days after** (the client-side twin of the server rule in `SessionAttendanceView`).
- Lines 114–119: `_tiersFromJson` falls back to *all* tiers on bad data — a visibly-wrong "All Tiers" pill beats an invisible broken session.
- Lines 121–133: `toJson` sends **date-only** `YYYY-MM-DD` (Django `DateField` rejects full ISO timestamps).

### `lib/domain/entities/card_tier.dart` (40 lines)
FUT card tiers: Bronze (0+), Silver (65+), Gold (80+) as an **enhanced enum with fields** (labels, ARGB colour, threshold). Lines 26–30: `forOverall()` picks the highest earned tier. Colour is a raw ARGB int so the domain stays Flutter-free.

### `lib/domain/entities/player_position.dart` (137 lines)
- Line 4: `PositionGroup` (keeper/defence/midfield/attack) — how the picker groups.
- Lines 27–38: ten positions; **no "unassigned" member — an unassigned player is `Player.position == null`** (invalid states unrepresentable).
- Lines 129–136: `fromWire` returns null for unknown codes — never guess a position the coach didn't choose.

### `lib/domain/entities/attendance.dart` (111 lines)
Immutable record: `playerId`, `status`, `updatedAt`, optional `sessionId/sessionName/coachUid/effort/note`. Line 3: status enum. `effort` is session-scoped (one day), unlike profile ratings (long-lived).

### `lib/domain/entities/dispute.dart` (159 lines)
`DisputeCategory`, `DisputeStatus` (with UNDER_REVIEW snake-case wire), `DisputeResponse` (append-only thread entry) and `Dispute` with its `responses` list. Lines 157–158: `_blankAsNull` — backend blank strings become null in the app.

### `lib/domain/entities/injury_record.dart` (118 lines)
Player-owned medical record. Lines 103–110: `toJson` omits server-owned fields (id, playerId, timestamps) and sends date-only dates.

### `lib/domain/entities/eligibility_change.dart` (52 lines)
One audit-trail row. `changedBy` arrives **already privacy-shaped by the server** (name for staff, role for families, "System" when unknown) — the client just displays it.

### `lib/domain/entities/session_confirmation.dart` (57 lines)
The RSVP: CONFIRMED/DECLINED + `respondedAt`. "Intent vs fact" — distinct from Attendance.

### `lib/domain/entities/user_profile.dart` (61 lines)
The `/api/auth/me/` result. Lines 40: `isCoach` — a **UX gate only**; the server is the authority on writes (comment says so explicitly — quote it in defense).

## 2.3 Domain layer — repository interfaces

All follow the same pattern — worth explaining once, well:

### `lib/domain/repositories/attendance_repository.dart` ⭐ the ISP showcase
- Three narrow interfaces: `PlayerAttendanceReader` (guardian view), `SessionAttendanceReader` (coach re-opens a session), `SessionAttendanceWriter` (coach saves) — **the guardian's screen physically cannot depend on a write** (Interface Segregation Principle).
- `AttendanceRepository` aggregates all three; concrete classes implement the aggregate, consumers depend on the narrow one.
- Lines 49–51: **`AttendanceNetworkException` (server never reached) vs `AttendanceRepositoryException` (server refused)** — the distinction that makes offline-first possible: queue the first kind, surface the second.

### The others (same shape)
- `player_repository.dart`: `SquadRepository` / `PlayerProfileRepository` / `LinkedPlayersRepository` / `AssessmentWriter` / `PositionWriter` → `PlayerRepository`. `AssessmentWriter.saveAssessment` makes `coachNotes` **required** — because a notes field was once silently dropped, the compiler now catches any caller that forgets it (great "bug → design change" story).
- `auth_repository.dart`: sign-in/sign-out/reset; implementations translate Firebase errors to `AuthException` so presentation never imports `firebase_auth`.
- `training_repository.dart`, `injury_repository.dart`, `dispute_repository.dart`, `session_confirmation_repository.dart`: reader/writer split + aggregate + exception, identically.
- `eligibility_history_repository.dart`: read-only by design (history is written server-side by the signal).
- `device_repository.dart`: `registerCurrentDevice()` — best-effort, must never break login.

## 2.4 Domain layer — use cases (`lib/domain/usecases/`, 21 files)

Every use case is the same micro-pattern — one class, one injected **narrow** interface, one `call()` method:

```dart
class GetSquad {
  const GetSquad(this._repository);
  final SquadRepository _repository;          // narrow interface, not the aggregate
  Future<List<Player>> call() => _repository.fetchSquad();
}
```

Files: `sign_in`, `sign_out`, `send_password_reset`, `get_squad`, `get_my_profile`, `get_linked_players`, `save_player_assessment`, `save_player_position`, `get_player_attendance`, `get_session_attendance`, `log_session_attendance`, `get_injuries`, `save_injury`, `delete_injury`, `get_disputes`, `raise_dispute`, `respond_to_dispute`, `get_eligibility_history`, `get_session_confirmations`, `confirm_session`, `get_training_sessions`, `schedule_training_session`, `register_device`.

**Defense line:** "each use case names one business operation and depends only inward on an abstraction (the Dependency Rule); e.g. `ScheduleTrainingSession` holds a `TrainingScheduleWriter`, so it *cannot even see* the read methods."

## 2.5 Data layer — live API repositories

All share one pattern (explain once): get the Firebase **ID token** (`_requireIdToken`) → `http` request to `ApiConfig.baseUrl` with `Authorization: Bearer` → non-2xx → domain exception with a friendly message → parse JSON into entities (tolerating both a bare list and DRF-paginated `{results: []}`).

- **`api_player_repository.dart` (158 lines):** `fetchSquad`/`fetchLinkedPlayers`/`fetchMyProfile` GETs; `savePosition` (28–53) PUTs `{'position': position.wire}`; `saveAssessment` (55–88) PUTs `{'ratings': ..., 'coachNotes': ...}` — the body shape the Django `AssessmentSerializer.to_internal_value` flattens.
- **`api_attendance_repository.dart` (119 lines):** ⭐ throws **`AttendanceNetworkException` on connection errors** (lines 24–28, 50–54, 84–88) but plain `AttendanceRepositoryException` on HTTP errors — the split the offline decorator relies on. `saveSessionAttendance` POSTs `{records: [...]}`, server echoes the saved set back.
- **`firebase_auth_repository.dart` (85 lines):** ⭐ the login. Lines 22–27: Firebase sign-in; lines 31–35: **verifies the session against Django `/api/auth/me/`**; lines 37–47: if Django refuses, **signs out of Firebase too** — never keep a half-valid session; lines 67–84: `_friendlyAuthMessage` maps Firebase codes to human copy (data layer owns provider errors).
- **`api_training_repository.dart` (88 lines):** fetch + create sessions (accepts 200 or 201).
- **`api_dispute_repository.dart` (117 lines):** fetch/raise/respond; uses a shared `_send()` helper wrapping token + connection errors (98–116). Note lines 52–53 use Dart's null-aware element syntax `'detail': ?detail`.
- **`api_injury_repository.dart` (109 lines):** `saveInjury` chooses **POST (create) vs PUT (update) by `record.id == null`** (lines 42–61); delete expects 204.
- **`api_eligibility_history_repository.dart` (62 lines):** plain GET; the server already scoped access and shaped `changedBy`.
- **`api_session_confirmation_repository.dart` (105 lines):** GET by player; POST sends only `{sessionId, status}` — **the player is derived from the token server-side** (line 54–56 comment).
- **`api_device_repository.dart` (79 lines):** the FCM token source is an injected function (`PushTokenProvider`, line 12) so the plugin stays out of this layer; `registerCurrentDevice` swallows every failure — **push must never break login** (lines 40–55).

## 2.6 Data layer — offline-first attendance ⭐ (defense highlight)

### `lib/data/local/attendance_outbox.dart` (135 lines)
**Purpose:** a durable sqflite queue of roll-call saves that failed offline.
- Lines 9–23: `OutboxBatch` — the whole session batch is the retry unit (saves are wholesale-replace, so re-sending is always safe).
- Lines 51–60: single table `outbox_attendance` (records stored as JSON, with `retry_count` and `last_error`).
- Lines 68–76 `enqueue`; 81–86 `pendingBatches` (**oldest first — so the newest save for a session lands last and wins**); 89–99 `latestBatchForSession` (offline read fallback); 102–115 `markSynced` (delete) / `markFailed` (increment + record error).
- Constructor takes an injectable `DatabaseFactory` + path so tests run on an in-memory DB.

### `lib/data/repositories/offline_first_attendance_repository.dart` (54 lines)
**Purpose:** a **decorator** around the live repository.
- Lines 22–34: `saveSessionAttendance` — try live; **on `AttendanceNetworkException` only** → enqueue the batch and report the marks as saved (optimistic). A 4xx validation error still propagates — the coach can fix that; retrying it forever cannot succeed.
- Lines 37–47: `fetchAttendanceForSession` — on failure, show the last queued batch instead of an empty roll call.
- Line 50–53: player history reads stay live (offline scope is capture only).

### `lib/data/local/attendance_sync_service.dart` (97 lines)
**Purpose:** drains the outbox when connectivity returns.
- Lines 41–53: `start()` — subscribes to `connectivity_plus` changes and kicks one immediate drain (pre-restart work syncs without waiting).
- Lines 57–82: `drain()` — replay batches sequentially; **network failure → keep batch, stop, schedule retry; server rejection → record error then drop the batch** (replaying identical invalid payloads can never succeed).
- Lines 84–89: capped **exponential backoff** (5 s doubling to 5 min).

**Defense narrative:** "mark attendance in a gym with no signal → the save 'succeeds' into a sqflite outbox → when the phone regains connectivity the sync service replays batches oldest-first → the server's wholesale-replace endpoint makes the newest batch win → duplicates are impossible because of the DB's `unique_together (player, session)`."

## 2.7 Data layer — mock repositories

All mocks: in-memory lists + `Future.delayed` (~300–500 ms) so loading states are visible during UI work; instance (not static) state so each test gets a clean slate.

- `mock_auth_repository.dart` (69): accepts any email with password `demo123`, infers the role from the email ("coach@…" → COACH). **This is exactly why `useMockData` is forced off in release builds.**
- `mock_player_repository.dart` (202): 10-player squad (parody names) covering every UI edge: a GK with the GK six (p7), an unassigned rookie (p10), every eligibility state. `savePosition`/`saveAssessment` mutate in place so changes survive refetch.
- `mock_attendance_repository.dart` (114): seeded histories for p1/p2/p3; `saveSessionAttendance` does the same wholesale replace as the server (lines 98–102).
- `mock_training_repository.dart` (100): sessions at relative dates (`day(+2) … day(-8)`) so Upcoming/Past tabs always have content.
- `mock_dispute_repository.dart` (107), `mock_injury_repository.dart` (70), `mock_eligibility_history_repository.dart` (53), `mock_session_confirmation_repository.dart` (43), `mock_device_repository.dart` (7, no-op).

## 2.8 Presentation layer — providers (the ViewModels)

Common pattern: **`FutureProvider.autoDispose`** for reads (auto-refetch when the screen re-enters), **`AsyncNotifier` controllers owning only submit state** (field values stay in the screen as transient form state), and **`ref.invalidate(...)` after a successful write** so every open view refetches.

- `auth_controllers.dart` (117): `LoginState` (immutable) + `LoginController.signIn/sendResetEmail`; `_next()` (lines 74–88) documents the transition rules (busy flags reset, error clears, visibility toggle survives). `PasswordResetController` for the coach profile.
- `squad_providers.dart` (71): `squadProvider`; **`RosterFilter.apply` (lines 24–45) — the search + tier filter logic** (matches name, position code, or full position name); `filteredSquadProvider` = derived state recomputed automatically.
- `coach_overview_providers.dart` (108): ⭐ `TeamOverview` read-model — `readyPercent`, and `teamOverviewProvider` derives **alerts** from the squad: ineligible → critical, academic warning → warning, unassigned position → info, empty schedule → info. Pure derivation from two other providers — good MVVM example.
- `training_schedule_providers.dart` (68): `upcomingSessionsProvider` / `pastSessionsProvider` split + sort around today; `ScheduleSessionController.submit` invalidates the schedule on success.
- `attendance_log_providers.dart`: `kDefaultEffort = 70` (mid-range = "not yet judged"); `sessionAttendanceProvider` is `.family` per session; `AttendanceLogController.save` returns bool so the screen can pop.
- `guardian_dashboard_providers.dart` (70): `linkedPlayersProvider`, selected-child selection with first-child fallback, `childAttendanceProvider` family, and the **`AttendanceSummary` extension — `presentPercent` and `currentStreak`** (counts leading present records of the newest-first list — the streak flame's number).
- `session_confirmation_providers.dart`: ⭐ controller state is a **`Set<String>` of in-flight session ids** — so tapping Confirm spins only that card's button, not every card.
- `injury_providers.dart`, `dispute_providers.dart`, `edit_performance_controller.dart`, `player_position_controller.dart`, `eligibility_history_providers.dart`, `player_dashboard_providers.dart`: same submit-controller/family-read patterns.
- `error_text.dart`: `friendlyErrorMessage()` — a switch over the domain exception types; **raw exception text never reaches the user**, unknown errors get a screen-specific fallback.

## 2.9 Presentation layer — screens (Views)

All screens are "thin Views": render providers, forward intent, no data access.

- **`home_screen.dart`** — post-login **role router**: `switch (profile.role)` → Coach/Player/Guardian dashboard; unknown roles get a fallback page.
- **`login_screen.dart` (170)** — form UI only; on success **fire-and-forget device registration + starts the attendance sync service** (lines 108–111) before navigating.
- **`coach_dashboard_screen.dart` (317)** — Team Overview + Active Squad Roster; search bar, scrollable tier-filter chips (a chip row, not a segmented button, so a 4th tier still fits), compact-list vs FUT-card-grid toggle, pull-to-refresh, quick "mark attendance" that routes to the most recent open session.
- **`log_attendance_screen.dart` (947) ⭐ the biggest screen** — Attendance & Evaluation:
  - `_marks` map = transient form state; **unmarked ≠ absent** (null status is a real state).
  - `_seedOnce` preloads previously saved marks exactly once.
  - Effort slider / note field deliberately **don't** `setState` (lines 109–124) — rebuilding the roster per keystroke would fight the cursor.
  - `_finalize` (152–231): re-checks `isAttendanceOpen` (server enforces too), warns about unmarked players, **strips effort/notes from non-present players** (rebuilt, not `copyWith`, because copyWith can't clear fields), saves via the controller, pops on success.
  - `PopScope` + discard dialog protects unsaved marks; "Mark all present" bulk action; per-player link to the full assessment.
- **`edit_performance_data_screen.dart` (420)** — six 0–99 sliders + coach-notes field → drafts a `PlayerRatings` → `EditPerformanceController.submit` → pops with the updated `Player` so the profile card refreshes instantly.
- **`player_profile_screen.dart` (541)** — the coach's view of one player: FUT card, radar chart, position edit via picker sheet **with a confirm dialog naming old → new position** (one mis-tap in a ten-item list must not silently re-label a player), links to assessment, injuries (read-only), flag-dispute.
- **`player_dashboard_screen.dart` (267)** — the player's own card + `TierBadge`, **streak flame** instead of raw percentages, eligibility as youth-friendly copy ("Ready to Play! 🚀"), recent attendance, injury history entry.
- **`guardian_dashboard_screen.dart` (264)** — read-only mirror of the player dashboard for the selected linked child; injury history opened with `readOnly: true` (server enforces regardless).
- **`training_schedule_screen.dart` (219)** / **`schedule_session_screen.dart` (434)** — coach schedule with Upcoming/Past toggle; the form collects title/date/times/location/focus/tier chips (a `_TierSelectionHint` states in words who the session will reach) and submits a draft `TrainingSession`.
- **`schedule_tab_screen.dart` (168)** — the player/guardian schedule; upcoming cards carry the RSVP `SessionConfirmationButton`.
- **`injury_history_screen.dart` (352)** — list + add/edit bottom sheet + delete with confirm; the same screen serves player (CRUD) and coach/guardian (`readOnly`).
- **`dispute_list_screen.dart` (265)** / **`flag_dispute_screen.dart` (139)** — the coach's ticket list with a thread sheet (respond + optional status change) and the flag form.
- **`eligibility_history_screen.dart` (115)** — the read-only timeline; shows `changedBy` exactly as the server shaped it.
- **`attendance_history_screen.dart`**, **`progress_screen.dart`** (attendance records that carry coach notes = the feedback feed), **`profile_tab_screen.dart`**, **`coach_profile_screen.dart`** — detail/tab screens following the same patterns.

## 2.10 Presentation layer — theme & widgets

- **`theme/app_theme.dart` (148)** — the youth-facing design system: teal primary, coral accent, Fredoka display over Nunito body.
- **`widgets/player_card.dart` (351) ⭐** — the FUT card: an SVG frame with live values overlaid **in the frame's 600×850 coordinate space** so they line up at any size; `_StatsPanel` shows the outfield six or GK six by position.
- **`widgets/attribute_radar_chart.dart` (190)** — six-axis radar drawn with a **`CustomPainter`** (no chart package), animating outward on first show; axis order mirrors the card's stat columns.
- **`widgets/team_overview_card.dart` (224)** — ready-gauge + alert list from `TeamOverview`.
- **`widgets/streak_counter.dart` (150)** — progress ring + flame; ring turns gold at the goal; zero streak framed as an invitation.
- **`widgets/training_session_card.dart` (316)** — shared coach/player session card; role-specific bottom row (Log Attendance vs RSVP); single-tier sessions colour-coded by tier.
- **`widgets/position_picker_sheet.dart` (162)** — modal sheet grouped by line (keeper/defence/midfield/attack); returns the pick, caller confirms — selection alone is never destructive.
- **`widgets/tear_away_date.dart` (127)** — calendar-page date block; picks black/white text by **actual WCAG contrast**, not a lightness threshold.
- Small single-purpose widgets: `mini_player_card` (dense roster row), `attendance_status_chip`, `eligibility_badge`, `injury_status_chip`, `tier_badge`, `stat_tile`, `session_confirmation_button`, `dashboard_states` (shared error+retry), `coach_bottom_nav` / `portal_bottom_nav` (shared navs; tapping the active tab is a no-op).

## 2.11 Flutter tests (`footpath_cebu/test/`, 27 files)

- `models/*` — entity logic: tier bounds & `forAge`, `overall` vs `gkOverall`, wire round-trips, `isAttendanceOpen` window, position `fromWire` null behaviour.
- `data/attendance_outbox_test.dart` + `offline_first_attendance_repository_test.dart` — the offline queue: enqueue on network failure, drain order, drop-on-validation-error, read fallback (uses `sqflite_common_ffi` in-memory DB).
- `providers/*` — controller/provider behaviour with fake repositories via `ProviderContainer(overrides:)`: filters, team overview alerts, submit flows, invalidation.
- `screens/*` — widget tests per screen: role routing, roll-call marking/finalising, dispute flows, injury CRUD, read-only gating for guardians.
- `widgets/*` — card/chart/button rendering.
- `wiring_and_assessment_test.dart` — verifies the DI wiring and that the assessment carries coach notes end-to-end.

---

## 3. Feature → Files cheat sheet (for "which code makes X work?")

| Feature | Backend | Frontend |
|---|---|---|
| Login & roles | `accounts/authentication.py`, `accounts/views.py` (MeView) | `firebase_auth_repository.dart`, `auth_controllers.dart`, `login_screen.dart`, `home_screen.dart` |
| Squad roster & FUT cards | `academy/views.py` SquadListView, `PlayerSerializer` | `squad_providers.dart`, `coach_dashboard_screen.dart`, `player_card.dart` |
| Attendance roll call | `SessionAttendanceView` (replace + 2-day window) | `log_attendance_screen.dart`, `attendance_log_providers.dart` |
| Offline attendance | — (server just receives the replay) | `attendance_outbox.dart`, `offline_first_attendance_repository.dart`, `attendance_sync_service.dart` |
| Player assessment (6 ratings + notes) | `PlayerAssessmentView`, `AssessmentSerializer` | `edit_performance_data_screen.dart`, `edit_performance_controller.dart` |
| Position assignment | `PlayerPositionView` | `position_picker_sheet.dart`, `player_position_controller.dart`, `player_profile_screen.dart` |
| Training scheduling + push | `TrainingSessionListCreateView`, `notifications.py` | `schedule_session_screen.dart`, `training_schedule_providers.dart` |
| Player RSVP | `SessionConfirmationView` | `session_confirmation_button.dart`, `session_confirmation_providers.dart` |
| Guardian view (linked children only) | `GuardianLink`, `_guardian_may_read` | `guardian_dashboard_providers.dart`, `guardian_dashboard_screen.dart` |
| Injuries (least privilege) | `InjuryRecord*View` | `injury_history_screen.dart`, `injury_providers.dart` |
| Eligibility + audit trail + privacy | `signals.py`, `EligibilityHistoryView`, portal `staff_eligibility` | `eligibility_history_screen.dart` |
| Disputes (append-only thread) | `Dispute*View` | `dispute_list_screen.dart`, `flag_dispute_screen.dart` |
| Club registration & tenancy | `portal/` (all), `Club` model | — |
| Push notifications | `notifications.py`, `DeviceRegisterView` | `api_device_repository.dart` |
| Player photos | `storage.py`, `PlayerPhotoUploadView` | `photoUrl` on `Player`, avatar fallbacks |

## 4. Likely defense questions & where the answer lives

1. **"How do you stop a guardian reading another child's data?"** → `academy/views.py:69` `_guardian_may_read` + `GuardianLink` table; tested in `AttendanceAuthorizationTests`.
2. **"What if the phone is offline during roll call?"** → the outbox/decorator/sync trio (§2.6); last-write-wins by design.
3. **"Why doesn't the client decide the role?"** → role lives on the server `User` row; the app only reads `/api/auth/me/`; `UserProfile.isCoach` is documented as a UX gate only.
4. **"Why is tier stored instead of computed from age?"** → both `academy/models.py:49` and `age_tier.dart:55` document it: no mid-season birthday shifts.
5. **"How is the eligibility audit trail guaranteed?"** → model signals (`signals.py`) fire on every write path; history is append-only even in the admin.
6. **"Why can't mock login ship to production?"** → `providers.dart:74` — `kReleaseMode` forces live data (audit F1).
7. **"How do you prevent duplicate attendance?"** → DB `unique_together ('player','session')` + upsert + wholesale replace.
8. **"Multi-club isolation?"** → `User.club` single-sources tenancy; every queryset filters by it; `ClubIsolationTests` / `SessionTenancyTests` prove it.
