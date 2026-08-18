# FootPath — 2-Week Execution Plan (Adviser Scope, Django-Aligned)
**Scope authority:** adviser-issued feature list (supersedes prior internal drafts) · **Team:** 3 devs · **Stack:** Django REST Framework + PostgreSQL · Firebase Auth (Admin SDK verification) · FCM · Flutter MVVM (Provider + get_it) · Django Templates (Admin + School Staff web portals) · **Ship date:** Day 10 code freeze

> **Architecture update (August 2026):** Account/Club provisioning in this
> historical plan is superseded by
> [Account and Club Hierarchy](ACCOUNT-AND-CLUB-HIERARCHY.md). Super Admin
> creates Clubs and their Coordinators; the Coordinator normally creates
> members only in their own Club. That document's School/Independent behavior
> and grade-free eligibility boundary are authoritative.

**Team split:**
- **Member A** — Django backend: models, API endpoints, RBAC middleware, Firebase integration
- **Member B** — Flutter mobile (Coach, Player, Guardian) + Django Templates portals (Admin, School Staff)
- **Member C** — QA, testing infra (pytest-django, flutter_test), CI/CD (GitHub Actions), OWASP ZAP, demo data

**Adviser scope, restated as the build list (nothing more, nothing less):**
- RBAC across 6 roles: **Super Admin, Club Coordinator, Coach, Player, Guardian, School Staff** — hierarchical account provisioning, no public self-registration; Firebase-authenticated mobile login with provisioned credentials
- **Super Admin:** create/manage Clubs, choose School or Independent type, assign each Club's single Coordinator, and configure age-tier settings; 3 tiers (Foundation 10–12, Development 13–15, Pathway 16–18)
- **Club Coordinator:** provision Coach, Player, Guardian, and—only for School Clubs—School Staff accounts inside their own active Club
- **Coach:** schedule CRUD; offline-first attendance (Present/Absent/Excused) with auto-sync; **1–10 standardized rubric** ratings (position-aware + goalkeeper variants); qualitative feedback; view player profiles + performance trends
- **Player:** view own profile / schedule / attendance / feedback+ratings / match performance stats / eligibility status; **injury history CRUD** (the one player-write feature)
- **School Staff:** update eligibility status ∈ {ELIGIBLE, NOT_ELIGIBLE, PENDING, ACADEMIC_WARNING} with no grade entry/exposure; view eligibility status history of linked players
- **Guardian:** own credentials, linked to ≥1 players; read-only view of child's profile, attendance, ratings, schedule, eligibility status
- **System:** push notifications to Player + Guardian for schedule, feedback, and eligibility updates
- **Dispute/audit log foundation:** Coach flag/respond → School Staff participation → Admin review

---

## 0. Ground Rules (read once, enforce daily)

1. **Django is the single source of truth.** Firebase handles identity only (Auth tokens, FCM delivery). All data lives in PostgreSQL; all authorization happens in DRF permission classes. Flutter and the portals render — they never enforce.
2. **DIP is the schedule.** Member A freezes the Flutter `domain/` package (entities + repository interfaces) Day 1 EOD with B; the **OpenAPI contract freezes Day 5 EOD**. Member B builds every screen against `MockXRepository` implementations until real HTTP repos swap in via `get_it` — one line per repository.
3. **Data minimization is structural.** Eligibility is a status enum with an auditable history of transitions. No grade column, no grade field in any serializer, no free-text field on eligibility records. Grades never enter the system by construction (RA 10173-aligned).
4. **One writer per resource.** Each endpoint has exactly one role permitted to write, expressed as one permission class — the whole permission matrix stays auditable in one file. The single exception the adviser scope introduces: **Players write their own injury records.**

---

## 1. COMPREHENSIVE WORKFLOW ARCHITECTURE

### 1.0 Data Topology (PostgreSQL via Django ORM)

```
User              → firebase_uid (unique, indexed), role ENUM, is_active
                    role ∈ {ADMIN, COACH, PLAYER, GUARDIAN, SCHOOL_STAFF}
AgeTierConfig     → tier ENUM {FOUNDATION, DEVELOPMENT, PATHWAY},
                    min_age, max_age (Admin-configurable; seeded 10–12 / 13–15 / 16–18)
PlayerProfile     → user OneToOne, position, age_tier FK(AgeTierConfig), club FK
GuardianLink      → guardian FK, player FK, created_by FK, created_at
                    (M:N through-table; multiple guardians ↔ multiple players)
Club              → name, province
Schedule          → club FK, coach FK, starts_at, location, session_type
AttendanceMark    → schedule FK, player FK, status ENUM {PRESENT, ABSENT, EXCUSED},
                    marked_by FK, device_ts, server_ts, client_uuid (unique) ← idempotency
Rating            → player FK, coach FK, rubric_variant ENUM {OUTFIELD, GK},
                    scores JSONB (attribute → int 1–10, validated per variant),
                    qualitative_feedback TEXT, schedule FK, created_at
MatchStat         → player FK, schedule FK (session_type=MATCH), coach FK,
                    stats JSONB (goals, assists, minutes, ...), created_at
InjuryRecord      → player FK (owner), title, body_area, occurred_on,
                    recovered_on NULL, notes, created_at, updated_at
Eligibility       → player OneToOne, status ENUM {ELIGIBLE, NOT_ELIGIBLE,
                    PENDING, ACADEMIC_WARNING}, updated_by FK, updated_at
                    ← NO grade fields, ever
EligibilityHistory→ player FK, from_status, to_status, changed_by FK, changed_at
                    ← Staff-viewable per adviser spec; stores transitions, NO reasons
Dispute           → subject (GenericFK: AttendanceMark | Rating), status ENUM
                    {OPEN, RESPONDED, RESOLVED}, opened_by FK
DisputeEvent      → dispute FK, actor FK, actor_role, event_type, note, created_at
                    (append-only: no update/delete route exists)
FcmDevice         → user FK, token, platform, last_seen
```

