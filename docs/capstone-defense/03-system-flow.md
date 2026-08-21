# System Flow

## End-to-end request pattern

Most mobile workflows use the same chain:

```text
Tap / form submit
  -> StatefulWidget validation
  -> Riverpod controller
  -> domain use case
  -> repository interface
  -> live API implementation
  -> shared authenticated client (Bearer token, timeout, typed errors)
  -> Django authentication
  -> endpoint role + club/object checks
  -> serializer validation
  -> ORM transaction/save
  -> JSON response
  -> entity deserialization
  -> controller state/provider invalidation
  -> rebuilt UI / feedback
```

Mocks stop at a mock repository. Offline attendance may detour through the local outbox before later replaying the live request. Eligible successful GET responses can be read from an owner-scoped cache only when the shared client detects a network-classified failure; HTTP errors are never replaced by cached data.

## Startup and session restoration

1. `main()` initializes Firebase and runs a Riverpod `ProviderScope`.
2. `MaterialApp` opens `SessionBootstrapScreen`.
3. The screen calls `RestoreSession` through a provider.
4. `FirebaseAuthRepository.restoreSession()` waits for Firebase’s first auth-state result.
5. If no Firebase user exists, the login screen is shown.
6. If a user exists, Flutter obtains an ID token and calls `GET /api/auth/me/`.
7. Django verifies the token with revocation checking, maps Firebase UID to an active local user, and applies the club requirement.
8. The response becomes `UserProfile` and `HomeScreen` selects the role portal.
9. On successful live restoration, device registration and attendance synchronization start.
10. A 401/403 causes local Firebase sign-out; other failures can be shown as retryable bootstrap errors.

## Login and logout

### Login success

`LoginScreen._handleSignIn` → `LoginController.signIn` → `SignIn.call` → `FirebaseAuthRepository.signIn` → Firebase email/password sign-in → ID-token retrieval → Django `/api/auth/me/` → `UserProfile.fromJson` → `HomeScreen` → role portal.

Firebase success is insufficient if the Django user is missing, inactive, or lacks a required club. The app needs both identity and local authorization.

### Login failure

Firebase errors or profile-endpoint errors become repository/controller errors and are rendered by the login UI. Empty credentials are not prevalidated by the screen; Firebase produces the failure. This is a UX gap, not an authorization bypass.

### Logout

Portal screen → best-effort device-token unregister → `signOutProvider` → `SignOut` captures the Firebase UID → Firebase sign-out → clear that captured owner’s GET cache → clear in-memory guardian unlock tokens → replace navigation with `LoginScreen`.

## Account registration and provisioning

There is no public mobile registration.

### Super Admin creates Club and Coordinator

Authenticated Super Admin → create Club → select `SCHOOL` or `INDEPENDENT` →
select the valid Club in the Coordinator flow → create role `COORDINATOR` with
that exact Club → activate/deactivate through protected lifecycle controls.
The public signup URL is informational and creates no records.

### Coordinator creates a club account

Authenticated coordinator → portal create-account form → server derives
`request.user.club` → validates role/active Club/type → `create_club_account` →
Firebase identity plus Django `User` (or Django-session School Staff account) →
central `provision_player` creates the PlayerProfile and optional same-Club
GuardianLink atomically → success response.

New active academy users are provisioned by trusted roles. Generic account creation excludes `PLAYER`; every Player is required to have an active Club and exactly one `PlayerProfile`. Admin, API, portal, and seed paths use the central aggregate service or an idempotent equivalent. The service generates temporary credentials and compensates by deleting a newly created Firebase identity if the database operation fails.

## Coach flow

1. Coach signs in and is routed to `CoachPortalScreen`.
2. Providers load squad, sessions, confirmations, attendance aggregates, or progress from APIs.
3. The coach can open a player, assign position, edit the current assessment, review injury/attendance history, or flag a dispute.
4. The coach can create/edit/cancel sessions and log attendance within the server’s permitted date window.
5. Successful writes invalidate relevant Riverpod providers so screens refetch current server state.

## Player flow

1. Player signs in and reaches `PlayerPortalScreen`.
2. A privacy setup gate requires the player to create a 4–6 digit household PIN before the dashboard content is shown.
3. The player loads their own profile via `/api/players/me/`.
4. The player can view current ratings/notes, attendance, eligibility history, and injuries.
5. The player owns injury CRUD.
6. For a session scheduled today, the player can set a confirmation response.

The PIN is a household privacy layer, not the primary API authentication for a player’s own data; Firebase/Django authentication remains primary.

## Guardian flow

1. Guardian signs in and calls `/api/players/linked/` for a deliberately redacted list.
2. Guardian selects a linked player.
3. The privacy gate checks PIN availability and asks for the player’s household PIN.
4. `POST` verification checks the hash, increments failures atomically, applies lockout after five failures, and returns a signed player/user-bound token on success.
5. Flutter stores that unlock token only in memory.
6. Guardian detail requests add `X-Player-Unlock`.
7. Django checks signature, user/player binding, ten-minute age, and guardian link before returning profile, attendance, injury, or eligibility information.
8. Logout clears the token store; expiry requires another PIN.

## School staff flow

School staff use Django’s session-authenticated portal. The eligibility form lists club-scoped players. A valid update saves `PlayerProfile.eligibility`; signals capture the prior state, create `EligibilityHistory` and `AuditLog`, then schedule FCM after transaction commit. The implementation stores eligibility status, not grades.

## Training schedule flow

Coach presses schedule/edit → form validates required text, date, and tiers → controller/use case → `ApiTrainingRepository` → Django training-session endpoint → coach-role and club enforcement → serializer validation → server assigns creator and club → model validation/save → audit → FCM scheduled after commit → serialized response → provider invalidation → refreshed schedule. The serializer and `TrainingSession` model both require paired supported 12-hour time strings and `startTime < endTime`, so API, ORM, form, and admin paths share the cross-field rule.

