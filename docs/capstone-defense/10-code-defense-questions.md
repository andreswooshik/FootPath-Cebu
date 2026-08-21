# Code Defense Question Bank

These questions focus on what a panelist can point to in source. Answers describe behavior rather than pretending every implementation is ideal.

### C1. Why does `main()` catch Firebase initialization failure?

- **Answer:** It lets the widget tree start and display a controlled authentication/configuration error rather than crashing before UI bootstrap. Live authentication still cannot succeed without valid initialization.
- **Evidence:** `footpath_cebu/lib/main.dart`.

### C2. Why is `ProviderScope` placed at the root?

- **Answer:** Riverpod repositories, use cases, controllers, and async data providers must be available throughout the app and dispose predictably.
- **Evidence:** `main.dart`; `core/di/providers.dart`.

### C3. What does `SessionBootstrapScreen._restore()` protect against?

- **Answer:** It prevents routing from a stale local Firebase session without rechecking the Django domain account, active flag, role, and club.
- **Evidence:** `session_bootstrap_screen.dart`; `restore_session.dart`; `firebase_auth_repository.dart`.

### C4. Why does `FirebaseAuthRepository` use both Firebase and an HTTP client?

- **Answer:** Firebase establishes identity while `/api/auth/me/` establishes application authorization/profile. Combining them implements the app’s actual sign-in contract.
- **Evidence:** `data/repositories/firebase_auth_repository.dart`.

### C5. What happens on a `/api/auth/me/` 401/403 during restore?

- **Answer:** The repository signs out the Firebase session because the local authorization is invalid. Other errors are kept retryable so a network outage does not unnecessarily destroy the session.
- **Evidence:** restore logic in `firebase_auth_repository.dart`.

### C6. Why are use cases separate from controllers?

- **Answer:** Controllers own UI async state; use cases express application actions against domain contracts. Tests and alternate adapters can change without widget dependencies.
- **Evidence:** `domain/usecases/`; `presentation/providers/`.

### C7. What proves dependency inversion?

- **Answer:** Domain use cases import repository interfaces, not `http`, Firebase, or sqflite. Concrete adapters are selected externally by `providers.dart`.
- **Evidence:** `domain/repositories/`; `domain/usecases/`; `core/di/providers.dart`.

### C8. Why is `OfflineFirstAttendanceRepository` a decorator?

- **Answer:** It adds queue fallback to an existing attendance contract by composing a live repository and outbox. The HTTP adapter stays focused on transport.
- **Evidence:** `data/repositories/offline_first_attendance_repository.dart`.

### C9. Why queue only `AttendanceNetworkException`?

- **Answer:** Authentication, permission, validation, and server business errors should not be treated as safe offline success. A network-classified exception indicates a potentially retryable transport failure.
- **Evidence:** `api_attendance_repository.dart`; `offline_first_attendance_repository.dart`.

### C10. Why store `owner_uid` in the outbox?

- **Answer:** Devices can be shared or accounts can change. Owner scoping prevents replaying one coach’s queued mutation under another authenticated identity.
- **Evidence:** `data/local/attendance_outbox.dart`; `attendance_sync_service.dart`.

### C11. Why stop sync after a failed replay?

- **Answer:** The queue represents ordered full-session batches. Continuing past a failed older batch could reverse the user’s intended last-write order.
- **Evidence:** `attendance_sync_service.dart`.

### C12. How does the session-attendance fallback avoid masking server errors?

- **Answer:** Both queued writes and queued roll-call reads fall back only on `AttendanceNetworkException`. Authentication, permission, validation, and 5xx HTTP responses remain visible instead of being replaced by local data.
- **Evidence:** `offline_first_attendance_repository.dart`; shared client and attendance tests.

### C13. How does `ApiConfig` prevent an unsafe release endpoint?

- **Answer:** Release mode forces live operation, requires HTTPS, and can restrict the allowed host. Debug keeps developer flexibility.
- **Evidence:** `core/config/api_config.dart`.

### C14. Why can debug mock mode be misleading?

- **Answer:** Its default is mock mode, so UI changes may not reach Django. Integration demonstrations must explicitly set `USE_MOCK=false` and show server-side effects.
- **Evidence:** `api_config.dart`; `providers.dart`.

### C15. What exactly does `FirebaseAuthentication.authenticate()` do?

- **Answer:** It extracts the Bearer token, verifies it with Firebase Admin including revocation, reads UID, finds the active Django user, and rejects missing club assignment for non-admin users.
- **Evidence:** `backend/accounts/authentication.py`.

### C16. Why not use the Firebase role claim as the source of truth?