**Writer map (one role per table — the audit spine):**

| Table | Sole writer (DRF permission) | Readers |
|---|---|---|
| User, PlayerProfile, GuardianLink, AgeTierConfig | `IsAdmin` | role-scoped |
| Schedule | `IsCoachOfClub` | Coach, Player(club), linked Guardian, Staff |
| AttendanceMark | `IsCoachOfSession` | Coach, Player(self), linked Guardian, Staff |
| Rating (scores + qualitative feedback) | `IsCoachOfPlayer` | Coach, Player(self), linked Guardian |
| MatchStat | `IsCoachOfPlayer` | Coach, Player(self), linked Guardian |
| **InjuryRecord** | **`IsOwnerPlayer` (full CRUD)** | Player(self), Coach(club, read), linked Guardian(read) |
| Eligibility | `IsSchoolStaffOfPlayer` (status field only) | all roles (enum only); History readable by Staff |
| Dispute/DisputeEvent | service layer, role-gated actions | participants + Admin |

---

### 1.1 Account Provisioning & Linking (Coordinator → Player + Guardian)

**Principle:** No public self-registration means clients never call Firebase's signup APIs. The authenticated Club Coordinator portal calls a Django service that derives the Club from the coordinator, uses the **Firebase Admin SDK server-side** to create the identity, and persists the domain record in PostgreSQL—with compensation so a DB failure never leaves an orphaned Firebase identity. Super Admin separately creates Clubs and their single Coordinators.

```
┌─ ADMIN WEB PORTAL (Django Templates, Member B) ────────────────────────┐
│ ProvisionUserForm → POST /portal/admin/users/create                    │
│ (session auth + IsAdmin + CSRF)                                        │
└────────────────────────────────┬───────────────────────────────────────┘
┌─ DJANGO SERVICE: provisioning.create_user() ▼ ─────────────────────────┐
│ 1. Guard: request.user.role == ADMIN                                   │
│ 2. firebase_admin.auth.create_user(email, temp_password)               │
│ 3. firebase_admin.auth.set_custom_user_claims(uid, {"role": "PLAYER"}) │
│    ← claim = client-side routing hint only; the DB role is authority   │
│ 4. atomic():                                                           │
│      User.objects.create(firebase_uid=uid, role=PLAYER)                │
│      PlayerProfile.objects.create(user=u, age_tier=tier, club=club)    │
│      Eligibility.objects.create(player=p, status=PENDING)  ← default   │
│    On DB failure → compensate: firebase_admin.auth.delete_user(uid)    │
│ 5. Firebase password-reset email sent; temp password never shown,      │
│    logged, or stored ("Admin-issued credentials" per spec)             │
└────────────────────────────────┬───────────────────────────────────────┘
                                 │ repeat with role=GUARDIAN
┌─ DJANGO SERVICE: provisioning.link_guardian() ▼ ───────────────────────┐
│ 1. IsAdmin guard                                                       │
│ 2. Validate roles: guardian.role==GUARDIAN, player.role==PLAYER        │
│ 3. GuardianLink.objects.get_or_create(guardian, player,                │
│      defaults={created_by: admin})   ← idempotent via unique_together  │
│    One guardian ↔ many players; one player ↔ many guardians (M:N)      │
└─────────────────────────────────────────────────────────────────────────┘
```

**Admin "assign and manage role-based permissions" (per spec):** role is a `User` field changeable only through an Admin portal action that (a) updates the DB row, (b) re-stamps the Firebase custom claim, (c) bumps a `claims_version` so the app forces a token refresh. Because DRF reads the **DB role**, a demotion takes effect on the very next API call — no stale-claim window.

**Admin "configure age-tier settings" (per spec):** `AgeTierConfig` rows are Admin-editable (min/max ages), seeded with the three DepEd-aligned tiers. Player tier assignment references the config, so a boundary tweak is a data change, not a migration.

**Auth handoff on every subsequent request (the Firebase↔Django seam):**

```
Flutter/Portal → Firebase sign-in → ID token (JWT)
Client → Django with Authorization: Bearer <idToken>
Django FirebaseAuthentication:
  1. firebase_admin.auth.verify_id_token(token)  ← signature/expiry/audience
  2. User.objects.get(firebase_uid=uid, is_active=True)
  3. request.user = local User → permissions read User.role from the DB
     (deactivating a user in Django kills access instantly)
```

---

### 1.2 Offline-to-Online Attendance Lifecycle (local sync queue, auto-sync)

