# FootPath-Cebu

Youth Sports Academy Portal — Capstone Project.

**Stack:** Flutter (MVVM) · Firebase Authentication · Django REST backend · Firebase Cloud Messaging (FCM)

---

## Project layout

```
footpath_cebu/   Flutter mobile app (Coach, Player, Guardian) — MVVM
backend/         Django REST API + admin console (account provisioning, RBAC)
docs/            Requirements, setup, and detailed execution notes
```

### Flutter MVVM structure (`footpath_cebu/lib/`)

The app follows a strict MVVM boundary: **View → ViewModel → Repository interface → Repository implementation**. Views never touch Firebase or HTTP directly; ViewModels hold only business logic; repositories abstract all data access.

Precisely, this is **MVVM + the Repository pattern** — a pragmatic layered architecture, *not* full Clean Architecture (there is deliberately no separate use-case / interactor layer at this scope). SOLID shows up concretely: ViewModels depend on **narrow** repository interfaces (`SquadRepository`, `PlayerProfileRepository`, `LinkedPlayersRepository` — Interface Segregation + Dependency Inversion) resolved by `service_locator.dart`, and provider-specific concerns (Firebase, HTTP, JSON) stay in the data layer so the presentation layer is provider-agnostic.

```
lib/
  models/          Immutable data classes (Player, Attendance, UserProfile) — no I/O, no UI
  viewmodels/      ChangeNotifier state holders (CoachDashboardViewModel) — business logic only
  repositories/    Interfaces (PlayerRepository) + implementations:
                     mock_*  → in-memory data for UI development
                     api_*   → live Django REST backend (Firebase ID-token auth)
                   service_locator.dart wires mock vs. live via initMock()/initFirebase()
  widgets/         Reusable UI (PlayerCard — the FUT-style roster card)
  screens/         Views (CoachDashboardScreen, LoginScreen, HomeScreen)
```

**Feature reference — Coach dashboard "Active Squad Roster":**
`CoachDashboardScreen` (View) → `CoachDashboardViewModel` (loading/search/counts) → `PlayerRepository` → `MockPlayerRepository` / `ApiPlayerRepository`. Run against mock data with `ServiceLocator.initMock()` in `main.dart`.

Tests live in `footpath_cebu/test/` (model round-trips, ViewModel filtering/error paths, dashboard widget tests). Run with `flutter test`.

---

# 2-Week Execution Plan

## 1. Comprehensive Workflow Architecture

### A. Account Provisioning & Linking
Only the **Admin** can create accounts — there is **no public registration**.

```
Admin UI → Admin ViewModel → IUserRepository → Firebase Admin SDK
  ├── Create Firebase Auth user
  ├── Assign custom claims (role=PLAYER)
  └── Generate temporary password → Firestore users/, players/
```

- **UI only submits:** Name, Email, Role, Age Tier
- **UI never submits:** Claims, Permissions, UID
- Only the backend can assign roles. Firestore Rules verify `request.auth.token.role`, **not** a `role` field inside the document.
- Guardians are created the same way (`role=GUARDIAN`) and linked via `guardian_links/{guardianUid_playerUid}`.

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
eligibility/{playerUid} { status: ELIGIBLE | NOT_ELIGIBLE | PENDING | ACADEMIC_WARNING, updatedBy, updatedAt, remarks }
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
- [ ] Admin SDK creates all users
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
