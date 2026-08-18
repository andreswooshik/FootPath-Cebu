# Code Explanation and Important Files

## How to explain the codebase

The repository has two main applications. Flutter is the role-based mobile client; Django is the API, web portal, admin console, authorization authority, and data owner. The cleanest oral explanation follows one request through Flutter’s presentation, domain, and data layers, then through Django authentication, views, serializers, models, and optional side effects.

## Twenty high-value files/directories

| # | Path | Responsibility | Why it matters in defense |
|---|---|---|---|
| 1 | `footpath_cebu/lib/main.dart` | Firebase initialization and first screen | Proves the real entry point and bootstrap behavior |
| 2 | `footpath_cebu/lib/core/di/providers.dart` | Riverpod dependency composition and mock/live selection | Explains dependency inversion and demo mode |
| 3 | `footpath_cebu/lib/presentation/screens/session_bootstrap_screen.dart` | Restores an existing session | Shows that routing waits for Django authorization, not only cached Firebase state |
| 4 | `footpath_cebu/lib/presentation/screens/home_screen.dart` | Routes by role | Defines the three implemented mobile portals |
| 5 | `footpath_cebu/lib/data/repositories/firebase_auth_repository.dart` | Firebase sign-in plus Django profile lookup | The bridge between identity and domain authorization |
| 6 | `footpath_cebu/lib/domain/` | Entities, contracts, use cases | Demonstrates clean dependency boundaries |
| 7 | `footpath_cebu/lib/data/repositories/api_player_repository.dart` | Squad/profile/assessment/position HTTP adapter | Central player-development data path |
| 8 | `footpath_cebu/lib/data/repositories/api_attendance_repository.dart` | Attendance HTTP adapter and error classification | Basis of online/offline behavior |
| 9 | `footpath_cebu/lib/data/repositories/offline_first_attendance_repository.dart` | Decorates attendance writes with queue fallback | One of the strongest advanced engineering features |
| 10 | `footpath_cebu/lib/data/local/attendance_outbox.dart` | sqflite queue schema and persistence | Makes the resilience claim concrete |
| 11 | `footpath_cebu/lib/data/local/attendance_sync_service.dart` | Sequential replay and retry metadata | Explains synchronization and conflict policy |
| 12 | `backend/config/settings.py` | Database, REST, middleware, CORS, production hardening | The security and deployment control center |
| 13 | `backend/accounts/models.py` | `Club`, custom `User`, `GuardianLink` | Defines tenancy, roles, and family links |
| 14 | `backend/accounts/authentication.py` | Verifies Firebase tokens and maps local users | Server trust boundary |
| 15 | `backend/accounts/services.py` | Firebase/Django account provisioning | Handles cross-system consistency and rollback |
| 16 | `backend/academy/models.py` | Core football, safeguarding, audit, and notification models | Main relational domain |
| 17 | `backend/academy/serializers.py` | API input validation and response shapes | Defines the client/server contract |
| 18 | `backend/academy/views.py` | API workflows and authorization | Main endpoint implementation and risk surface |
| 19 | `backend/academy/pin_service.py` + `player_unlock.py` | Hashed PIN, lockout, signed unlock token | Key privacy mechanism |
| 20 | `backend/portal/services.py` + `portal/views.py` | Coordinator/staff account and eligibility workflows | Explains non-mobile operational users |

## Source-file defense cards

Each card makes the input, processing, output, dependencies, and spoken defense explicit.

### 1. `footpath_cebu/lib/main.dart`

- **Important classes/functions:** `main()`, `FootPathApp.build()`, `_SetupErrorScreen`.
- **Input:** platform launch and Firebase options.
- **Processing:** initialize Flutter/Firebase, catch setup failure, create Riverpod root and `MaterialApp`.
- **Output:** bootstrap screen or setup-error UI.
- **Dependencies:** Firebase Core/options, Riverpod, app theme, `SessionBootstrapScreen`.
- **Defense:** “This is the composition entry point. It completes plugin initialization before rendering and converts configuration failure into a visible controlled screen.”

### 2. `footpath_cebu/lib/core/di/providers.dart`

