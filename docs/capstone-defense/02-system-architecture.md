# System Architecture

## Architecture at a glance

```text
SUPER ADMIN → CLUB (SCHOOL | INDEPENDENT) → CLUB COORDINATOR
                                             ↓
                         COACH / PLAYER / GUARDIAN / SCHOOL STAFF
```

Super Admin creates the Club and its one Coordinator. Normal member
provisioning is performed by that Coordinator, and the server derives the
tenant from `request.user.club`.

```text
Flutter presentation (screens/widgets + Riverpod controllers/providers)
        |
Flutter domain (entities + use cases + repository contracts)
        |
Flutter data adapters
  |             |                 |
Firebase Auth   Django REST API   Local sqflite attendance outbox
                      |
        FirebaseAuthentication + DRF role/object/club checks
                      |
        Django views/serializers/services/signals
          |              |                 |
      Django ORM     Firebase Admin/FCM   Supabase Storage REST
          |
 SQLite by default OR PostgreSQL/Supabase when DB_* is configured

Django templates (Coordinator/School Staff) -> session auth -> services/ORM
Django admin (Administrator)              -> session auth -> admin/API/ORM
```

The dependency direction in Flutter is presentation → domain abstractions ← data implementations. `core/di/providers.dart` is the composition root that selects mock or live adapters and injects use cases into Riverpod controllers.

## Technology stack verified in code

| Layer | Technology | Evidence |
|---|---|---|
| Mobile UI | Flutter/Dart, Material, Riverpod | `footpath_cebu/pubspec.yaml`, `lib/presentation/` |
| Mobile state/DI | `flutter_riverpod` | `lib/core/di/providers.dart`, `lib/presentation/providers/` |
| Mobile identity | Firebase Auth | `firebase_auth_repository.dart` |
| Mobile networking | Dart `http` | `lib/data/repositories/api_*.dart` |
| Offline write storage | `sqflite`, connectivity | `attendance_outbox.dart`, `attendance_sync_service.dart` |
| Backend | Django 5.2, DRF 3.16 | `backend/requirements.txt`, `config/settings.py` |
| Backend identity verification | Firebase Admin SDK | `accounts/authentication.py`, `accounts/firebase.py` |
| Web authentication | Django sessions + Axes | `portal/`, `settings.py` |
| Relational persistence | Django ORM; SQLite/PostgreSQL | `settings.py`, model/migration files |
| Push | Firebase Cloud Messaging | `academy/notifications.py`, device token endpoints |
| Optional object storage | Supabase Storage REST | `academy/storage.py` |
| CI | GitHub Actions | `.github/workflows/ci.yml` |

## Layer-by-layer defense map

| Layer | Purpose | Actual files/symbols | Communicates with |
|---|---|---|---|
| Presentation/UI | collect input and render role state | screens/widgets; `_handleSignIn`, `_submit`, `_finalize`, `_save` | Riverpod controllers/providers and Navigator |
| State/controller | loading/data/error and provider invalidation | `presentation/providers/`; `LoginController`, `ScheduleSessionController`, `AttendanceLogController` | domain use cases |
| Business/domain | name actions and hold typed rules/data | `domain/entities`, `domain/usecases`; `SignIn`, `SavePlayerAssessment`, `LogSessionAttendance` | repository interfaces only |
| Repository/data access | translate domain operations to infrastructure | `data/repositories/api_*`, `firebase_auth_repository.dart`, mocks, offline decorator | Firebase, HTTP, sqflite |
| Backend/API | authenticate, authorize, validate, orchestrate | `accounts/authentication.py`, `academy/views.py`, `academy/serializers.py` | services/models/FCM/storage and Flutter JSON |
| Database | relational integrity/query/transactions | `accounts/models.py`, `academy/models.py`, migrations | Django ORM only |
| Authentication | establish identity/session | Firebase Auth repository/Admin verifier; Django portal session views | local `User` mapping and authorization |
| Storage | private player-photo object handling | `academy/storage.py`, portal/admin upload views | Supabase Storage REST and `PlayerProfile.photo_path` |
| External APIs | managed identity/push/object service | Firebase Auth/Admin/FCM, optional Supabase Storage | adapters/helpers; no direct DB call from Flutter |
| AI components | none | no model/service/dependency/endpoint found | not applicable |

