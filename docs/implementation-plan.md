# FootPath-Cebu — Implementation Plan (Gaps A–F) + Claude Code Prompt Guide

Completes the remaining feature gaps on top of the existing **Flutter → Django REST →
Supabase Postgres** architecture ([ADR 0001](decisions/0001-roles-source-of-truth.md),
unchanged). Preserves the domain/data/presentation layering, the RBAC/BOLA patterns in
`backend/academy/views.py` + `backend/accounts/permissions.py`, the **0–99 FUT-style
rating system as-is**, and keeps Admin/School-Staff work on `/admin/` + `backend/console/`
(no new Flutter screens for those two roles).

> For the narrower "get online + verify every screen without mock data" workflow, see the
> companion doc: [go-live-and-screen-verification-plan.md](go-live-and-screen-verification-plan.md).

**Context — why this work exists.** The app is feature-partial against
[REQUIREMENTS.md](REQUIREMENTS.md): the newest Coach attendance screen isn't wired to a
live endpoint, offline-first capture is unbuilt, and injury CRUD / dispute log / the two
extra push triggers don't exist yet. The backend RBAC foundation is solid and tested (46
backend + 55 Flutter tests). This plan closes the gaps without disturbing that foundation.

**Push dependency note (verify at implementation time):** as of planning,
`firebase_auth 6.5.6` and `firebase_messaging 16.4.3` both target
`firebase_core_platform_interface ^8.0.0` — the conflict documented in
`wiring-implementation-notes.md` appears resolved upstream, making the "unpin + add
messaging" path (Phase 5a) the recommended default. Re-verify with `flutter pub get`
before executing.

---

## Phase 0 — Backend: session-level attendance endpoint (unblocks A, B)

**Why first:** the Flutter screen and controller already assume `GET/POST` session-scoped
attendance exists; the offline queue (B) needs a stable request/response shape to enqueue
against, so it must follow this.

**Gap found:** `Attendance` (backend) has no `effort`/`note` fields, but the Flutter
`Attendance` entity and `log_attendance_screen.dart` already collect both, and the
serializer doesn't emit `sessionId`. These must be added to make the wire contract truthful.

- **`backend/academy/models.py`** — add `effort` (nullable `PositiveSmallIntegerField`),
  `note` (`CharField` blank, max 1000) to `Attendance`; add
  `unique_together = ('player', 'session')` (nothing prevents duplicate rows today, and
  the new upsert depends on this). New migration.
- **`backend/academy/serializers.py`** — `AttendanceSerializer` emits `sessionId`/`effort`/
  `note`; new `SessionAttendanceRecordSerializer` (write shape: `playerId`, `status`,
  `effort`, `note`, with `status` upper-cased + choice-validated).
- **`backend/academy/views.py`** — new `SessionAttendanceView`: `GET` (coach/admin) reads
  `Attendance.objects.filter(session_id=…)`; `POST` (coach only) upserts via
  `update_or_create` on `(player, session)`, sets `recorded_by=request.user`, and **prunes
  players no longer in the payload** inside a `transaction.atomic()` — "replace this
  session's attendance" semantics, matching `MockAttendanceRepository`. Follows the file's
  existing hand-rolled `APIView` + manual role-check style (not DRF generics).
- **`backend/academy/urls.py`** — `path('attendance/session/<int:session_id>/', …)`.
- **`backend/academy/admin.py`** — expose `effort`/`note` on `AttendanceAdmin`.
- **Tests** (`backend/academy/tests.py`, mirror `SquadEndpointTests` style):
  coach POST+GET round-trip with effort/note/sessionId; resubmit replaces not duplicates;
  non-coach POST → 403; exact wire-contract key set; invalid status / out-of-range effort
  rejected.

## Phase 1 — Flutter: wire the live attendance repository (A)

- **`footpath_cebu/lib/data/repositories/api_attendance_repository.dart`** — replace both
  `UnimplementedError` stubs with real HTTP calls, copying the `_requireIdToken()` +
  error-handling pattern already in `fetchAttendanceForPlayer`. `saveSessionAttendance`
  POSTs `{'records': records.map((r) => r.toJson())}` (existing `toJson()` already emits
  the needed keys). Throws `AttendanceRepositoryException` on non-2xx/network error.