- **Important symbols:** repository, use-case, outbox, sync, and token-store providers.
- **Input:** build configuration (`ApiConfig.useMock`) and dependent provider refs.
- **Processing:** selects mock/live adapters and composes use cases/controllers around repository contracts.
- **Output:** lazy injectable dependencies.
- **Dependencies:** all domain contracts/use cases and data adapters.
- **Defense:** “This file is the composition root; it proves dependency inversion because screens request abstractions/use cases while this boundary chooses infrastructure.”

### 3. `presentation/screens/session_bootstrap_screen.dart`

- **Important class/functions:** `SessionBootstrapScreen`, `initState()`, `_restore()`, `build()`.
- **Input:** existing Firebase auth state through restore use case.
- **Processing:** await local identity plus Django reauthorization, then start device/sync services.
- **Output:** profile, login decision, or retryable error.
- **Dependencies:** restore/register/sync providers, `HomeScreen`, `LoginScreen`.
- **Defense:** “It prevents a cached Firebase session from bypassing the current Django role/account state.”

### 4. `presentation/screens/login_screen.dart` + `presentation/providers/auth_controllers.dart`

- **Important functions/classes:** `_handleSignIn()`, `LoginController.signIn()`, `sendResetEmail()`.
- **Input:** email/password text controllers.
- **Processing:** manage loading/error, invoke auth use case, start device/sync on success.
- **Output:** `UserProfile?`, role navigation, or visible error.
- **Dependencies:** auth use cases, Riverpod, `HomeScreen`.
- **Defense:** “The widget gathers input; the controller owns async state; the repository owns Firebase/HTTP. That keeps UI free of protocol logic.”

### 5. `data/repositories/firebase_auth_repository.dart`

- **Important methods:** `restoreSession()`, `signInAndFetchProfile()`, `signOut()`, password reset/change/reauthenticate.
- **Input:** credentials or current Firebase user.
- **Processing:** Firebase Auth operation, ID-token retrieval, Django `/api/auth/me/`, exception translation.
- **Output:** typed `UserProfile`, void success, or `AuthException`.
- **Dependencies:** Firebase Auth, HTTP, `ApiConfig`, `UserProfile`.
- **Defense:** “It bridges managed identity and the application’s server-authoritative profile; successful Firebase login alone is not enough.”

### 6. `data/repositories/api_player_repository.dart`

- **Important methods:** `fetchSquad`, `fetchLinkedPlayers`, `fetchPlayerDetails`, `fetchMyProfile`, `savePosition`, `saveAssessment`.
- **Input:** player ID, position, ratings/notes, optional unlock token.
- **Processing:** attach Firebase token, send GET/PUT JSON, decode responses.
- **Output:** `Player` or `List<Player>`; typed repository exception.
- **Dependencies:** Firebase Auth, HTTP, `Player.fromJson`, `ApiConfig`.
- **Defense:** “This adapter translates domain player operations into authenticated Django endpoints without giving widgets transport knowledge.”

### 7. `data/repositories/offline_first_attendance_repository.dart`

- **Important methods:** `saveSessionAttendance`, `fetchAttendanceForSession`, `fetchAttendanceForPlayer`.
- **Input:** session ID and typed records; current owner UID callback.
- **Processing:** try live repository; on network write exception enqueue complete batch; optionally read latest queued batch.
- **Output:** server records, optimistic queued records, or error.
- **Dependencies:** live attendance contract and `AttendanceOutbox`.
- **Defense:** “It is a decorator that adds resilience only for the attendance operation, and only network-classified writes become offline success.”

### 8. `data/local/attendance_outbox.dart` + `attendance_sync_service.dart`

- **Important methods:** queue CRUD methods and sync `start`/replay routine.
- **Input:** owner UID, session ID, serialized attendance records.
- **Processing:** persist sqflite row; load current-owner rows oldest first; replay sequentially; delete success or record retry failure.
- **Output:** durable pending work and eventual live save.
- **Dependencies:** sqflite, connectivity, live attendance repository, Firebase owner.
- **Defense:** “Owner scoping protects shared devices and sequential replay preserves full-batch ordering; the conflict policy is deliberately simple last-write-wins.”

### 9. `presentation/screens/log_attendance_screen.dart`

