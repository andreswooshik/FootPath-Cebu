# Technical Glossary

## Core terms: simple and technical definitions

| Term | Simple explanation | Technical definition in this repository |
|---|---|---|
| Flutter | Toolkit used to build the mobile screens | Dart UI framework whose widgets render the coach/player/guardian clients |
| Dart | Language used by the mobile app | Statically typed, async-capable language compiling the Flutter client |
| Widget | One piece of Flutter UI | Immutable configuration in the element/render tree; screens compose widgets and rebuild from state |
| StatelessWidget | UI with no mutable state inside it | A widget whose `build` depends on constructor/context/provider values |
| StatefulWidget | UI that remembers local values | Widget paired with a `State` object using lifecycle methods and `setState`, used for forms |
| ConsumerWidget | Widget that reads Riverpod | Flutter/Riverpod widget whose `build` receives `WidgetRef` and rebuilds for watched providers |
| Future | A value available later | Dart representation of one asynchronous result/error from Firebase, HTTP, or sqflite |
| async/await | Write later-finishing work in order | Language syntax that yields to the event loop and resumes when a `Future` completes |
| Riverpod | Manages dependencies and screen state | Provider graph using `ProviderScope`, `FutureProvider`, `Notifier`, and `AsyncNotifier` |
| Provider | Named source of a dependency/value | Lazy reactive definition watched/read through `WidgetRef`; some are auto-disposed/family-keyed |
| State management | Keeps UI synchronized with data | Controllers/providers expose loading/data/error and invalidate reads after mutations |
| Model/entity | Typed representation of system data | Immutable Dart objects such as `Player`/`Attendance`; Django models are persistent ORM entities |
| Repository pattern | Hides where data comes from | Domain interfaces implemented by API/mock/offline adapters |
| Use case | One named application action | Domain class such as `SavePlayerAssessment` delegating to repository contract |
| API | Controlled way for programs to communicate | Authenticated Django REST endpoints under `/api/` |
| REST | HTTP style using resources/methods/statuses | GET/POST/PUT/DELETE DRF views exchanging JSON and standard codes |
| JSON | Text format passed between app and server | Maps/lists encoded by Dart repositories and validated/serialized by DRF |
| CRUD | Create, read, update, delete | Implemented for sessions/injuries and selected domain records with role restrictions |
| Django | Server framework | Python web framework supplying ORM, sessions, middleware, admin, forms, migrations |
| DRF | Toolkit for Django APIs | Django REST Framework authentication, permissions, serializers, API views, responses |
| SQLite | Small file-based relational database | Django default/test engine; separately sqflite stores only mobile outbox rows |
| PostgreSQL | Server-grade relational database | Optional Django engine, including a Supabase-hosted instance |
| Supabase | Hosted infrastructure option | PostgreSQL and private object storage here; not client auth/RLS |
| Primary key | Unique row identifier | Django-generated `id` or one-to-one key used in tables/endpoints |
| Foreign key | Link from one row to another | Club/user/player/session/actor relations with `CASCADE` or `SET_NULL` policies |
| Authentication | Proves identity | Firebase ID token verification for mobile; Django sessions for web |
| Authorization | Decides allowed actions/data | Django role + club + ownership/link/PIN checks after authentication |
| RBAC | Permissions based on role | Six `Roles` values checked in permissions/views, supplemented by object scope |
| RLS | Database directly filters rows by policy | Not used because Flutter never connects to Supabase database directly |
| JWT/ID token | Signed proof carried by the client | Firebase ID token verified/revocation-checked by Firebase Admin; do not assume arbitrary JWT claims authorize roles |
| Session | Remembered authenticated state | Firebase SDK state on mobile or signed Django session cookie on portal/admin |
| Validation | Reject bad input/state | UI checks plus authoritative serializers/forms/views and selected DB constraints |
| MVVM | Separates view, state logic, and models | Some source comments use Model/ViewModel-style terminology, but the broader verified structure is presentation/domain/data with Riverpod controllers |
| BLoC | Event/state Flutter pattern | Not used in this repository; Riverpod is the actual state system |

## Extended repository-specific terms