## Flutter layers

### Presentation

Screens and widgets collect input and render Riverpod state. Controllers expose async actions and provider invalidation. Important examples:

- `session_bootstrap_screen.dart` restores identity before routing.
- `login_screen.dart` submits sign-in credentials.
- `home_screen.dart` maps the authenticated role to a portal.
- `coach_dashboard_screen.dart`, `schedule_tab_screen.dart`, `progress_screen.dart`, and roster/profile screens form the coach experience.
- `player_dashboard_screen.dart` and `guardian_dashboard_screen.dart` provide role-specific views.
- provider files convert use cases into `AsyncValue`-based UI state.

### Domain

The domain layer contains entities (`Player`, `TrainingSession`, `Attendance`, `Dispute`, and others), repository interfaces, and one-purpose use cases such as `SignIn`, `LogSessionAttendance`, `SavePlayerAssessment`, and `VerifyPlayerPrivacyPin`. It does not import UI widgets or concrete HTTP code.

### Data

Concrete adapters translate domain calls into external operations:

- `FirebaseAuthRepository` combines Firebase sign-in with the Django `/api/auth/me/` authorization/profile call.
- API repositories create Bearer-authenticated HTTP requests and deserialize JSON.
- mock repositories supply deterministic local data when mocks are enabled.
- `OfflineFirstAttendanceRepository` decorates the live attendance repository and queues only network-classified write failures.
- `AttendanceOutbox` persists queued batches and `AttendanceSyncService` replays them.

### Composition and mock/live selection

`core/di/providers.dart` wires repositories, use cases, and controllers. Debug builds default to mocks unless `USE_MOCK=false` is passed. Release builds force the live path. This is useful for UI development, but a defense demo must explicitly launch live mode before claiming server persistence.

## Backend layers

### URL/view boundary

`accounts/urls.py`, `academy/urls.py`, and `portal/urls.py` map HTTP paths. DRF views authenticate, check roles and club/object ownership, call serializers/services, persist models, and form responses. Portal views use Django sessions and forms.

### Serializers/forms

DRF serializers validate JSON input and shape JSON output. Django forms validate portal workflows and uploads. A critical defense point: the server derives trusted fields such as actor, player identity, and club from the authenticated user rather than accepting those decisions from the client.

### Services and signals

- `accounts/services.py` handles account provisioning and Firebase compensation.
- `accounts/services.py::provision_player` is the single Player aggregate path.
- `portal/services.py` derives account creation from the authenticated coordinator’s club.
- `academy/pin_service.py` provides PIN verification, failure counting, and lockout.
- `academy/player_unlock.py` creates and verifies short-lived signed unlock tokens.
- `academy/notifications.py` sends FCM messages.
- `academy/signals.py` creates eligibility history/audit records and schedules notifications after commit.
- `academy/storage.py` mediates private Supabase Storage access.

### Models and persistence

`accounts/models.py` owns `Club`, the custom `User`, and `GuardianLink`. `academy/models.py` owns the football and safeguarding domain. Migrations are the executable schema history. Django is the source of truth regardless of whether its database engine is local SQLite or PostgreSQL hosted by Supabase.

## Authentication versus authorization

These are deliberately separate:

1. Firebase Auth validates the email/password and issues an ID token.
2. Flutter sends that token in `Authorization: Bearer <token>`.
3. `FirebaseAuthentication` verifies signature, expiry, and revocation using Firebase Admin.
4. Django locates an active local user by Firebase UID.
5. Django requires a club for non-admin users.
6. Endpoint role checks, club filters, object ownership, and guardian links decide what that user may do.