**Principle:** the offline layer is the app's own local queue (Drift/sqflite). Writes commit locally and instantly; a connectivity-triggered sync worker drains the queue automatically ("syncs automatically once connectivity returns," per spec). `client_uuid` makes replays idempotent; `device_ts` gives deterministic last-write-wins.

```
T0  (pitch, zero connectivity)
│  Coach taps PRESENT for player X
│  AttendanceViewModel.mark(...) → IAttendanceRepository.mark(...)  ← MVVM boundary
│     └─ OfflineFirstAttendanceRepository:
│        1. UPSERT local row (local DB = the UI's read model)
│        2. Enqueue SyncOp { client_uuid, payload, device_ts }
│  UI re-renders instantly from the local stream; "pending" cloud icon shows
│  (pending == op exists in sync_queue).
│
T1  (still offline — corrections)
│  ABSENT→EXCUSED on the same player: local row updated; the queued op for
│  (schedule, player) is REPLACED, not appended → only final state ships.
│  Safe because exactly one coach owns a session (single-writer rule).
│
T2  (connectivity returns — automatic, no user action)
│  connectivity_plus wakes SyncWorker → drains queue FIFO:
│    POST /api/v1/attendance/marks/bulk-sync/   (Bearer <fresh ID token>)
│  DJANGO evaluates NOW, not at T0:
│    - middleware verifies token → request.user
│    - IsCoachOfSession: schedule.coach_id == request.user.id
│    - serializer: status ∈ {PRESENT, ABSENT, EXCUSED};
│      marked_by set server-side from request.user (client value ignored)
│    - idempotency: duplicate client_uuid → 200 no-op
│    - last-write-wins: incoming.device_ts < existing.device_ts → skip
│  2xx → op dequeued → pending icon clears.
│  4xx → op moved to a visible dead-letter (surfaced to the coach);
│  never silently dropped, never retried forever.
│
T3  (server side, on_commit)
│  For each mark CHANGED to ABSENT:
│    guardians = GuardianLink.objects.filter(player=p)
│    FCM multicast to their FcmDevice tokens:
│    "Alex was marked absent from U-14 training (4:00 PM)."
│    Payload: IDs + status only (data minimization at the push layer).
└─ Guardian push → deep-link lands on the correct child in the
   multi-child dashboard.
```

**Audit posture:** a tampered queue still hits DRF permissions at T2 — a coach cannot sync sessions they don't own, cannot spoof `marked_by`, cannot inject out-of-enum statuses. The client is believed temporarily on its own screen, never trusted by the server.

---

### 1.3 Academic Eligibility Gating & Alerts (4-state, status-only, grade-free)

**Principle:** School Staff performs the grade→status judgment in their own records outside FootPath; the system receives only the verdict. There is no grade column to secure because none exists — and the single-writable-field serializer makes adding one a validation error.

```
┌─ SCHOOL STAFF PORTAL (Django Templates, Member B) ─────────────────────┐
│ EligibilityRosterView — linked players of this staff member's school   │
│ Row action → POST /portal/staff/eligibility/<player_id>/               │
│   { status: ACADEMIC_WARNING }                                         │
│ History tab per player: renders EligibilityHistory (per adviser spec)  │
└────────────────────────────────┬───────────────────────────────────────┘
┌─ DJANGO: EligibilityService.set_status() ▼ ────────────────────────────┐
│ 1. IsSchoolStaffOfPlayer (staff ↔ school ↔ player scoping)             │
│ 2. Serializer accepts EXACTLY ONE writable field:                      │
│    status ∈ {ELIGIBLE, NOT_ELIGIBLE, PENDING, ACADEMIC_WARNING}        │
│    Any extra key ("grade": 88) → 400. Structural, not policy.          │
│ 3. atomic():                                                           │
│      No-op guard: unchanged status → return (idempotent, no push spam) │
│      Eligibility.status = new; updated_by = request.user               │
│      EligibilityHistory.create(from, to, changed_by, changed_at)       │
│        ← transitions are auditable & staff-viewable; REASONS are       │
│          deliberately never stored (no free-text = no grade leakage)   │
│ 4. on_commit → NotificationService.eligibility_changed(player)         │
└────────────────────────────────┬───────────────────────────────────────┘
┌─ NOTIFICATION FAN-OUT ▼ ───────────────────────────────────────────────┐
│ Recipients: player + all linked guardians (per spec)                   │
│ FCM payload: { player_id, new_status }, NEUTRAL copy                   │
│ ("Eligibility status updated.") — detail renders inside the authed     │
│ app, never on a semi-public lock screen.                               │
└────────────────────────────────┬───────────────────────────────────────┘
┌─ DASHBOARDS ▼ ─────────────────────────────────────────────────────────┐
│ Player & Guardian views show the status badge (enum only, no grades).  │
│ ACADEMIC_WARNING renders as a distinct amber state — early-warning UX  │
│ without any academic detail. Coach matchday screens grey out           │
│ NOT_ELIGIBLE players (UX gate); the authoritative gate is API-side     │
│ re-validation on any roster-submission write.                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Panel-ready framing:** four states cover the real lifecycle (PENDING = not yet reviewed, ACADEMIC_WARNING = eligible-but-flagged early intervention); the single-field serializer + enum choices means storing a grade is a *type/validation error*; the history table proves auditability while storing zero academic content.

---

### 1.4 The Dispute Lifecycle (foundation, append-only audit trail)

**Principle:** disputes are a role-locked state machine (`OPEN → RESPONDED → RESOLVED`) living in one service class. Evidence is an append-only `DisputeEvent` table — no update/delete route exists, and the DB role's UPDATE/DELETE privileges on that table are revoked (defense in depth).

```
STEP 1 — Coach flags an entry (attendance mark or rating)
  POST /api/v1/disputes/  { subject_type, subject_id, note }
    ✓ role == COACH; subject belongs to the coach's club
    → atomic(): Dispute(OPEN) + DisputeEvent(OPENED, actor, note)
    → FCM to School Staff linked to the player's school