- **No other Flutter changes** — `attendanceRepositoryProvider` already swaps this in for
  `useMockData == false`; the controller/screen call through use cases and are agnostic.
- **Tests** — extend `log_attendance_screen_test.dart` with provider overrides simulating
  200/403/500 so error banners are covered; add an HTTP-mock unit test only if
  `wiring_and_assessment_test.dart` already establishes that pattern (don't invent a new
  harness unilaterally — flag it in the PR if absent).

## Phase 2 — Offline-first attendance capture (B)

Depends on Phase 1 (needs a real request/response shape to queue against).

**Approach — `sqflite` (not drift/isar/hive):** the need is one outbox table + optional
read-through cache; drift/isar add a `build_runner` codegen step to a project that
currently has zero generated code (entities hand-write `fromJson`/`toJson`). `sqflite`
is the lowest-ceremony durable/transactional option; pair with `sqflite_common_ffi` for
the Windows desktop target. Add `connectivity_plus` for reconnect detection. `shared_preferences`/files
are rejected — the outbox needs atomic multi-row transactions + queryability.

**Layering — keep domain pure, keep `AttendanceRepository` unbroken (decorator pattern):**
- **`lib/data/local/attendance_outbox.dart`** — `AttendanceOutbox` over a sqflite table
  `outbox_attendance(id, session_id, records_json, created_at, retry_count, last_error)`;
  `enqueue/pendingBatches/markSynced/markFailed`. One row per save (whole batch = retry
  unit, matching wholesale-replace semantics).
- **`lib/data/repositories/offline_first_attendance_repository.dart`** — implements
  `AttendanceRepository`, wrapping the real `ApiAttendanceRepository` + the outbox.
  `saveSessionAttendance`: try inner; on a **network-style** failure, enqueue and return
  the records optimistically (screen still reports success + pops); on a **validation**
  failure, propagate without queuing (don't silently swallow a coach's fixable error).
  `fetchAttendanceForSession`: try live, else fall back to the latest un-synced queued
  batch. `fetchAttendanceForPlayer`: passthrough (offline requirement is capture only).
- **`lib/data/local/attendance_sync_service.dart`** — subscribes to
  `Connectivity().onConnectivityChanged`; on reconnect drains the outbox sequentially
  through the inner API repo with capped exponential backoff. Plain Dart (testable),
  instantiated in the composition layer (depends on a platform plugin, so not domain).
- **`lib/core/di/providers.dart`** — `attendanceOutboxProvider`; `attendanceRepositoryProvider`
  builds `OfflineFirstAttendanceRepository(inner: ApiAttendanceRepository(), outbox: …)`
  when live; `attendanceSyncServiceProvider` `ref.watch`'d once post-login (same spot as
  the existing `registerDeviceProvider` call).
- **Conflict strategy:** last-write-wins at batch level (the server `update_or_create`
  already does this); sequential drain means later batch wins. Multi-device same-session
  editing is explicitly out of scope.
- **UI:** `log_attendance_screen.dart` snackbar distinguishes "Attendance saved." (synced)
  from "Saved — will sync when you're back online." (queued), via a sibling
  `attendanceSyncStatusProvider` — **no change to the domain interface signature.**
- **Tests** — `test/data/attendance_outbox_test.dart` (init `sqflite_common_ffi` in
  `setUpAll`), `test/data/offline_first_attendance_repository_test.dart` (network failure →
  queued + success returned; validation failure → NOT queued + propagates).

## Phase 3 — Injury history CRUD, Player (C)

- **Backend** — `InjuryStatus` choices + `InjuryRecord` model (player FK, description,
  body_part, status, occurred_on, resolved_on, notes, timestamps) + migration;
  `InjuryRecordSerializer` (camelCase); `InjuryRecordListCreateView` +
  `InjuryRecordDetailView` (player CRUDs **own only**, `player=request.user` forced on
  create; coach/admin **read-only** across all; guardian **denied** — medical data,
  least-privilege, flagged as a judgment call); routes `injuries/`, `injuries/<pk>/`;
  `InjuryRecordAdmin`. Tests: ownership enforcement, coach read-only, guardian denial,
  wire contract.