- **Important functions:** `_mark`, `_setEffort`, `_setNote`, `_finalize`, `_seedOnce`.
- **Input:** coach marks, effort, note, current session/roster.
- **Processing:** enforce open window/unmarked confirmation and strip per-session evaluation from non-present marks.
- **Output:** `List<Attendance>` passed to controller; pop/error feedback.
- **Dependencies:** attendance/squad providers, assessment screen, domain entities.
- **Defense:** “It owns transient form state, while the controller/repository/backend own persistence and authority.”

### 10. `backend/config/settings.py`

- **Important configuration:** installed apps/middleware, database selection, REST auth, password hashing, CORS, cache, production TLS/cookies/HSTS.
- **Input:** environment values and testing/debug flags.
- **Processing:** validate production requirements and select SQLite/PostgreSQL/cache/security options.
- **Output:** Django runtime configuration.
- **Dependencies:** Django, DRF, Axes, CORS, Firebase initialization paths.
- **Defense:** “This is the operational security boundary: it changes engines and hardening by environment while keeping Django as the data authority.”

### 11. `backend/accounts/authentication.py`

- **Important class/method:** `FirebaseAuthentication.authenticate()`.
- **Input:** HTTP Bearer token.
- **Processing:** Firebase Admin verification with revocation, UID extraction, active local user lookup, non-admin club gate.
- **Output:** `(user, token)` for DRF or authentication rejection.
- **Dependencies:** Firebase Admin wrapper and `accounts.User`.
- **Defense:** “A token proves identity only after server verification; the local user supplies the trusted role and tenant.”

### 12. `backend/accounts/services.py`

- **Important functions:** `link_or_create_firebase_user`, `provision_user`, `provision_managed_player`, `change_role`, `provision_web_user`.
- **Input:** trusted email/names/role/club and optional password.
- **Processing:** coordinate Firebase and Django records, use transactions, compensate newly created Firebase identity on DB failure.
- **Output:** user and controlled temporary-credential metadata or `ProvisioningError`.
- **Dependencies:** Firebase Admin wrapper, `User`, Django transactions.
- **Defense:** “This service concentrates a cross-system invariant that cannot be safely implemented in a view alone.”

### 13. `backend/academy/models.py`

- **Important classes:** `PlayerProfile`, `TrainingSession`, `Attendance`, `SessionConfirmation`, `EligibilityHistory`, `InjuryRecord`, `Dispute`, `DisputeResponse`, `AuditLog`, `DeviceToken`, `PlayerPrivacyPin`.
- **Input:** validated values from views/serializers/services/signals.
- **Processing:** relational mapping, defaults, relationships, uniqueness/deletion behavior, limited model methods.
- **Output:** authoritative persistent domain rows/querysets.
- **Dependencies:** custom `User`, Django ORM, enum choices.
- **Defense:** “The model layer expresses cardinality and history: one player profile/PIN, unique attendance/RSVP pairs, and appendable eligibility/dispute records.”

### 14. `backend/academy/serializers.py`

- **Important classes:** player, assessment, position, attendance, session, injury, dispute, eligibility, and age-tier serializers.
- **Input:** request JSON or model/queryset instances.
- **Processing:** validate types/ranges/choices and map flat model fields to client-friendly nested JSON.
- **Output:** `validated_data` for saves or response `.data`.
- **Dependencies:** academy/account models and DRF.
- **Defense:** “Serializers are the API contract and authoritative payload validator; server-derived club/actor fields are deliberately outside ordinary client control.”

### 15. `backend/academy/views.py`

- **Important classes:** `SquadListView`, `PlayerAssessmentView`, `SessionAttendanceView`, training/progress/PIN/confirmation/dispute/injury/device/photo views.
- **Input:** authenticated request, path/query IDs, serializer data, unlock header.
- **Processing:** role, club, ownership/link/PIN checks; transactional queries; audit/on-commit side effects.
- **Output:** DRF JSON/204 or validation/auth errors.
- **Dependencies:** authentication defaults, models, serializers, notification/PIN/storage helpers.
- **Defense:** “This is the backend workflow boundary. It never trusts a Flutter role/club and resolves every protected object against the verified request user.”

### 16. `backend/academy/pin_service.py` + `player_unlock.py`