STEP 2 — School Staff participates
  POST /api/v1/disputes/{id}/respond/  { note }
    ✓ role == SCHOOL_STAFF, scoped to the player's school
    ✓ current status == OPEN            ← illegal transition → 409
    → status = RESPONDED + DisputeEvent(RESPONDED)
    → FCM to the opening coach + Admin
  (Coach may add follow-up notes: POST .../comment/ appends a
   DisputeEvent without changing status — "Coach flag/respond" per spec.)

STEP 3 — Admin reviews & resolves
  POST /api/v1/disputes/{id}/resolve/  { resolution, corrective_action? }
    ✓ role == ADMIN;  ✓ status ∈ {RESPONDED, OPEN (escalation)}
    → status = RESOLVED + DisputeEvent(RESOLVED, resolution)
    → corrective write (e.g., flip an attendance mark) executed IN THE
      SAME SERVICE with its own DisputeEvent(CORRECTION_APPLIED) —
      Admin never hand-edits attendance/rating rows directly.
    → FCM to coach + staff

STATE MACHINE (one place, ~20 lines):
  ALLOWED = { OPEN:      {RESPOND: SCHOOL_STAFF, RESOLVE: ADMIN},
              RESPONDED: {RESOLVE: ADMIN} }
  Anything else → 409 Conflict.

READ SCOPE: participants + Admin. DisputeEvent: append-only by routing
AND by DB privilege revocation.
```

---

### 1.5 Ratings, Feedback, Match Stats & Injury History (the remaining spec items)

```
RATINGS + QUALITATIVE FEEDBACK (Coach → Player/Guardian)
  POST /api/v1/ratings/
    ✓ IsCoachOfPlayer
    ✓ rubric_variant ∈ {OUTFIELD, GK}; scores JSONB validated against the
      variant's attribute list; every value int ∈ [1, 10]  ← adviser's
      standardized 1–10 rubric (validator constant RUBRIC_MIN/MAX = 1/10,
      so a future scale change is a one-line diff, not a schema change)
    ✓ qualitative_feedback: plain text, length-capped, rendered escaped
  → on_commit: FCM to player + linked guardians ("New coach feedback")
    ← per spec: Player & Guardian receive feedback notifications
  Performance trends (Coach + Player views): GET .../players/{id}/trends/
    → per-attribute time series aggregated server-side from Rating rows.

MATCH PERFORMANCE STATISTICS (Coach records → Player views)
  MatchStat rows tied to schedules with session_type=MATCH; Coach writes,
  Player(self) + linked Guardian read. Kept as flexible JSONB for MVP.

INJURY HISTORY — the one Player-write feature (full CRUD)
  /api/v1/injuries/           (list/create)   ✓ IsOwnerPlayer
  /api/v1/injuries/{id}/      (update/delete) ✓ object-level: record.player
                                               == request.user's profile
  Reads: Player(self); Coach(read-only, players of own club — informs
  training load); linked Guardian(read-only).
  Data-minimization note: title/body_area/dates/notes only — this is
  self-reported sports-injury context, not a medical record; no
  diagnosis codes, no attachments in MVP.

SCHEDULE NOTIFICATIONS (per spec: schedule updates push to Player+Guardian)
  Schedule create/update in the coach flow → on_commit fan-out to the
  club's players + their linked guardians: "Training added/changed:
  Sat 4:00 PM, Aboitiz Pitch." Payload = schedule id + change type only.