- **Flutter — mirror the attendance template exactly:** `domain/entities/injury_record.dart`,
  `domain/repositories/injury_repository.dart` (`InjuryReader`/`InjuryWriter` split),
  `data/repositories/mock_injury_repository.dart` + `api_injury_repository.dart`,
  use cases `get_injuries.dart` / `save_injury.dart` (single upsert, matching
  `save_player_assessment.dart` precedent) / `delete_injury.dart`, providers in
  `core/di/providers.dart` + `presentation/providers/injury_providers.dart`
  (`injuriesProvider` family + `InjuryFormController`).
- **Screen** `presentation/screens/injury_history_screen.dart` — player list + add/edit/
  delete; `readOnly` flag for the coach view (UX only; server enforces). Entry points:
  `player_dashboard_screen.dart` (wire the existing inert "Injury History" placeholder
  card's `onTap`) and `player_profile_screen.dart` (coach, read-only, below Technical
  Performance).
- **Tests** — `test/models/injury_record_test.dart`, `test/providers/injury_providers_test.dart`,
  `test/screens/injury_history_screen_test.dart`.

## Phase 4 — Dispute / audit-log foundation (D)

Backend-complete; **Coach-side Flutter UI only** (flag + respond). Admin/School-Staff
participate via `/admin/` + `/console/` per the project decision.