| Term | FootPath Cebu meaning |
|---|---|
| Abstract class/interface | A Dart repository contract specifying operations without choosing HTTP, mock, or local storage |
| AbstractUser | Django base user extended with Firebase UID, role, and club |
| Adapter | Concrete code translating a domain contract to Firebase, HTTP, mocks, sqflite, or storage REST |
| Admin | Global operational role mainly served by Django admin/admin API |
| Aggregate | Deterministic count/average computed by Django ORM; not AI |
| API | Django REST endpoints used by Flutter and some admin operations |
| API base URL | Configured Django origin used by live Flutter repositories |
| Argon2 | Memory-hard password hashing algorithm configured first for Django/PIN hashes |
| Attendance outbox | Local sqflite queue of unsent complete attendance batches |
| Authentication | Proving who a user is; Firebase for mobile, Django sessions for portal/admin |
| Authorization | Deciding what the identified user may access; enforced by Django roles, clubs, links, and objects |
| Bearer token | Firebase ID token placed in the HTTP `Authorization` header |
| Cache | Temporary server data store; production rate limiting requires shared Redis |
| CASCADE | Foreign-key behavior deleting dependent rows when the parent is deleted |
| CI | GitHub Actions automation for tests, analysis, and deployment checks |
| Clean architecture | Dependency organization in which domain policy does not depend on UI or infrastructure |
| Club scope | Tenant boundary restricting most records to the authenticated user’s club |
| Composition | Building behavior from collaborating objects; offline attendance wraps live repository + outbox |
| Composition root | `core/di/providers.dart`, where concrete Flutter dependencies are assembled |
| Compensation | Undoing a newly created Firebase identity when its corresponding DB operation fails |
| CSP | Content Security Policy headers reducing browser script/style injection risk |
| CSRF | Cross-site request forgery; Django middleware/tokens protect session forms |
| Database constraint | Schema rule such as unique guardian/player or player/session pairs |
| Deep link | A notification/URL route directly to an app screen; not implemented for pushes here |
| Dependency injection | Supplying repositories/use cases externally through Riverpod providers |
| Dependency inversion | Domain depends on repository abstractions, not HTTP/Firebase implementations |
| Device token | FCM registration token associated with a Django user/device |
| Django ORM | Object-relational mapper and authoritative persistence interface |
| Domain entity | Typed application value such as `Player`, `Attendance`, or `TrainingSession` |
| DRF | Django REST Framework: API authentication, permissions, serializers, responses |
| Eligibility | Current playable/academic eligibility status; it is not a stored grade |
| Entity serialization | Conversion between JSON and typed Dart entities/DRF output |
| FCM | Firebase Cloud Messaging for server-initiated push delivery |
| Firebase Admin SDK | Server SDK that verifies ID tokens, provisions users, and sends FCM |
| Firebase Auth | Managed mobile email/password identity provider |
| Firebase UID | Stable identity key linking Firebase account to Django `User` |
| Foreign key | Relational reference such as attendance → player/session |
| Foreground listener | Mobile callback for pushes received while app is open; not found in current Flutter code |
| GuardianLink | Relational authorization link from a guardian user to a player user |
| Hash | One-way representation used for password/PIN verification |
| HSTS | Browser policy requiring future HTTPS connections in production |
| HTTP status | Server response category used by adapters to classify success/auth/validation/error |
| ID token | Signed Firebase identity assertion verified by Django |
| IndexedStack | Flutter widget retaining tab children/state while one is visible |
| Invariant | Condition that should always hold, such as player-role user having a profile and club |
| JSON | Wire format between Flutter API repositories and Django serializers |
| Last-write-wins | Simple conflict result where later replayed complete attendance state replaces earlier state |
| Migration | Versioned Django schema change under each app’s `migrations/` |
| Mock repository | In-memory/deterministic adapter for development and tests |
| Multi-tenancy | One deployment isolates multiple clubs using club relationships and filters |
| Object permission | Access decision about a specific player/session/injury, beyond broad role |
| `on_commit` | Django transaction callback used so notification occurs only after successful commit |
| One-to-one | Unique relation, for example a player user to one `PlayerProfile` |
| OOP | Organizing state/behavior using entities, interfaces, implementations, composition, and encapsulation |
| Outbox pattern | Persist work locally/transactionally for later reliable delivery; used on mobile attendance |
| Pagination | Loading data in pages; not implemented for local roster filtering |
| PIN unlock token | Django-signed ten-minute proof of successful guardian household PIN verification |
| Polymorphism | Treating API/mock/offline repository implementations through one interface |
| PostgreSQL | Production-capable relational engine selectable by Django settings |
| Provider | Riverpod definition that constructs dependencies or exposes reactive state |
| Proxy model | Django model sharing an existing table; `PlayerEligibility` adds admin behavior without a table |
| RBAC | Role-based access control using six Django roles |
| Reauthentication | Asking Firebase for credentials again to prove recent identity before sensitive reset |
| Repository | Boundary exposing domain data operations and hiding the data source |
| Revocation check | Firebase Admin validation that rejects explicitly revoked sessions/tokens |
| Riverpod | Flutter dependency and reactive state-management library |
| RLS | Database row-level security; not used because clients do not query Supabase directly |
| Serializer | DRF component validating input and converting model/domain data to JSON |
| Session auth | Cookie-backed Django login used by coordinator/staff/admin web interfaces |
| Signed URL | Time-limited URL for reading a private Supabase Storage object |
| Signal | Django callback around model save; used for eligibility history/notifications |
| Source of truth | Django’s local user authorization and ORM data, not client roles or Firebase claims |
| `sqflite` | Flutter SQLite plugin used for the attendance outbox |
| SQLite | Default local/test relational database for Django; also separate mobile outbox engine |
| Status code | HTTP outcome such as 200/201, 400, 401, 403, or 5xx |
| Supabase | Optional hosted PostgreSQL/private storage infrastructure in this project |
| Tenant | A club whose data should be isolated from other clubs |
| Transaction | All-or-nothing database unit used for multi-record correctness |
| `update_or_create` | ORM method used to make attendance/confirmation writes idempotent by key |
| Use case | Domain action class such as `SignIn`, `LogSessionAttendance`, or `RaiseDispute` |
| Validation | Rejecting invalid format/range/state; must be authoritative on server |
| Widget test | Flutter test that renders UI and simulates interaction |
| X-Player-Unlock | Custom request header carrying the guardian’s signed player unlock token |

## Terms not to confuse

- **Authentication ≠ authorization:** Firebase login does not determine club access.
- **Hashing ≠ encryption:** PIN hashes are not intended to be decrypted.
- **Aggregate ≠ AI:** an average/count is deterministic analytics.
- **Supabase host ≠ Supabase client backend:** Django still owns all queries/policies.
- **Push send ≠ notification inbox:** FCM backend calls do not prove visible foreground/history UI.
- **Mock success ≠ live integration:** run `USE_MOCK=false` and show server persistence.
- **Eligibility ≠ grades:** only a status/history exists.
- **Dispute ≠ scouting:** it is an internal concern thread.
