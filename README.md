# FootPath-Cebu

Youth Sports Academy Portal — Capstone Project.

**Stack:** Flutter (Clean Architecture + MVVM) · Firebase Authentication · Django REST backend · Firebase Cloud Messaging (FCM)

---

## Project layout

```
footpath_cebu/   Flutter mobile app (Coach, Player, Guardian) — Clean Architecture + MVVM
backend/         Django REST API + admin console (account provisioning, RBAC)
docs/            Requirements, setup, and detailed execution notes
```

### Flutter Clean Architecture (`footpath_cebu/lib/`)

The app is organized into **Clean Architecture** layers with the Dependency Rule pointing inward: **presentation → domain ← data**. The domain layer is pure Dart (no Flutter, Firebase, or HTTP) and holds entities, repository *interfaces*, and **use cases** (interactors). Presentation state is managed with **Riverpod** (see ADR 0002): screens are `ConsumerWidget`s that watch providers, and the providers depend on use cases — never on a concrete data source.

```
lib/
  domain/          Pure business core — no Flutter, no I/O
    entities/        Immutable data classes (Player, Attendance, MatchPerformance)
    repositories/    Abstract interfaces (AuthRepository, SquadRepository, ...)
    usecases/        One class per operation (SignIn, GetSquad, GetMyProfile, ...)
  data/            Implements the domain interfaces
    repositories/    mock_* (in-memory) + firebase_/api_* (live Django REST + Firebase)
  presentation/    UI + state (Riverpod)
    providers/       FutureProviders, Notifiers and controllers — depend on use cases only
    screens/         Views (CoachDashboardScreen, LoginScreen, HomeScreen)
    widgets/         Reusable UI (PlayerCard — the FUT-style roster card)
  core/
    config/          ApiConfig (base URLs)
    di/              providers.dart — composition root; repository providers swap mock <-> live
```

SOLID shows up concretely: use cases depend on **narrow** repository interfaces (`SquadRepository`, `PlayerProfileRepository`, `LinkedPlayersRepository` — Interface Segregation + Dependency Inversion); provider-specific concerns (Firebase, HTTP, JSON) stay in the data layer so domain and presentation stay provider-agnostic.

**Feature trace — Coach dashboard "Active Squad Roster":**
`CoachDashboardScreen` (View) → `filteredSquadProvider`/`squadProvider` → `GetSquad` (use case) → `SquadRepository` → `MockPlayerRepository` / `ApiPlayerRepository`. Live Firebase + Django repositories are the default; use `--dart-define=USE_MOCK=true` only for isolated UI work (release builds are always live).

**Feature trace — Match performance:**
`CoachMatchesScreen` / `PlayerMatchStatisticsView` → match providers → narrow match use cases → `MatchManager` / `MatchStatisticsReader` → `MockMatchRepository` / `ApiMatchRepository`. Django stamps match ownership from the authenticated Coach, validates same-Club players, and exposes read-only trends to the Player, same-Club Coach, Admin, and linked Guardians through the existing privacy-PIN unlock.

Tests live in `footpath_cebu/test/` (entity round-trips, provider filtering/error paths via `ProviderContainer` overrides, dashboard widget tests inside `ProviderScope`). Run with `flutter test`.

---

# 2-Week Execution Plan

## 1. Comprehensive Workflow Architecture

### A. Account Provisioning & Linking
There is no public registration. The approved hierarchy is:

```
SUPER ADMIN
    ↓ creates/classifies
CLUB (SCHOOL or INDEPENDENT)
    ↓ receives one
CLUB COORDINATOR
    ↓ provisions only inside that club
COACH / PLAYER / GUARDIAN / SCHOOL STAFF
```

- Super Admin creates/manages Clubs and provisions each Club's Coordinator.
- The Coordinator is the normal creator of Club members. Django derives the
  target Club from the authenticated Coordinator and ignores manipulated
  `club_id` input.
- Player creation atomically creates the `PLAYER` user, non-null Club,
  `PlayerProfile`, and optional same-Club Guardian link.
- Only School Clubs allow School Staff and status-only academic eligibility.
  Independent Clubs show eligibility as Not Applicable.
- FootPath Cebu never stores raw student grades, GPA, report cards,
  transcripts, or grade uploads.

See [Account and Club Hierarchy](docs/ACCOUNT-AND-CLUB-HIERARCHY.md).

### B. Offline-to-Online Attendance
The live app uses a Firebase-user-scoped SQLite cache for successful API reads
and a durable attendance outbox for writes made without a connection:

```
Coach → Attendance Screen → Riverpod controller → OfflineFirstAttendanceRepository
      → Django API when online
      → SQLite outbox on transport failure → replay service on reconnect
```

Only connection-level failures use cached data or queue a write. Authentication,
authorization, validation, and server failures remain visible and are never
masked as offline success. Replays are scoped to the signed-in Firebase UID and
processed oldest first, so the latest complete session batch wins.

### C. Academic Eligibility Gating
School Staff set an eligibility **status enum only** — never grades, GPA, or report cards:

```
  PlayerProfile.eligibility = ELIGIBLE | NOT_ELIGIBLE | PENDING | ACADEMIC_WARNING
```

Django records an inbox notification and sends a neutral FCM alert to the
Player and linked Guardians after a committed status change. Authorized detail
is loaded from Django; no grade value enters the notification payload.