The token proves identity; it does not by itself grant academy permissions. Django’s local `User.role`, `User.club`, linked records, and endpoint logic grant access.

## Role-to-interface routing

```text
SessionBootstrapScreen / LoginScreen
              |
           HomeScreen
       /         |          \
   COACH       PLAYER      GUARDIAN
     |            |            |
CoachPortal   PlayerPortal  GuardianPortal

ADMIN -> Django admin/admin API
COORDINATOR -> Django portal
SCHOOL_STAFF -> Django portal
```

Flutter uses direct `Navigator`/`MaterialPageRoute` transitions and tab shells rather than a named-route package.

## Data topology and trust boundaries

### Trusted server boundary

The backend holds Firebase Admin credentials, optional Supabase service-role credentials, Django’s signing secret, and database credentials. None should be exposed to Flutter. The local workspace contains ignored environment/service-account files; this reviewer intentionally records no values.

### Mobile boundary

The mobile client holds a Firebase user session and receives Django data. Client validation improves usability, but all important authorization and data integrity must remain server-enforced because mobile code and requests can be modified.

### Database boundary

Relational foreign keys, one-to-one relations, unique constraints, and transactions supplement application checks. There are no Supabase RLS policies in this design because Flutter never accesses the database directly.

## Key architectural decisions and tradeoffs

| Decision | Benefit | Tradeoff/risk |
|---|---|---|
| Firebase identity + Django authorization | Managed identity with domain-controlled RBAC and tenancy | Two identity records must stay synchronized |
| Clean/domain layers in Flutter | Testable use cases and replaceable adapters | More files/indirection for a capstone-sized app |
| Server-only Supabase access | Credentials and rules remain centralized | Backend is a required hop and potential bottleneck |
| Relational model/history | Constraints, joins, transactions, auditable change records | Schema migrations and careful deletion behavior are required |
| Offline queue only for attendance writes | Protects the field’s most connectivity-sensitive operation | Other screens still depend on live reads/writes; conflict policy is simple last-write-wins |
| Riverpod DI with mocks | Fast isolated UI tests and demos | Debug defaults can accidentally show mock rather than live data |
| Signals for eligibility history | Every model save can produce consistent history | Side effects are less visible than an explicit service and need transaction awareness |

## Important architecture files

1. `footpath_cebu/lib/main.dart` — application bootstrap.
2. `footpath_cebu/lib/core/di/providers.dart` — Flutter composition root.
3. `footpath_cebu/lib/data/repositories/firebase_auth_repository.dart` — identity/profile bridge.
4. `footpath_cebu/lib/data/repositories/offline_first_attendance_repository.dart` — resilience decorator.
5. `backend/config/settings.py` — security, database, middleware, REST configuration.
6. `backend/accounts/authentication.py` — Firebase-to-Django authentication.
7. `backend/accounts/models.py` — clubs, users, guardian links.
8. `backend/accounts/services.py` — safe account provisioning.
9. `backend/academy/models.py` — core domain schema.
10. `backend/academy/views.py` — API role/object/workflow boundary.
11. `backend/academy/serializers.py` — validation and API contracts.
12. `backend/academy/pin_service.py` and `player_unlock.py` — household privacy control.
13. `backend/academy/signals.py` — eligibility history/audit side effects.
14. `backend/portal/services.py` and `views.py` — coordinator/staff workflows.

## Architectural answer to memorize

> Flutter is a layered client: UI and Riverpod controllers call domain use cases, which depend on repository interfaces implemented by Firebase, Django API, mock, or local-outbox adapters. Firebase proves identity. Django verifies the token, enforces roles and club/object scope, and persists through its ORM. SQLite is the default database; production can use PostgreSQL, including Supabase-hosted PostgreSQL. Supabase is not an alternative authorization layer in this implementation.