**Scope call:** one `Dispute` (flag + status lifecycle) + append-only `DisputeResponse`
thread — *not* a generic every-model-change audit log (that's a distinct, larger feature).
The requirement's wording ("foundation… Coach flag/respond, School Staff participation,
Admin review") maps exactly onto a status-ticket-with-thread. `DisputeResponse` *is* the
audit trail for a dispute (append-only, no update/delete endpoints).

- **Backend** — `DisputeCategory`/`DisputeStatus` choices; `Dispute` (raised_by,
  subject_player nullable, category, status, summary, detail, timestamps);
  `DisputeResponse` (dispute FK, author, body, status_change_to nullable, created_at) +
  migration. Serializers (read + create for both). `DisputeListCreateView` (GET:
  coach/school_staff/admin see all; POST: coach only, `raised_by` forced),
  `DisputeDetailView`, `DisputeResponseCreateView` (coach/school_staff/admin, `author`
  forced, applies `status_change_to` to parent). Routes `disputes/`, `disputes/<pk>/`,
  `disputes/<pk>/responses/`. `DisputeAdmin` with `DisputeResponse` as a `TabularInline`
  (satisfies "Admin review" in one screen). Console: a Disputes panel in
  `console/static/console/app.js` + template (using existing `apiFetch`/`textCell`/
  `createElement` conventions, never `innerHTML` with server data). Tests: coach create;
  player/guardian denied; school_staff/admin list+respond; status transition via response;
  wire contract.
- **Flutter (Coach-only)** — `domain/entities/dispute.dart`, `dispute_repository.dart`,
  mock+api repos, use cases `get_disputes.dart`/`raise_dispute.dart`/`respond_to_dispute.dart`,
  `presentation/providers/dispute_providers.dart`. Screens
  `flag_dispute_screen.dart` (reachable from `player_profile_screen.dart` app bar) and
  `dispute_list_screen.dart` (reachable from a new "Disputes" section on
  `coach_profile_screen.dart`, matching its `Card(ListTile(...))` idiom). Tests mirror the
  injury shapes.

## Phase 5 — Push notifications (E)

Two independent sub-tracks. 5b (new triggers) works today even with zero devices (no-op).

**5a — unblock the on-device token (recommended path, re-verify pub.dev first):**
1. `pubspec.yaml`: `firebase_auth: 6.5.4` → `^6.5.6` (or unpin), add `firebase_messaging: ^16.4.3`.
2. `flutter pub get`; inspect `pubspec.lock` for `firebase_core_platform_interface`/
   `firebase_core` landing on `^8.0.0`/`^4.12.x` with no conflict. If a conflict remains,
   **revert** and keep the no-op default (documented fallback) — don't force resolution.
3. Run full `flutter test` (highest-risk step — auth moved versions).
4. **`lib/core/di/providers.dart`** — wire the real token provider into
   `deviceRepositoryProvider` (`FirebaseMessaging.instance.requestPermission()` +
   `getToken()`), exactly as the comment in `api_device_repository.dart` already spells
   out. No change to `ApiDeviceRepository`.

**5b — new backend triggers** (`backend/academy/notifications.py`, same best-effort/
dead-token-pruning shape as `notify_session_scheduled`):
- `notify_assessment_saved(profile)` → player + linked guardians; hooked into
  `PlayerAssessmentView.put` via `transaction.on_commit`. **Fires on the six-attribute
  assessment save, not per-session attendance** (20 players = 20 pushes would be spam).
- `notify_eligibility_changed(profile, previous)` → player + guardians, via a
  **pre_save/post_save signal** in new `backend/academy/signals.py` (registered in
  `AcademyConfig.ready()`), so it fires no matter the write path (admin site / console /
  future API), not just a single view. No-op transitions (same value) don't fire.
- Tests: mock `messaging.send_each_for_multicast`; assert correct recipients after an
  assessment PUT and after an ORM eligibility change; assert unchanged-value save does
  NOT fire.

## Phase 6 — Go-live + no-mock verification (F)

Expands `wiring-implementation-notes.md`'s existing sections to cover everything built
above, using the existing `useMockData` seam (`--dart-define=USE_MOCK=false`; automatic in
`kReleaseMode`). Full step-by-step lives in
[go-live-and-screen-verification-plan.md](go-live-and-screen-verification-plan.md); the
additions here are:
- Seed `seed_academy.py` with 1–2 injuries + one dispute+response (idempotent
  `update_or_create` style) so new screens have live demo data on first login.
- Automated gate: backend `manage.py test` (46 + new) + `check --deploy`; Flutter
  `analyze` + `test` (55 + new). If 5a's version bump was taken, this is the primary
  auth-regression signal — stop-ship on any new failure.
- Manual live walkthrough per role (Coach: assessment→push, schedule→push, roll-call
  round-trip, **offline-capture→reconnect-sync**, injury read, dispute flag/respond;
  Player: injury CRUD persists; Guardian: linked read + **403 BOLA negative test**;
  Console/Admin smoke of new models; Push end-to-end if 5a landed).
- Update `wiring-implementation-notes.md` with a new dated "what shipped" section.

---

## Prompt Guide — copy-paste prompts for Claude Code

One prompt per phase, sized to be independently reviewable. Run in order; each assumes the
prior diffs are present (later phases depend on earlier endpoints/entities). Replace
`<this plan>` with `docs/implementation-plan.md`.

### Prompt 1 — Phase 0 (backend session attendance)
```
Implement session-level attendance endpoints in the Django `academy` app, per <this plan>
Phase 0:
1. Add `effort` (nullable PositiveSmallIntegerField) and `note` (blank CharField, max 1000)
   to Attendance in backend/academy/models.py, plus unique_together=('player','session')
   on Meta. Generate the migration.
2. Update AttendanceSerializer to emit sessionId/effort/note; add SessionAttendanceRecordSerializer
   for the write side (playerId, status, effort, note).
3. Add SessionAttendanceView (GET coach/admin, POST coach-only) wired at
   attendance/session/<int:session_id>/ in urls.py. POST upserts via update_or_create on
   (player, session), sets recorded_by=request.user, and deletes rows for players no longer
   in the payload (replace-this-session semantics). Follow the existing hand-rolled APIView
   + manual role-check style (see SquadListView, TrainingSessionListCreateView), not DRF
   generics.
4. Expose effort/note on AttendanceAdmin.
5. Add tests to backend/academy/tests.py mirroring the existing style: coach GET/POST;
   resubmit replaces not duplicates; non-coach POST → 403; wire-contract key set; invalid
   status / out-of-range effort rejected.
Run `python manage.py test` from backend/ and confirm the pre-existing 46 still pass.
```

### Prompt 2 — Phase 1 (Flutter attendance wiring)
```
Wire footpath_cebu/lib/data/repositories/api_attendance_repository.dart to the live
GET/POST /api/attendance/session/<id>/ endpoints. Replace both UnimplementedError stubs
following the exact pattern already in fetchAttendanceForPlayer (Firebase ID-token bearer,
AttendanceRepositoryException on failure, Attendance.fromJson/toJson). Do NOT change the
interface, use cases, providers, or log_attendance_screen.dart — contain it to this one
file. Then check whether test/wiring_and_assessment_test.dart already mocks http.Client for
an Api*Repository; if so add success/failure tests for the two new methods, otherwise don't
invent a harness — confirm existing attendance tests still pass and tell me. Run
`flutter analyze` and `flutter test`.
```

### Prompt 3 — Phase 2 (offline-first capture)
```
Implement offline-first attendance capture per <this plan> Phase 2. Add sqflite (+
sqflite_common_ffi dev dep) and connectivity_plus to pubspec.yaml. Create:
- lib/data/local/attendance_outbox.dart (sqflite table outbox_attendance: id, session_id,
  records_json, created_at, retry_count, last_error; enqueue/pendingBatches/markSynced/markFailed)
- lib/data/repositories/offline_first_attendance_repository.dart implementing
  AttendanceRepository as a decorator over inner ApiAttendanceRepository + the outbox:
  saveSessionAttendance tries inner, queues on network failure (returns optimistically),
  propagates validation failures WITHOUT queuing; fetchAttendanceForSession falls back to
  the latest un-synced queued batch on failure; fetchAttendanceForPlayer passes through.
- lib/data/local/attendance_sync_service.dart listening to onConnectivityChanged, draining
  the outbox sequentially through the inner repo with capped backoff.
Wire into lib/core/di/providers.dart (attendanceRepositoryProvider builds the decorator when
live; add attendanceSyncServiceProvider, start once post-login like registerDeviceProvider).
Do NOT change the AttendanceRepository interface or any existing consumer. Add
test/data/attendance_outbox_test.dart and test/data/offline_first_attendance_repository_test.dart
(network failure → queued+success; validation failure → not queued). Init sqflite_common_ffi
in setUpAll. Run `flutter analyze` and `flutter test`.
```

### Prompt 4 — Phase 3 (injury history CRUD)
```
Implement Player injury history CRUD per <this plan> Phase 3.
Backend: InjuryStatus choices + InjuryRecord model (player FK, description, body_part,
status, occurred_on, resolved_on, notes, timestamps) + migration; InjuryRecordSerializer
(camelCase: id, playerId, description, bodyPart, status, occurredOn, resolvedOn, notes,
createdAt, updatedAt); InjuryRecordListCreateView + InjuryRecordDetailView (player CRUDs own
only, player=request.user forced on create; coach/admin read-only all; guardian denied) at
injuries/ and injuries/<pk>/; InjuryRecordAdmin; tests for ownership, coach read-only,
guardian denial, wire contract.
Flutter (mirror the attendance stack exactly): domain/entities/injury_record.dart,
domain/repositories/injury_repository.dart (InjuryReader/InjuryWriter split), mock + api
repos, use cases get_injuries/save_injury/delete_injury, injuryRepositoryProvider + use-case
providers in core/di/providers.dart, presentation/providers/injury_providers.dart
(injuriesProvider family + InjuryFormController), and
presentation/screens/injury_history_screen.dart (player add/edit/delete; readOnly flag for
coach). Wire entry points: the inert "Injury History" card in player_dashboard_screen.dart
(give it onTap) and a read-only entry in player_profile_screen.dart. Add
test/models/injury_record_test.dart, test/providers/injury_providers_test.dart,
test/screens/injury_history_screen_test.dart. Run backend + Flutter test suites.
```

### Prompt 5 — Phase 4 (dispute / audit-log foundation)
```//
Implement the dispute/audit-log foundation per <this plan> Phase 4 — backend-complete with
Coach-only Flutter UI (Admin/School-Staff use /admin/ and backend/console/).
Backend: DisputeCategory/DisputeStatus choices; Dispute (raised_by, subject_player nullable,
category, status, summary, detail, timestamps) + DisputeResponse (dispute FK, author, body,
status_change_to nullable, created_at) + migration; read+create serializers for both;
DisputeListCreateView (GET coach/school_staff/admin all; POST coach-only, raised_by forced),
DisputeDetailView, DisputeResponseCreateView (coach/school_staff/admin, author forced,
applies status_change_to) at disputes/, disputes/<pk>/, disputes/<pk>/responses/;
DisputeAdmin with DisputeResponse TabularInline; a Disputes panel in
console/static/console/app.js + template (existing apiFetch/textCell/createElement
conventions, never innerHTML with server data); tests (coach create; player/guardian denied;
staff list+respond; status transition; wire contract).
Flutter (Coach-only): domain/entities/dispute.dart, dispute_repository.dart, mock+api repos,
use cases get_disputes/raise_dispute/respond_to_dispute, dispute_providers.dart, screens
flag_dispute_screen.dart (from player_profile_screen.dart app bar) and dispute_list_screen.dart
(from a new "Disputes" section on coach_profile_screen.dart). Tests mirror the injury shapes.
Run backend + Flutter test suites.
```

### Prompt 6 — Phase 5a (unblock push token)
```
Attempt to unblock on-device FCM push per <this plan> Phase 5a. In pubspec.yaml change
firebase_auth 6.5.4 → ^6.5.6 (or unpin) and add firebase_messaging: ^16.4.3. Run
`flutter pub get` and show the resolved firebase_core / firebase_core_platform_interface
in pubspec.lock — confirm no conflict before proceeding. If clean: wire the real token
provider into deviceRepositoryProvider in lib/core/di/providers.dart exactly as the comment
in lib/data/repositories/api_device_repository.dart describes (requestPermission() +
getToken()); do NOT modify ApiDeviceRepository. Run the full flutter test suite and fix any
auth regressions. If a genuine conflict remains, revert the pubspec change and report back —
do not force resolution; we keep the no-op default per the documented fallback.
```

### Prompt 7 — Phase 5b (backend push triggers)
```
Add two push triggers per <this plan> Phase 5, following the best-effort/dead-token-pruning
pattern of notify_session_scheduled in backend/academy/notifications.py.
1. notify_assessment_saved(profile) → assessed player + linked guardians; hook into
   PlayerAssessmentView.put via transaction.on_commit.
2. notify_eligibility_changed(profile, previous) → player + guardians when
   PlayerProfile.eligibility actually changes; implement via pre_save/post_save signals in a
   new backend/academy/signals.py (stash previous in pre_save, compare + fire in post_save
   via transaction.on_commit), registered in AcademyConfig.ready() — must fire regardless of
   write path (admin/console/API).
Tests: mock messaging.send_each_for_multicast; assert recipients after an assessment PUT;
assert an ORM eligibility change fires and an unchanged-value save does NOT. Run
`python manage.py test`.
```

### Prompt 8 — Phase 6 (go-live prep + docs)
```
Prepare for go-live + no-mock verification per <this plan> Phase 6. Do NOT create the
Supabase project or run the manual device walkthrough (needs my credentials/hands-on).
Instead: (1) extend backend/academy/management/commands/seed_academy.py to also seed 1-2
InjuryRecords for a roster player and one Dispute+DisputeResponse, idempotent update_or_create
style; (2) run backend `python manage.py test` + `check --deploy` and Flutter
`flutter analyze && flutter test`, report pass counts; (3) update
docs/wiring-implementation-notes.md with a new dated section summarizing what shipped
(session attendance, offline capture, injury CRUD, dispute foundation, push outcome); (4)
produce the Phase 6.3/6.4 manual checklist as runnable Markdown referencing the seeded
accounts/screens. Don't touch Supabase/Firebase settings or .env, and don't run the app
against a live backend.
```

---

## Critical files
- `backend/academy/models.py` — every new/changed model; the migration chain starts here.
- `backend/academy/views.py` — the RBAC/BOLA pattern every new view must match.
- `footpath_cebu/lib/data/repositories/api_attendance_repository.dart` — the two
  `UnimplementedError` stubs (Gap A) and the template every new `Api*Repository` mirrors.
- `footpath_cebu/lib/core/di/providers.dart` — the single composition root for mock/live/
  offline wiring, all new providers, and the push-token provider.
- `docs/wiring-implementation-notes.md` — the go-live/verification playbook Phase 6 extends.