- **Important functions:** `set_pin`, `verify_pin`, `reset_pin`, `issue_player_unlock`, `require_player_unlock`.
- **Input:** player, PIN candidate/current PIN, authenticated user/player IDs.
- **Processing:** format/hash checks, row lock, failure/lock state, Django signing/max-age/binding.
- **Output:** PIN status or signed temporary token/errors.
- **Dependencies:** Django hashers, transactions, signing, PIN model.
- **Defense:** “The PIN is a second privacy layer: it is hashed and throttled, and success becomes a short-lived tamper-evident grant rather than a client boolean.”

### 17. `backend/academy/signals.py` + `notifications.py`

- **Important functions:** `stash_previous_eligibility`, `fire_eligibility_changed`, `notify_*` helpers.
- **Input:** saved profile/session/assessment and recipient relationships/device tokens.
- **Processing:** compare old/new eligibility, create history/audit, defer FCM to commit, fan out/clean invalid tokens.
- **Output:** persistent change history and best-effort push.
- **Dependencies:** ORM transaction lifecycle, Firebase Admin messaging.
- **Defense:** “The on-commit boundary prevents a push from advertising rolled-back data; the mobile receive experience is still partial.”

### 18. `backend/portal/services.py` + `portal/views.py`

- **Important functions:** `provision_club_coordinator`, `create_club_account`, `provision_player`, `set_player_eligibility`, link/unlink guardian, and protected Club/Coordinator API views.
- **Input:** session-authenticated forms and coordinator/staff identity.
- **Processing:** form/role/club validation, trusted provisioning, eligibility updates, web redirects/messages.
- **Output:** users/profiles/links/status changes and rendered portal feedback.
- **Dependencies:** account services, academy models/signals, Django forms/sessions/CSRF.
- **Defense:** “These modules serve operational roles that are deliberately not given full mobile portals and always derive tenant scope from the session user.”

## Flutter code mechanics

### Entities

Entities are UI-independent data structures. `Player` combines identity, profile data, ratings, eligibility, notes, and optional photo URL. `TrainingSession`, `Attendance`, `InjuryRecord`, `Dispute`, `EligibilityChange`, and other entities convert JSON into typed values. They are the vocabulary passed between use cases and screens.

### Repository contracts

Interfaces under `domain/repositories/` state what the application needs without deciding how it is performed. For example, the attendance contract exposes session/player reads and a batch log operation. This allows live, mock, and offline-decorated implementations to satisfy the same use case.

### Use cases

Use cases are intentionally thin: they name an application action and delegate to a contract. This may appear verbose, but it isolates screen logic from protocols and makes future policy changes testable in one place. Examples include `GetSquad`, `SavePlayerAssessment`, `ScheduleTrainingSession`, `ConfirmSession`, and `RaiseDispute`.

### Riverpod controllers/providers

Providers obtain dependencies from the composition root. Controllers guard duplicate submissions, set loading state, catch errors, and invalidate read providers after successful mutation. Async read providers call use cases and let widgets render loading, data, or error states.

### Concrete repositories

API repositories:

1. obtain the current Firebase ID token;
2. build the Django URL from `ApiConfig`;
3. send JSON and Bearer headers;
4. classify status/network errors;
5. decode the response into domain entities.

Many adapters use a common pattern but are separate files to retain domain-specific parsing. A future refactor could centralize timeout, error-body, and token-header behavior.

### Navigation

The app does not use a declarative/named routing library. `HomeScreen` uses role conditions, while feature screens push `MaterialPageRoute` instances. Portal shells retain bottom-tab state with an `IndexedStack`.

## Django code mechanics

### Models and relationships

Models hold both data and some invariant-adjacent behavior. `User` extends `AbstractUser` and adds Firebase UID, role, and club. `PlayerProfile` is one-to-one with a player-role user. Foreign-key deletion policies are selected according to history: attendance retains a null session after session deletion; audit actors can be null; confirmations disappear with their session.

### Authentication and permissions

`FirebaseAuthentication.authenticate` parses the Bearer token, verifies it with revocation checking, maps UID to a local user, and rejects inactive or improperly unscoped accounts. Permission classes/decorators provide broad role gates, then views add object and club checks. Security depends on this combination.

### Serializers