Cancellation snapshots recipients, audits, and deletes the session inside the successful request path, then schedules the cancellation notification with `transaction.on_commit()`. A failed delete therefore cannot emit a false cancellation message. Existing attendance records retain history because their session foreign key uses `SET_NULL`; session confirmations are deleted through `CASCADE`.

## Attendance with offline branch

### Online success

Coach marks players → finalize validates unmarked records/window → non-present marks have effort/note removed → controller/use case → `OfflineFirstAttendanceRepository` → live API → backend coach/club/date checks → per-record serializer validation → transaction `update_or_create` and delete omitted session rows → response → UI success and provider invalidation.

### Network failure

If and only if the live write raises `AttendanceNetworkException`, the repository serializes the whole batch into the user-scoped sqflite outbox. The UI receives an optimistic result and can continue. Connectivity/session-start synchronization later replays batches sequentially. A successful replay removes the item; a failure increments retry metadata and stops that pass.

Because the endpoint replaces the submitted session set and the queue replays in order, later batches effectively win. This is a simple and explainable conflict policy, not a merge algorithm.

### Cached read branch

The shared `AuthenticatedApiClient` caches only eligible successful JSON GET responses under the current Firebase UID and request key. On timeout/socket/handshake/client failure it may return an unexpired entry for that owner. It does not cache protected `X-Player-Unlock` reads and does not use cache for 401, 403, other 4xx, 5xx, or malformed success payloads. Logout clears only the departing owner’s entries.

## Performance assessment flow

Coach opens a player → editor initializes twelve rating inputs and notes → `_save` validates/parses → `EditPerformanceController.submit` → `SavePlayerAssessment` → `ApiPlayerRepository` `PUT` → backend coach/same-club check → serializer validates ratings as 0–99 → flatten/update `PlayerProfile` → audit save → notification after commit → `PlayerSerializer` response → domain `Player` → squad provider invalidation → saved player returned.

Only the current profile is stored. There is no assessment-version history table.

## Eligibility flow

For a School Club, School Staff changes one of the four approved statuses in
the portal → model save → history/audit → FCM on commit. Players and unlocked
linked guardians can retrieve permitted history. For an Independent Club the
feature returns Not Applicable and no history. Raw grades are never collected.

## Injury flow

Player opens injury history → provider/use case → API list. Create/edit form → save use case → POST/PUT → backend requires the authenticated player to own the record → serializer/model save → entity response → provider invalidation. Delete follows the same ownership rule. Coach, administrator, and unlocked linked guardian have authorized read paths; they do not receive player write ownership.

## Player-photo flow

An authorized Coordinator/admin web user or same-Club Coach in Flutter selects an image → Flutter sends multipart form data to `POST /api/players/<player_id>/photo/` → Django rechecks role and same-Club scope → validates size, MIME type, and file signature → uploads privately through the server → stores `PlayerProfile.photo_path` → returns a player with a short-lived signed display URL. The mobile controller refreshes player/squad state and surfaces validation or storage errors. This workflow requires configured Supabase Storage credentials; without them, upload fails visibly and display uses the existing avatar fallback.

## Dispute flow

Coach opens flag form → submits category, summary/detail, and a club-scoped subject player → use case/API → backend validates coach and club → creates an `OPEN` dispute → response/invalidation. Authorized coach/staff/admin users can list threads and append `DisputeResponse`; a response may atomically change status. Responses are append-only; edit/delete was not found.

This is the closest implemented workflow to reporting a concern. It is not a scouting report.

## Notification send, inbox, and receive flow

Most committed domain events → notification helper selects active recipients → creates a current-user `NotificationRecord` with title/body/event data → best-effort Firebase Admin fan-out to registered device tokens → invalid tokens may be removed. Cancellation snapshots recipients and schedules this work only after the delete commits. Inbox endpoints list the authenticated user’s newest records, report unread count, mark one read, or mark all read.

Flutter registers and refreshes the FCM token, renders an unread badge and persistent inbox, and handles `onMessage`, `onMessageOpenedApp`, and the initial message. A foreground push produces visible feedback with a View action. Opened pushes re-resolve the current Django profile, suppress duplicates, mark the matching inbox row read best-effort, and route session events to the schedule or assessment/eligibility events to the role-appropriate Player/Guardian destination. Guardian targets are resolved only from linked children and existing PIN gates remain in force; unknown events fall back to the focused inbox. Remote transport still requires valid Firebase/APNs configuration and a supported device.

## Search/filter flow

The coach roster is fetched for the club, then `RosterFilter.apply` performs in-memory name/tier/position filtering. Search does not generate a server query. This is adequate for a small academy roster but less scalable than paginated server filtering.

## Error-handling patterns

- UI controllers expose loading/error state through Riverpod.
- serializers return client errors for invalid data;
- authentication returns 401/403 for identity/permission failures;
- account provisioning compensates across Firebase and the relational database;
- attendance distinguishes network failures for queueing;
- the shared API client keeps auth, timeout, typed transport/HTTP/decode errors, and safe cache policy consistent;
- Supabase photo helpers fail safely when unconfigured for reads and reject invalid uploads;
- session confirmation reports failed submission with a SnackBar and offers `Retry RSVP` when initial loading fails.

## Flow statement to memorize

> The UI never writes the database directly. A tap calls a controller, domain use case, and repository. Live repositories use a shared client to send a Firebase Bearer token to Django. Django re-verifies identity, applies role and club/object authorization, validates input, writes through the ORM, and sends JSON back. Riverpod then refreshes the affected state. Attendance adds one controlled offline write-queue branch, while eligible reads have a user-scoped cache used only for network failures.