### D. Dispute Lifecycle
```
Coach creates dispute (`OPEN`) → authorized reviewer responds
→ `UNDER_REVIEW` → `RESOLVED` or `DISMISSED`
```
The response thread and `AuditLog` provide an append-only history with actor and
timestamp attribution.

---

## 2. Delivered Architecture Map

| Day | Dev A (Backend) | Dev B (Coach/Admin) | Dev C (Player/Guardian) |
|----|----|----|----|
| **1** | Django models, Firebase identity verification, RBAC | Riverpod/Clean Architecture foundation | Login and role routing |
| **2** | Super Admin Club/Coordinator APIs and Guardian linking | Admin/Coordinator web workflows | Player and Guardian profiles |
| **3** | Attendance API and user-scoped SQLite outbox | Attendance capture and sync state | Attendance history |
| **4** | Performance profile API | Coach assessment workflow | Player performance display |
| **5** | School-only eligibility status/history | Coordinator roster | School Staff eligibility portal |
| **6** | Schedule and persistent notification inbox | Schedule CRUD and notification bell | Schedule/RSVP and notification inbox |
| **7** | Disputes, responses, and authorization | Coach dispute workflow | Authorized review workflow |
| **8** | Audit logs, privacy PINs, photo storage gateway | Photo upload and privacy UI | Guardian privacy gates |
| **9** | **Entire team:** regression, security, offline, and failure-path testing |||
| **10** | **Release preparation:** deployment/config checks, migration review, backup/restore scripts and runbook, and demo checklist |||

---

## 3. Concrete Architecture Blueprint (Offline Attendance)

```dart
// Model — plain data, no logic
class Attendance {
  final String playerId;
  final String status;
  final DateTime updatedAt;
}

// Narrow domain interface — presentation depends on this abstraction.
abstract class SessionAttendanceWriter {
  Future<List<Attendance>> saveSessionAttendance(
    String sessionId,
    List<Attendance> records,
  );
}

// Data-layer decorator — queues only typed connection failures.
class OfflineFirstAttendanceRepository implements AttendanceRepository {
  final AttendanceRepository inner;
  final AttendanceOutbox outbox;
  // ...
}

// Riverpod controller — owns UI state, not HTTP or SQLite details.
class AttendanceLogController extends Notifier<AttendanceLogState> {
  Future<bool> save(String sessionId, List<Attendance> records) { ... }
}
```

**SOLID application**
- **SRP:** Repository = data access, ViewModel = business logic, View = rendering only.
- **DIP:** use cases/controllers depend on domain repository interfaces, not
  `http`, SQLite, or Firebase implementations.
- The view sends intent through Riverpod providers; the data layer owns API,
  cache, and synchronization mechanics.

---

## 4. Deployment & Secure-Coding Audit Checklist

**Authentication**
- [x] No public registration enabled
- [x] Super Admin creates Clubs and their Coordinators
- [x] Club Coordinators create normal accounts in their own Club
- [x] Player creation atomically creates its profile and non-null Club link
- [x] Firebase ID tokens are verified and mapped to active Django users

**Role-Based Access Control**
- [x] Django role, Club, object, and Guardian-link checks are authoritative
- [x] Frontend role checks are UX routing only
- [x] Cross-Club provisioning and data access have regression coverage

**Tenant and object security**
- [x] Players read their own protected data
- [x] Coaches record same-Club match statistics and view player trends
- [x] Players view their own match summaries, history, and rating trends
- [x] Linked Guardians view player match trends through the privacy-PIN gate
- [x] Guardians require a same-Club link and privacy unlock
- [x] Coaches are limited to their Club
- [x] School Staff eligibility exists only for School Clubs
- [x] Super Admin-only Club and Coordinator operations are server-enforced

**Data Minimization**
- [x] No academic grades are stored; eligibility uses a status enum only
- [x] Guardian relationships are stored separately
- [x] Push payloads avoid grades and unnecessary academic detail

**Offline Support**
- [x] User-scoped SQLite API cache and attendance outbox implemented
- [x] Automatic reconnect replay and typed failure handling tested

**Notifications**
- [x] Django records notifications only for authorized recipients
- [x] FCM registration, refresh, and account-scoped removal are implemented
- [x] Persistent inbox, unread state, foreground handling, and tap routing exist
- [ ] Verify delivery end-to-end on configured Android/iOS devices

**Audit Logging**
- [x] Critical actions are attributed in `AuditLog`
- [x] Eligibility history and dispute responses are append-only

**SOLID Compliance**
- [x] Screens delegate operations to Riverpod controllers/use cases
- [x] Domain entities and interfaces contain no Firebase/HTTP dependencies
- [x] Repositories abstract data access and are wired through providers
- [x] Mock implementations support deterministic Flutter testing

**Final Release Validation**
- [x] Authentication, RBAC, Club boundaries, and Player invariants tested
- [x] Offline attendance replay and cache isolation tested
- [x] Eligibility workflow validated without grade storage
- [x] Notification inbox/read state and role-aware routing covered locally
- [ ] Real Firebase/APNs delivery verified on supported physical devices
- [x] Dispute lifecycle covered by backend and Flutter tests
- [ ] Production URL, device delivery, alerting, and restore drill verified

See [Production Operations](docs/PRODUCTION-OPERATIONS.md) for the deploy,
monitoring, backup, and evidence procedure.