- **Answer:** Django’s user/club/link records are the implemented domain authority. Centralizing role changes there avoids stale distributed claims and supports relational object checks.
- **Evidence:** ADR `docs/decisions/0001-roles-source-of-truth.md`; `accounts/authentication.py`; `accounts/models.py`.

### C17. How does `provision_user()` handle a partial cross-system failure?

- **Answer:** It creates/links Firebase identity and relational user inside a controlled service. If a newly created Firebase identity would become orphaned because the DB save fails, compensation deletes it.
- **Evidence:** `backend/accounts/services.py`.

### C18. Why use `transaction.on_commit()` for notifications?

- **Answer:** Creating an inbox event or sending a push before commit could advertise data that later rolls back. The callback runs only after successful database commit; cancellation snapshots recipients first but emits only after deletion commits.
- **Evidence:** `academy/views.py`; `academy/signals.py`; `academy/notifications.py`.

### C19. What do `pre_save` and `post_save` do for eligibility?

- **Answer:** `pre_save` remembers the database’s prior status; `post_save` compares it with the new value and creates history/audit/notification only on a real change.
- **Evidence:** `backend/academy/signals.py`.

### C20. Why use `select_for_update()` in PIN verification?

- **Answer:** It serializes concurrent attempts against one row so the failure counter and lock timestamp cannot be raced easily.
- **Evidence:** `backend/academy/pin_service.py`.

### C21. Why is the unlock token signed rather than a random PIN-success flag in Flutter?

- **Answer:** Django can verify integrity, age, user binding, and player binding without trusting mutable client state. A client boolean would be forgeable.
- **Evidence:** `backend/academy/player_unlock.py`; guarded views.

### C22. Why recheck the guardian link after validating the signed token?

- **Answer:** The relationship can be revoked during the token lifetime. Signature proves token integrity, not that current authorization still exists.
- **Evidence:** guardian access helpers/views in `academy/views.py`.

### C23. Why is a PIN hash not returned by the API?

- **Answer:** Clients need only status and verification outcomes. Exposing even a hash would enable offline guessing and leak an implementation secret.
- **Evidence:** PIN serializers/views/entities.

### C24. How does the attendance endpoint implement replacement semantics?

- **Answer:** Inside a transaction it `update_or_create`s submitted `(player, session)` rows and deletes existing rows for that session whose players were omitted.
- **Evidence:** attendance view in `backend/academy/views.py`.

### C25. What data is cleared for an absent/late/non-present mark?

- **Answer:** The Flutter finalization path removes effort and note when a player is not present, matching the meaning of per-session performance data.
- **Evidence:** `presentation/screens/log_attendance_screen.dart`.

### C26. Why does attendance use `SET_NULL` for deleted sessions?

- **Answer:** It preserves legacy attendance evidence even if the scheduled event is canceled/deleted. The tradeoff is that the row loses full session metadata unless separately captured.
- **Evidence:** `Attendance.session` in `academy/models.py`.

### C27. What is wrong with nullable-session uniqueness?

- **Answer:** A unique pair containing SQL `NULL` may permit multiple rows for the same player with no session. A conditional uniqueness rule or explicit legacy event key would be stronger.
- **Evidence:** `Attendance` model constraint and nullable `session`.

### C28. How are string-based training times made safe?

- **Answer:** The wire contract still uses display strings, but one model helper parses/normalizes supported 12-hour values, requires start/end as a pair, and rejects start greater than or equal to end. DRF maps the same errors and `save()` invokes model validation for ORM/admin paths. Native `TimeField`s would still provide stronger database typing.
- **Evidence:** `TrainingSession.validate_time_window`, `clean`, and `save`; `TrainingSessionSerializer.validate`.

### C29. How are nested performance ratings persisted?

- **Answer:** The API contract groups ratings for the client; the serializer validates each 0–99 value and maps them to individual `PlayerProfile` columns.
- **Evidence:** `academy/serializers.py`; `PlayerProfile` fields; `Player.fromJson`.

### C30. Why is the rating scale a defense issue?

- **Answer:** Executable code consistently uses 0–99 while `docs/REQUIREMENTS.md` says 1–10. Unreconciled specification drift undermines requirements traceability even if code is internally consistent.
- **Evidence:** assessment UI/entity/serializer/model versus requirements.

### C31. How does `AdminCreatePlayerView` preserve the Club invariant?

- **Answer:** It derives the Club from the selected active Guardian and calls the same `provision_player` aggregate service used by the Coordinator flow.
- **Evidence:** admin player view in `backend/accounts/views.py`; club gate in `authentication.py`.