```

---

## 2. DAY-BY-DAY SPRINT SCHEDULE

**DIP mechanics:** Member B never waits for the backend. Day 1 EOD: `domain/` package frozen (entities incl. 1–10 score types, 4-state eligibility enum, injury entity; ALL repository interfaces). **Day 5 EOD: OpenAPI contract frozen** — the one inter-dev hard dependency. **Day 9, 12:00: feature freeze. Day 10 AM: code freeze.**

| Day | Member A — Django Backend | Member B — Flutter + Web Portals | Member C — QA / Testing / DevOps |
|---|---|---|---|
| **1** | Project scaffold: settings split (dev/prod), custom User model (`firebase_uid`, 5-role enum), Firebase Admin SDK init, `FirebaseAuthentication` DRF class. **Co-freeze Flutter `domain/` package with B by EOD.** | Flutter scaffold: routing, Provider + get_it, auth gate, role-based home routing (Coach/Player/Guardian). Co-freeze `domain/` package. | GitHub Actions skeleton: lint + test jobs both repos, branch protection, pre-commit (black/flake8/dart format), PostgreSQL service container in CI. |
| **2** | Full §1.0 models + migrations (AgeTierConfig, InjuryRecord, MatchStat, 4-state Eligibility, `client_uuid` on marks). Provisioning service + Firebase compensation. Draft OpenAPI. | `MockRepositories` (B owns; seeded demo data, fake latency, offline toggle). Coach: schedule CRUD screens + VMs against mocks. | pytest-django + factory_boy; factories for every model; first tests: provisioning incl. compensation path (mocked Admin SDK). |
| **3** | Auth middleware hardened (revocation, inactive-user). Permission classes: `IsAdmin`, `IsCoachOfSession`, `IsCoachOfClub`, `IsCoachOfPlayer`, `IsSchoolStaffOfPlayer`, `IsOwnerPlayer`. Attendance bulk-sync (idempotency + LWW). | Coach: attendance screen — roster, 3-state segmented control, pending-sync icon on mock queue stream. Drift local DB: tables + sync_queue. | **Permission matrix suite:** parameterized pytest — every endpoint × every wrong role → 403. Grows with each endpoint A ships; this is the security spine. |
| **4** | Ratings endpoints: 1–10 per-variant validation, qualitative feedback, trends aggregation. MatchStat endpoints. Eligibility endpoint (single-field, 4-state) + history list for Staff. | Coach: rating entry — OUTFIELD/GK variant switch, 1–10 steppers, feedback text box. Player dashboard: profile, schedule, attendance, eligibility badge (incl. amber ACADEMIC_WARNING state). | Sync-conflict tests: `client_uuid` replay → no-op; stale `device_ts` → skip; bad enum → 400 + dead-letter spec. flutter_test harness + first VM tests (mockito on interfaces). |
| **5** | Injury CRUD (object-level ownership). Dispute service (state machine) + endpoints. NotificationService (schedule/feedback/eligibility/absence fan-outs) + FcmDevice registration. **EOD: OpenAPI contract FROZEN → staging.** | Player: ratings/feedback view, match stats view, injury history CRUD screens. Guardian: multi-child switcher + read-only child dashboards (mocks). | Contract tests: schema generated from DRF diffed against the frozen spec in CI (drift fails the build). Staging deploy pipeline live. |
| **6** | Admin + Staff portal plumbing: provisioning, guardian-link, role management (claim re-stamp + `claims_version`), age-tier config forms; staff eligibility toggle + history view. Real FCM wired for all four notification types. | Build `HttpXRepositories` (Dio + token-refresh interceptor) against the frozen contract. **Swap DI mocks→HTTP for auth, schedules, attendance in dev.** Start portal templates (B owns portal UI; A owns plumbing). | OWASP ZAP baseline scan on staging; findings triaged to A. Integration test: bulk-sync end-to-end with simulated network loss. |
| **7** | Fix contract mismatches B files (contract frozen — fixes are impl bugs, not spec changes). Trends endpoint performance pass (indexes on Rating(player, created_at)). | Swap remaining repos (ratings, eligibility, injuries, match stats, disputes). Finish portal templates: admin provisioning/link/roles/tiers, staff roster + history. First full E2E: admin provisions → player logs in. | Demo data script (factories → staging): clubs across ≥2 provinces, all 3 tiers, linked guardians (incl. one guardian with 2 children), ratings + feedback + injuries + all 4 eligibility states. flutter integration_test: login → offline mark → sync. |
| **8** | **Offline gauntlet (whole team, C drives):** real devices, airplane mode, kill-and-relaunch persistence, reconnect auto-sync, guardian absence push, two-device LWW check. A fixes server sync edges. FCM verified iOS + Android for all 4 notification types. | Fix Coach offline UX from gauntlet (pending icons, dead-letter surfacing). Deep links: absence → correct child; feedback → rating detail; eligibility → badge screen; schedule → schedule detail. | Runs the gauntlet script + logs defects. ZAP full scan on near-final staging. Coverage gate check on services + permissions (agreed threshold, e.g. 80%). |
| **9** | **12:00 feature freeze.** Deploy prod. Run §4 items 1–14 adversarially (curl/Postman, wrong-role tokens). Rate limiting on provisioning/auth-adjacent endpoints. | Bug fixes only. Run §4 items 15–25 across Flutter + portals. Polish, no new features. | CI green on release branch. Pen-test pass: token tampering (expired / other-project / alg-none), IDOR probes on every ID-bearing route incl. `/injuries/{id}/`. |
| **10** | **Code freeze AM.** Final audit sign-off, prod smoke with fresh accounts, DB backup verified, tag release. | Demo dry-run: full happy path + fallback demo video. | Release checklist executor: every §4 box gets an evidence link (test run/screenshot) — doubles as thesis defense evidence. |

**Slack built in:** Day 8 is integration-only; Day 9 PM is buffer. If A slips, B is unaffected until Day 6 — the mock-first DIP setup exists precisely for that, and the Day 5 contract freeze is the only cross-dev hard dependency.

---

## 3. CONCRETE MVVM BLUEPRINT — Offline Attendance (Flutter + Django)

Layering: `View → ViewModel → Abstract Repository (domain) ← OfflineFirst/Mock impl (data) → Dio → Django`. The ViewModel imports zero networking/DB packages (SRP); it depends only on the abstraction (DIP).

### 3.1 Model (domain — pure Dart)

```dart
// domain/entities/attendance_mark.dart
enum AttendanceStatus { present, absent, excused }

