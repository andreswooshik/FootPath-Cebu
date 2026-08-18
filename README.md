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
    entities/        Immutable data classes (Player, UserProfile, Attendance)
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
`CoachDashboardScreen` (View) → `filteredSquadProvider`/`squadProvider` → `GetSquad` (use case) → `SquadRepository` → `MockPlayerRepository` / `ApiPlayerRepository`. Mock is the debug default; run against the live backend with `--dart-define=USE_MOCK=false` (release builds are always live).

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
Firestore local persistence is enabled, so the coach can mark attendance on the pitch with no internet:

```
Coach → Attendance Screen → AttendanceViewModel → IAttendanceRepository → Firestore local cache
```

On reconnect, Firestore's sync engine pushes to Cloud Firestore, a Cloud Function finds guardian links, and FCM notifies the guardian + player.
**Conflict resolution:** last-write-wins; every record carries `updatedAt`, `deviceTimestamp`, `coachUid`.

### C. Academic Eligibility Gating
School Staff set an eligibility **status enum only** — never grades, GPA, or report cards:

```
  PlayerProfile.eligibility = ELIGIBLE | NOT_ELIGIBLE | PENDING | ACADEMIC_WARNING
```

A Cloud Function notifies linked guardians on change. School Staff can access **only** the eligibility collection — not attendance, coach notes, or guardian accounts.

### D. Dispute Lifecycle
```
Coach creates dispute (status=OPEN) → School Staff responds (RESPONDED) → Admin reviews → Accept/Reject (CLOSED)
```
Audit trail is **immutable** — every action is appended to `history/` with `actorUid`, `timestamp`, `action`, `comment`.

---

## 2. Day-by-Day Sprint Schedule

| Day | Dev A (Backend) | Dev B (Coach/Admin) | Dev C (Player/Guardian) |
|----|----|----|----|
| **1** | Firebase setup, Firestore collections, Auth, custom claims, security-rules skeleton | MVVM setup, Admin Login UI, Coach Dashboard UI, repository interfaces | Login UI, Player & Guardian Dashboard UI, mock repositories |
| **2** | User provisioning APIs, guardian linking, Age Tier CRUD | Admin account screens | Profile pages |
| **3** | Attendance schema, Firestore offline config | Attendance UI | Attendance history screen |
| **4** | Performance schema | Performance grading | Ratings viewer |
| **5** | Eligibility backend | Coach player profile | School Staff eligibility UI |
| **6** | Cloud Messaging, notification triggers | Schedule CRUD | Schedule viewer |
| **7** | Dispute collections | Coach dispute UI | Staff dispute response UI |
| **8** | Audit logs, Cloud Functions testing | Admin review UI | Guardian notifications |
| **9** | **Entire team:** integration, bug fixing, security-rules validation, performance & offline testing |||
| **10** | **Code freeze:** security audit, regression testing, final deployment, presentation prep |||

---

## 3. Concrete MVVM Blueprint (example: Offline Attendance)

```dart
// Model — plain data, no logic
class Attendance {
  final String playerId;
  final String status;
  final DateTime updatedAt;
}

// Repository interface — the ViewModel depends on THIS
abstract class IAttendanceRepository {
  Future<void> saveAttendance(Attendance attendance);
  Stream<List<Attendance>> watchAttendance(String teamId);
}

// Implementation — uses Firestore offline persistence automatically
class FirestoreAttendanceRepository implements IAttendanceRepository { ... }

// ViewModel — business logic only, NO Firebase code
class AttendanceViewModel extends ChangeNotifier {
  final IAttendanceRepository repository;
  Future<void> markPresent() { ... }
  Future<void> markAbsent() { ... }
}
```

**SOLID application**
- **SRP:** Repository = data access, ViewModel = business logic, View = rendering only.
- **DIP:** ViewModel depends on `IAttendanceRepository`, **not** `FirestoreAttendanceRepository` — enabling mock repositories for testing.
- View (`AttendanceScreen`) talks to the ViewModel via a provider; it never communicates directly with Firebase.

---

## 4. Deployment & Secure-Coding Audit Checklist

**Authentication**
- [ ] No public registration enabled
- [ ] Super Admin creates Clubs and their Coordinators
- [ ] Club Coordinators create normal Club member accounts
- [ ] Temporary passwords enforced
- [ ] Firebase ID tokens validated
- [ ] Custom claims assigned correctly & refreshed after role changes

**Role-Based Access Control**
- [ ] Firestore Rules validate `request.auth.token.role`
- [ ] Frontend role checks used only for UX; backend is source of truth
- [ ] Least privilege enforced; users cannot elevate privileges

**Firestore Security Rules**
- [ ] Players read only their own documents
- [ ] Guardians read only linked players
- [ ] Coaches limited to assigned teams
- [ ] School Staff limited to the eligibility collection
- [ ] Admin has full administrative access; writes validated by role

**Data Minimization**
- [ ] No academic grades stored; eligibility uses ENUM only
- [ ] No unnecessary personal information collected
- [ ] Guardian relationship stored separately; audit logs exclude sensitive data

**Offline Support**
- [ ] Firestore persistence enabled; attendance tested offline
- [ ] Automatic sync verified; conflict handling documented

**Notifications**
- [ ] Cloud Functions trigger only on relevant document changes
- [ ] FCM tokens stored securely; sent only to authorized recipients
- [ ] Notification payload excludes sensitive information

**Audit Logging**
- [ ] All critical actions logged; history immutable
- [ ] Actor UID + timestamp recorded; resolution workflow verified

**SOLID Compliance**
- [ ] Views contain no business logic
- [ ] ViewModels contain no Firebase SDK calls
- [ ] Repositories abstract data access; DI used throughout
- [ ] Interfaces enable mock implementations for testing

**Final Release Validation**
- [ ] Authentication & RBAC (custom claims) verified
- [ ] Firestore Rules tested against unauthorized access
- [ ] Offline attendance sync confirmed
- [ ] Eligibility workflow validated without academic-grade storage
- [ ] Push notifications verified end-to-end
- [ ] Dispute lifecycle tested creation → resolution
- [ ] Code review, security review, and production deployment approved