Serializers reject malformed choices and ranges and flatten/unflatten ratings between the JSON contract and profile fields. They prevent a client from setting trusted server fields. The assessment serializer uses 0–99, while the planning requirements mention a 1–10 rubric; the implementation is authoritative unless the project specification is changed.

### Views

Views are fairly large and contain many use-case-specific checks. Common patterns include:

- filter a queryset by `request.user.club_id`;
- require a role before mutation;
- identify the player from `request.user` for player-owned operations;
- require a guardian link plus signed unlock token;
- run multi-row updates inside `transaction.atomic()`;
- record an `AuditLog` and schedule FCM on commit.

Large `academy/views.py` is functional but carries maintainability risk; service extraction and reusable club-scoped permission/query helpers would reduce duplication.

### Portal

Portal users authenticate with Django sessions rather than Firebase mobile tokens. Django forms, role decorators, CSRF middleware, Axes lockout, and server-rendered templates implement coordinator and school-staff operations. Club assignment comes from the logged-in coordinator, not a free client field.

## Representative code trace: assessment save

1. `EditPerformanceDataScreen._save()` reads rating controls and coach notes.
2. `EditPerformanceController.submit()` enters loading state.
3. `SavePlayerAssessment.call()` invokes `PlayerRepository.saveAssessment`.
4. `ApiPlayerRepository` sends a `PUT` request with ratings/notes.
5. Django `FirebaseAuthentication` verifies the caller.
6. The assessment view requires coach role and same club.
7. The serializer validates every rating in 0–99.
8. The profile fields and notes are saved.
9. An audit event is recorded and FCM is scheduled after commit.
10. `PlayerSerializer` returns the updated player.
11. Flutter converts JSON to `Player`, invalidates squad state, and closes with a success result.

## Representative code trace: guardian privacy

1. The linked-player endpoint returns only redacted selector data.
2. `PlayerPrivacyGate` requests a PIN for the selected player.
3. The verify controller calls the repository and Django endpoint.
4. `verify_pin` locks the PIN row, checks `locked_until`, verifies the Argon2-backed password hash, updates failure state, and returns success/failure.
5. Django signs a `{user, player}` token; it does not send the PIN/hash.
6. Flutter stores the token only in memory.
7. Detail adapters attach `X-Player-Unlock`.
8. Django verifies token age/binding and the active guardian link before returning data.

## Representative code trace: offline attendance

1. The use case calls the decorated attendance repository.
2. The decorator attempts the live API first.
3. HTTP connectivity failures become `AttendanceNetworkException`.
4. The decorator serializes the full batch to `outbox_attendance`, including the Firebase owner UID.
5. It returns optimistic records so the UI can finish.
6. Sync later loads only that owner’s queued records and replays oldest first.
7. Success deletes the row; failure stores retry count/error and stops to preserve ordering.

## OOP concepts visible in the project

- **Encapsulation:** repositories hide HTTP/Firebase/sqlite details; models encapsulate fields and behavior.
- **Abstraction:** repository interfaces and use-case APIs expose capabilities rather than transport details.
- **Polymorphism:** mock, API, and offline-first repository implementations satisfy the same contracts.
- **Composition:** `OfflineFirstAttendanceRepository` wraps rather than subclasses the live repository.
- **Dependency inversion:** domain code depends on repository abstractions; `providers.dart` supplies concrete adapters.
- **Single responsibility (approximate):** entities, use cases, adapters, controllers, and views have distinct roles, although `academy/views.py` has grown broad.

## Five code-level risks to admit

1. Player provisioning is centralized in `provision_player`; it requires an active Club and creates the User/Profile/optional link transactionally.
2. Generic admin user creation excludes `PLAYER`, preventing a User-only Player record.
3. The squad-progress admin comment suggests cross-club access, but its filter uses the admin’s normally-null club.
4. Session confirmation submission catches errors without displaying them to the user.
5. Training start/end values are stored as strings and no start-before-end validation was found.

These are concrete improvement targets, not reasons to claim the entire architecture is insecure.

## Ten-second code explanation

> Flutter screens call Riverpod controllers and domain use cases. Repository interfaces keep the domain independent; API, mock, Firebase, and offline adapters implement them. Django verifies Firebase identity, checks role and club/object scope, validates with serializers, and persists relational models. Providers invalidate after writes so the UI reloads authoritative data.