class AttendanceMark {
  final String playerId;
  final String playerName;        // denormalized for list rendering
  final AttendanceStatus? status; // null = unmarked
  final bool isPendingSync;       // true while an op sits in the sync queue
  const AttendanceMark({
    required this.playerId,
    required this.playerName,
    this.status,
    this.isPendingSync = false,
  });
}
```

### 3.2 Abstract Repository Interface (domain — the DIP seam)

```dart
// domain/repositories/attendance_repository.dart
abstract class IAttendanceRepository {
  /// Live roster from the LOCAL database. Emits instantly offline;
  /// isPendingSync flags rows whose ops are still queued.
  Stream<List<AttendanceMark>> watchSession(String scheduleId);

  /// Commits locally + enqueues a sync op. Never blocks on the network.
  Future<void> mark(String scheduleId, String playerId, AttendanceStatus s);
}
```

### 3.3 Offline-First Implementation (data layer — Drift local DB + sync queue)

```dart
// data/repositories/offline_first_attendance_repository.dart
class OfflineFirstAttendanceRepository implements IAttendanceRepository {
  OfflineFirstAttendanceRepository(this._db, this._queue);
  final AppDatabase _db;   // Drift: marks table + sync_queue table
  final SyncQueue _queue;

  @override
  Stream<List<AttendanceMark>> watchSession(String scheduleId) =>
      _db.watchMarksWithPendingFlag(scheduleId); // JOIN marks × sync_queue

  @override
  Future<void> mark(String sid, String pid, AttendanceStatus s) async {
    await _db.transaction(() async {
      await _db.upsertMark(sid, pid, s);            // local truth first
      await _queue.enqueueReplacing(                // coalesce corrections
        key: 'attendance:$sid:$pid',
        op: SyncOp(
          clientUuid: const Uuid().v4(),            // idempotency key
          method: 'POST',
          path: '/api/v1/attendance/marks/bulk-sync/',
          payload: {
            'schedule_id': sid,
            'player_id': pid,
            'status': s.name.toUpperCase(),
            'device_ts': DateTime.now().toUtc().toIso8601String(), // LWW
          },
        ),
      );
    });
  }
}

// data/sync/sync_worker.dart — woken by connectivity_plus (auto-sync per spec)
class SyncWorker {
  Future<void> drain() async {
    for (final op in await _queue.pendingFifo()) {
      try {
        await _api.post(op.path, data: op.payload,
            options: Options(headers: {'X-Client-UUID': op.clientUuid}));
        await _queue.remove(op);              // 2xx → done
      } on DioException catch (e) {
        final code = e.response?.statusCode ?? 0;
        if (code >= 400 && code < 500) {
          await _queue.deadLetter(op, e);     // rule violation: surface it,
        } else {                              // never retry forever
          break;                              // offline again → stop, retry later
        }
      }
    }
  }
}
```

### 3.4 Mock Implementation (Member B's Days 1–5 workhorse)

```dart
class MockAttendanceRepository implements IAttendanceRepository {
  final _state = <String, AttendanceMark>{/* seeded demo roster */};
  final _ctrl = StreamController<List<AttendanceMark>>.broadcast();
  bool simulateOffline = false; // debug-drawer toggle exercises pending UI

  @override
  Stream<List<AttendanceMark>> watchSession(String _) async* {
    yield _state.values.toList();
    yield* _ctrl.stream;
  }

  @override
  Future<void> mark(String _, String pid, AttendanceStatus s) async {
    _state[pid] = AttendanceMark(
        playerId: pid, playerName: _state[pid]!.playerName,
        status: s, isPendingSync: simulateOffline);
    _ctrl.add(_state.values.toList());
    if (simulateOffline) {
      Future.delayed(const Duration(seconds: 5), () {
        _state[pid] = AttendanceMark(
            playerId: pid, playerName: _state[pid]!.playerName, status: s);
        _ctrl.add(_state.values.toList());
      });
    }
  }
}
```

### 3.5 ViewModel (presentation — no Dio, no Drift; unit-testable with mockito)

```dart
class AttendanceViewModel extends ChangeNotifier {
  AttendanceViewModel(this._repo, this.scheduleId) {
    _sub = _repo.watchSession(scheduleId).listen(
      (m) { _marks = m; _error = null; notifyListeners(); },
      onError: (_) { _error = 'Could not load roster'; notifyListeners(); },
    );
  }
  final IAttendanceRepository _repo;   // ← abstraction only (DIP)
  final String scheduleId;
  late final StreamSubscription _sub;

  List<AttendanceMark> _marks = [];
  String? _error;
  List<AttendanceMark> get marks => _marks;
  String? get error => _error;
  int get pendingCount => _marks.where((m) => m.isPendingSync).length;

  Future<void> setStatus(String pid, AttendanceStatus s) =>
      _repo.mark(scheduleId, pid, s);  // optimistic; local stream reconciles