### C32. How is generic admin creation prevented from creating a profile-less Player?

- **Answer:** It cannot: generic choices exclude `PLAYER`; the dedicated service creates one User and one `PlayerProfile` in the same transaction.
- **Evidence:** `AdminCreateUserSerializer`; `AdminUserListCreateView`; `PlayerProfile` access paths.

### C33. How are Player invariants preserved outside interactive provisioning?

- **Answer:** Both seed commands use the aggregate service or an idempotent equivalent that assigns an active Club and `get_or_create`s exactly one PlayerProfile. Re-running seeds repairs incomplete demo rows rather than creating duplicates.
- **Evidence:** `accounts/management/commands/seed_users.py`; `academy/management/commands/seed_academy.py`; integrity tests.

### C34. How does squad progress scope Coach versus Super Admin?

- **Answer:** The base profile/attendance query spans all Clubs. It adds a Club filter only for Coach; Super Admin keeps the all-Club queryset. Other roles are rejected.
- **Evidence:** `SquadProgressView` in `academy/views.py` and its role-scope tests.

### C35. What is weak about `AuditLog.record()`’s guarantee?

- **Answer:** Its comment implies audit must never fail a primary operation, but the function itself does not catch database exceptions. Transaction context determines whether failure can propagate/rollback.
- **Evidence:** `AuditLog.record` in `academy/models.py` and call sites.

### C36. How are file uploads validated before Supabase?

- **Answer:** Django first checks the caller (same-Club Coach or authorized web/admin path), maximum size, declared content type, and file signature, then uploads with a server-held service credential and generates signed reads. Flutter’s picker/use case adds early type/size feedback but never replaces server validation.
- **Evidence:** `backend/academy/storage.py`; photo upload views; `player_profile_screen.dart`; `upload_player_photo.dart`.

### C37. Why is `unsafe-inline`/`unsafe-eval` in CSP a concern?

- **Answer:** It weakens the browser’s protection against injected script. It currently supports CDN Tailwind/Alpine usage; local bundled assets with nonce/hash policy would be safer.
- **Evidence:** `backend/portal/middleware.py`; portal templates.

### C38. What happens when the notification bell is pressed?

- **Answer:** The bell opens the authenticated notification inbox, whose provider loads current-user records and unread count. Rows can be marked read or all read. A row tap, foreground **View**, or opened/initial push sends known trusted events to the authorized Schedule, Player/linked-child Profile, or Eligibility destination; unknown events and current-profile failures safely return to the focused inbox.
- **Evidence:** `notification_bell.dart`; `notification_inbox_screen.dart`; notification providers/repository; `main.dart`.

### C39. What happens after a successful mutation in Riverpod?

- **Answer:** The controller invalidates affected read providers, causing a fresh authoritative fetch rather than relying only on manually patched UI state.
- **Evidence:** performance, schedule, injury, dispute, attendance, confirmation provider/controller files.

### C40. What is the limitation of broad provider invalidation?

- **Answer:** It is simple and consistent but can trigger extra API work and reset parts of UI state. Targeted cache updates/pagination would scale better.
- **Evidence:** repeated `ref.invalidate(...)` in presentation providers.

### C41. Why centralize API transport in `AuthenticatedApiClient`?

- **Answer:** It applies one Bearer-token, timeout, safe error-extraction, multipart, and cache policy across repositories. Eligible successful GETs are cached by Firebase UID and exact request; only network failures may read cache, while 401/403/other HTTP/decode errors cannot be hidden.
- **Evidence:** `data/network/authenticated_api_client.dart`; `data/local/api_get_cache.dart`; transport/cache tests.

## Code-walk checklist

When asked to open code live, choose one of these coherent chains:

1. `main.dart` → `session_bootstrap_screen.dart` → `firebase_auth_repository.dart` → `accounts/authentication.py` → `MeView`.
2. `log_attendance_screen.dart` → attendance controller/use case → offline decorator → API repository → attendance Django view → model.
3. `guardian_dashboard_screen.dart`/privacy gate → PIN provider/use case → API repository → `pin_service.py` → `player_unlock.py` → guarded detail view.
4. assessment editor → controller/use case → player API repository → assessment serializer/view → profile model/signals/notifications.
5. `main.dart` FCM listener → notification provider/repository → notification endpoints → `NotificationRecord` → inbox/bell/read state.
6. player profile picker → photo controller/use case → authenticated multipart client → photo endpoint/storage validation → `photo_path`/signed URL.

Do not jump among unrelated snippets. Narrate inputs, trust decisions, persistence, output, UI state, and failure path in that order.