  @override
  void dispose() { _sub.cancel(); super.dispose(); }
}
```

### 3.6 View (rendering only)

```dart
class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key, required this.scheduleId});
  final String scheduleId;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) =>
        AttendanceViewModel(getIt<IAttendanceRepository>(), scheduleId),
    child: Consumer<AttendanceViewModel>(
      builder: (_, vm, __) => Scaffold(
        appBar: AppBar(title: const Text('Attendance'), actions: [
          if (vm.pendingCount > 0) _PendingSyncChip(vm.pendingCount),
        ]),
        body: ListView.builder(
          itemCount: vm.marks.length,
          itemBuilder: (_, i) {
            final m = vm.marks[i];
            return ListTile(
              title: Text(m.playerName),
              leading: m.isPendingSync
                  ? const Icon(Icons.cloud_upload_outlined, size: 18)
                  : null,
              trailing: SegmentedButton<AttendanceStatus>(
                segments: const [
                  ButtonSegment(value: AttendanceStatus.present, label: Text('P')),
                  ButtonSegment(value: AttendanceStatus.absent,  label: Text('A')),
                  ButtonSegment(value: AttendanceStatus.excused, label: Text('E')),
                ],
                selected: {if (m.status != null) m.status!},
                emptySelectionAllowed: true,
                onSelectionChanged: (sel) => vm.setStatus(m.playerId, sel.first),
              ),
            );
          },
        ),
      ),
    ),
  );
}
```

### 3.7 DI Composition Root (the one-line swap)

```dart
void configureDependencies({required bool useMocks}) {
  if (useMocks) {
    getIt.registerLazySingleton<IAttendanceRepository>(
        () => MockAttendanceRepository());
  } else {
    getIt.registerLazySingleton<IAttendanceRepository>(
        () => OfflineFirstAttendanceRepository(getIt(), getIt()));
  }
  // same pattern for every repository (ratings, injuries, eligibility, ...)
}
```

### 3.8 Django Counterpart (Member A's side of the same feature)

```python
# attendance/permissions.py
class IsCoachOfSession(BasePermission):
    def has_permission(self, request, view):
        return request.user.role == User.Role.COACH

# attendance/serializers.py
class AttendanceMarkSyncSerializer(serializers.Serializer):
    schedule_id = serializers.IntegerField()
    player_id   = serializers.IntegerField()
    status      = serializers.ChoiceField(choices=AttendanceMark.Status.choices)
    device_ts   = serializers.DateTimeField()
    # marked_by is NEVER accepted from the client

# attendance/views.py
class AttendanceBulkSyncView(APIView):
    permission_classes = [IsAuthenticated, IsCoachOfSession]

    def post(self, request):
        s = AttendanceMarkSyncSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        schedule = get_object_or_404(
            Schedule, id=d["schedule_id"], coach=request.user)  # ownership
        client_uuid = request.headers.get("X-Client-UUID")

        with transaction.atomic():
            existing = AttendanceMark.objects.select_for_update().filter(
                schedule=schedule, player_id=d["player_id"]).first()
            if existing and existing.client_uuid == client_uuid:
                return Response(status=200)                # idempotent replay
            if existing and existing.device_ts >= d["device_ts"]:
                return Response(status=200)                # last-write-wins
            mark, was_absent = upsert_mark(
                schedule, d, marked_by=request.user, client_uuid=client_uuid)
            if mark.status == AttendanceMark.Status.ABSENT and not was_absent:
                transaction.on_commit(
                    lambda: notify_guardians_absent(mark))  # FCM fan-out
        return Response(status=200)
```

Replicate the five-file Flutter pattern + the permission/serializer/service Django triple per feature (ratings with the 1–10 validator, injury CRUD with object-level ownership, eligibility with the single-field serializer). **SRP audit shortcut:** a ViewModel importing `dio`/`drift` fails review; a Django view containing business logic instead of calling a service fails review.

---

## 4. DEPLOYMENT & SECURE CODING AUDIT CHECKLIST (Day 10 code freeze)

**Method:** every item is verified adversarially — pytest permission matrix, curl/Postman with wrong-role tokens, OWASP ZAP — never by reading code. Member C attaches evidence per box; the completed checklist doubles as defense evidence for OWASP Top 10 / MASVS / RA 10173 claims.

### A. Identity & Token Verification (Firebase ↔ Django seam)
1. ☐ Clients contain **zero** signup calls (grep both codebases); an identity with no active Django `User` row → 403 from middleware, so console-side signup is inert.
2. ☐ Middleware rejects: expired tokens, tokens from a **different Firebase project** (audience check), unsigned/alg-none JWTs, revoked tokens on sensitive endpoints, uids with no active local User.
3. ☐ Deactivating a User in Django kills API + portal access **immediately** (DB is the authority, not the claim) — verified live.
4. ☐ Role reassignment (Admin "manage role-based permissions"): DB role change + claim re-stamp + `claims_version` bump verified; demoted user loses access on the next API call.
5. ☐ Provisioning compensation: forced DB failure after Firebase user creation → Firebase user deleted, no orphaned identity (pytest, mocked Admin SDK).
6. ☐ Temp credentials never logged, never in responses, never in PostgreSQL; reset flows through Firebase email only. Firebase service-account JSON exists only as a server-side secret — repo grep clean, never in the Flutter bundle or template context.

### B. Authorization — Least Privilege (frontend never trusted)
7. ☐ **Permission matrix suite green:** parameterized pytest hits every endpoint with every wrong role → 403; the matrix table is exported for the thesis appendix.
8. ☐ IDOR sweep: every ID-bearing route probed as a non-owner — player B's ratings/injuries as player A, unlinked child as guardian, other coach's session, other school's player as staff → 403/404, never 200. `/injuries/{id}/` gets explicit attention (player-writable = highest IDOR risk in the system).
9. ☐ `marked_by`, `updated_by`, `opened_by`, rating `coach` are always set server-side from `request.user`; client-supplied values ignored — spoof tests pass.
10. ☐ Rating validation: every score int ∈ [1,10]; attribute keys must match the variant's allow-list (OUTFIELD vs GK) — unknown attributes → 400. Qualitative feedback length-capped and rendered escaped (XSS check on portal + app).
11. ☐ Dispute state machine: every illegal transition → 409; `DisputeEvent` has no update/delete route AND the DB role lacks UPDATE/DELETE on the table.
12. ☐ Eligibility serializer rejects any payload key beyond `status`; value outside the 4-state enum → 400; staff scoped to own school's linked players; history endpoint readable by Staff (and Admin) only.
13. ☐ Guardian scoping: guardian without a `GuardianLink` to a player → 403/404 on every child-data route; deleting the link revokes access on the next request; guardian write attempts on any child data → 403 (read-only per spec).
14. ☐ Portals enforce the same permission classes as the API (no side door) + CSRF on all portal POSTs; rate limiting on provisioning/auth-adjacent endpoints; `DEBUG=False`, `ALLOWED_HOSTS` set, HSTS + secure cookies on.

### C. Data Minimization & RA 10173
15. ☐ Schema/serializer grep: no field named/containing `grade`/`gwa` anywhere; `Eligibility` exposes exactly `{status, updated_by, updated_at}`; `EligibilityHistory` stores transitions with **no reasons/free text**.
16. ☐ FCM payloads audited on a real lock screen for all four notification types (schedule, feedback, eligibility, absence): IDs + status/type + neutral copy only — no rating values, no eligibility detail, no injury info, no other children's names.
17. ☐ Role-scoped serializers expose minimum viable PII (e.g., a coach's roster view carries no guardian contact details; a guardian's view carries no other players' data).
18. ☐ Injury records: fields limited to title/body_area/dates/notes (self-reported context, not medical records); visible only to the player, club coach (read), and linked guardians (read) — verified in the matrix suite.
19. ☐ Logs: no PII, no bearer tokens, no request-body dumps (grep logging config + sampled prod logs); error reporting scrubbed.
20. ☐ Stale FCM tokens pruned on `UNREGISTERED`; `FcmDevice` rows deleted on user deactivation.

### D. Client & Sync Hardening (OWASP MASVS-aligned)
21. ☐ Every role check in Flutter/portal UI is duplicated server-side — spot-verify 3 flows by calling the API directly with a wrong-role token, bypassing the UI entirely.
22. ☐ ViewModels import no `dio`/`drift`/`firebase_*` packages (mechanical grep across `presentation/`); repository interfaces are the only seam — DIP verified structurally.
23. ☐ Offline gauntlet on the release build: airplane-mode marks → kill app → relaunch offline (local DB persists) → reconnect → queue drains FIFO automatically → guardian push arrives; replayed `client_uuid` → no duplicates; stale `device_ts` → LWW skip verified on two devices.
24. ☐ Dead-letter behavior: a 403-rejected sync op surfaces a visible error to the coach and stops retrying — never silently dropped, never infinite-retried.
25. ☐ 401/403 surface as clean UX (snackbar + re-auth prompt), not crashes or spinners; the token interceptor silently refreshes an expired Firebase ID token once before failing.

### E. Release Mechanics & Scanning
26. ☐ OWASP ZAP full scan on final staging: no High findings; Mediums triaged with written dispositions (thesis appendix material).
27. ☐ Dev/staging/prod separated (envs + DBs); demo-data script pointed at prod explicitly, run once, then disabled; secrets via environment, never committed.
28. ☐ CI green on the release tag: pytest-django (permission matrix + sync-conflict + provisioning-compensation tests), flutter_test + integration_test, contract-drift check against the frozen OpenAPI spec.
29. ☐ PostgreSQL automated backups scheduled + a pre-demo dump taken and **restore-tested**; rollback plan written (previous tag redeployable; migrations reviewed for reversibility).
30. ☐ Fresh-account prod smoke covering the full adviser scope: Admin provisions Player + Guardian → links them → both log in → Coach creates a schedule (push received) → marks the player absent offline → auto-sync → guardian absence push → Coach submits a 1–10 rating + feedback (push received) → Player logs an injury and edits it → Staff sets ACADEMIC_WARNING on the portal (push received; badge updates; history row visible to Staff) → Coach opens a dispute → Staff responds → Admin resolves → DisputeEvent trail shows immutable entries. **All 30 boxes ticked → freeze.**
