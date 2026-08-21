# FootPath Cebu — Master Capstone Defense Reviewer

## Approved account hierarchy

```text
SUPER ADMIN → CLUB (SCHOOL | INDEPENDENT) → CLUB COORDINATOR
                                             ↓
                         COACH / PLAYER / GUARDIAN / SCHOOL STAFF
```

Super Admin creates Clubs and their single Coordinators. The Coordinator is
the normal creator of members only in their own Club. School Staff and
status-only academic eligibility apply only to School Clubs; Independent Clubs
show Not Applicable. FootPath Cebu never stores raw student grades.

## Read this first

This is the shortest complete defense path through the repository. Use the numbered chapters for depth and `16-code-tracing.md` when a panelist asks what executes after a click.

### August 21, 2026 hardening note

Current local verification is **241/241 Django tests**, **240/240 Flutter tests**, and **clean `flutter analyze`**. The hardening pass also completed Player/Profile/Club invariants and seed repair, Coach/Super-Admin progress scope, paired/ordered session times, persistent notification receiving/inbox behavior, visible RSVP errors, shared authenticated HTTP plus owner-scoped GET caching, and Coach photo upload. Production artifacts are present, but no live deployment, exercised monitor/alert, scheduled backup, restore drill, physical-device FCM delivery, or live Supabase upload is claimed without separate evidence.

## 90-second opening

> FootPath Cebu is a role-based youth football academy management system. Coaches, players, and guardians use a Flutter app; club coordinators and school staff use a Django portal; administrators use Django admin and protected APIs. The system centralizes player profiles and ratings, schedules, attendance, session confirmations, eligibility history, injuries, disputes, guardian links, and club account management.
>
> Technically, Flutter uses Riverpod with presentation, domain, and data layers. Firebase validates mobile identity and provides push messaging, but Django is the authorization and data source of truth. Django verifies each ID token, maps it to an active local user, applies role, club, object, and guardian-link rules, then persists through the ORM. SQLite is the default/test database; configured deployments can use PostgreSQL, including Supabase-hosted PostgreSQL. Supabase private storage is optional and server-mediated.
>
> The most distinctive implemented features are a user-scoped offline attendance outbox, owner-scoped authenticated GET caching, a persistent notification inbox/receive path, and a layered guardian privacy PIN with hashing, lockout, and short-lived signed unlock tokens. AI, scouting, match statistics, chat, and maps are not implemented; physical-device external-service and production-operation claims still require separate evidence.

## Project truth table

| Claim | Status | Defensible detail |
|---|---|---|
| Flutter mobile client | Implemented | Dedicated coach/player/guardian portals |
| Django REST backend | Implemented | Authentication, roles, API, ORM, portal, admin |
| Firebase Auth | Implemented | Email/password and ID-token verification |
| FCM notifications | Implemented repository path | persistent current-user inbox/read state and foreground feedback; known trusted events route to authorized Schedule/Profile/Eligibility destinations, while unknown events/profile failures focus the inbox; physical delivery not yet evidenced |
| SQLite | Implemented/default | local backend and forced tests |
| PostgreSQL/Supabase DB | Configurable | Django connection; no direct Flutter query |
| Supabase Storage | Optional/implemented server path | same-Club Coach mobile upload plus admin/coordinator paths and signed URL; configured credentials required |
| Supabase Auth/RLS | Not implemented/needed in topology | Django owns authorization |
| Offline mode | Scoped | attendance is the only replayable mutation; successful authenticated GETs have an owner-scoped network-failure cache |
| AI/ML | Not implemented | do not call aggregates AI |
| Scouting | Not implemented | dispute is not scouting |
| Match statistics | Not implemented | no model/endpoint/UI |
| Grades | Not implemented | eligibility status/history only |
| Production deployment | Artifacts implemented; execution not verified | Docker/compose, Gunicorn/WhiteNoise, health/readiness, optional Sentry, runbook, and backup/restore scripts exist; no live/monitor/backup/restore proof inspected |

## Reconstructed objectives

No authoritative formally labeled general/specific objective section was found. Defend these as implementation-derived objectives:

- **General:** centralize youth academy development and operations securely across authorized roles.
- **Specific:** digitize player development; schedule and record training; provide controlled player/guardian visibility; create traceable eligibility and dispute histories; enforce club/role isolation; support offline attendance; centralize account provisioning.

## Architecture to draw

```text
Flutter widget
  -> Riverpod controller/provider
  -> domain use case
  -> repository interface
  -> API/Firebase/offline adapter
  -> Firebase ID token + Django REST
  -> FirebaseAuthentication
  -> role + club + object/link check
  -> serializer/form/service
  -> Django ORM transaction
  -> SQLite or PostgreSQL
  -> JSON/entity/state rebuild

Coordinator/Staff browser -> Django session + CSRF/Axes -> portal service -> ORM
Admin browser             -> Django admin/protected admin API       -> ORM
```

## Roles and interfaces

| Role | Key allowed work |
|---|---|
| Admin | Approve/maintain clubs and users; global administrative data operations |
| Coordinator | Create club accounts/links, manage roster metadata/photos |
| Coach | Squad, sessions, attendance, current assessment/position, progress, injury reads, disputes |
| Player | Own dashboard, confirmation, eligibility/attendance reads, injury CRUD, PIN setup |
| School Staff | Club-scoped eligibility updates and authorized dispute participation |
| Guardian | Linked-player selector and PIN-unlocked permitted reads |

## Most important execution traces

### Login

`LoginScreen._handleSignIn()` → `LoginController.signIn()` → `SignIn.call()` → `FirebaseAuthRepository.signInAndFetchProfile()` → Firebase `signInWithEmailAndPassword()` → `getIdToken()` → `GET /api/auth/me/` → `FirebaseAuthentication.authenticate()` → `MeView.get()` → `UserSerializer` → `UserProfile.fromJson()` → `Navigator.pushReplacement(HomeScreen)` → role portal.

### Player dashboard retrieval

`PlayerDashboardScreen` watches `myProfileProvider` → `GetMyProfile.call()` → `ApiPlayerRepository.fetchMyProfile()` → `GET /api/players/me/` → `MyProfileView.get()` → `PlayerProfile` query → `PlayerSerializer` → `Player.fromJson()` → Riverpod `AsyncData` → dashboard widgets.

### Assessment save

`EditPerformanceDataScreen._save()` → `EditPerformanceController.submit()` → `SavePlayerAssessment.call()` → `ApiPlayerRepository.saveAssessment()` → `PUT /api/players/{id}/assessment/` → coach/same-club check → `AssessmentSerializer.save()` → `academy_playerprofile` update + audit + on-commit FCM → `PlayerSerializer` → `Player.fromJson()` → squad invalidation → refreshed UI.

### Attendance save/offline fallback

`LogAttendanceScreen._finalize()` → `AttendanceLogController.save()` → `LogSessionAttendance.call()` → `OfflineFirstAttendanceRepository.saveSessionAttendance()` → `ApiAttendanceRepository.saveSessionAttendance()` → `POST /api/attendance/session/{id}/` → coach/club/date/record validation → atomic `update_or_create` + prune omitted rows in `academy_attendance` → JSON list → `Attendance.fromJson()` → provider invalidation.

If a network exception occurs: serialize the batch to local `outbox_attendance` with `owner_uid`; sync later calls the same live repository oldest first; success removes the row, failure increments retry metadata and stops.

### Guardian unlock/read

Guardian watches `linkedPlayersProvider` → `GET /api/players/linked/` redacted selector → selects child → `PlayerPrivacyGate` submits PIN → verify use case/repository → `POST /api/players/{id}/pin/verify/` → transactional hash/failure/lock check → `issue_player_unlock(user, player)` → memory token store → detail repository adds `X-Player-Unlock` → Django verifies age/binding/link → `PlayerSerializer` → full child view.

### Training create

`ScheduleSessionScreen._submit()` → `ScheduleSessionController.submit()` → `ScheduleTrainingSession.call()` → `ApiTrainingRepository.createSession()` → `POST /api/training-sessions/` → coach check + serializer/model paired-time and start-before-end validation → server assigns club/creator → `academy_trainingsession` insert + audit + on-commit notification → `TrainingSession.fromJson()` → schedule-provider refresh.

### Eligibility update/read

Portal `staff_eligibility()` → `set_player_eligibility()` → `PlayerProfile.save()` → `stash_previous_eligibility()`/`fire_eligibility_changed()` → `academy_eligibilityhistory` + audit + on-commit FCM. Player/guardian `eligibilityHistoryProvider` → API repository → `GET /api/players/{id}/eligibility-history/` → role/link/unlock checks → `EligibilityChange.fromJson()` → list cards.

### Notification receive/inbox

Committed event → `academy.notifications._send_to_users()` → current-user `NotificationRecord` rows → best-effort FCM → Flutter foreground/opened/initial handling → `NotificationNavigationController` re-resolves the current profile and marks the matching row read best-effort → known `session_*`/assessment/eligibility events enter the authorized Schedule/Profile/Eligibility destination; unknown events or profile failures focus `NotificationInboxScreen`.

### Coach photo upload

Same-Club Coach opens player → `ImagePicker` → `PlayerPhotoController` → `UploadPlayerPhoto` → `ApiPlayerRepository.uploadPhoto()` → shared authenticated multipart client → `POST /api/players/{id}/photo/` → Django role/Club/size/MIME/signature validation → configured Supabase private storage → `photo_path` + signed URL → refreshed player/squad. Without valid Supabase credentials, upload fails visibly and the avatar fallback remains.

## Database essentials

- `accounts_club`: tenant.
- `accounts_user`: local identity, Firebase UID, role, club.
- `accounts_guardianlink`: unique guardian/player pair.
- `academy_playerprofile`: one-to-one current development/eligibility/photo data.
- `academy_playerprivacypin`: hash/failure/lock state.
- `academy_trainingsession`: club schedule.
- `academy_attendance`: unique player/session status, effort, note, recorder.
- `academy_sessionconfirmation`: unique player/session RSVP.
- `academy_eligibilityhistory`: old/new status and changer.
- `academy_injuryrecord`: player-owned injury history.
- `academy_dispute` + `academy_disputeresponse`: concern thread.
- `academy_auditlog`: actor/action/target/detail/time.
- `academy_devicetoken`: unique FCM token.
- `academy_notificationrecord`: per-user event/data/read/time inbox history.
- mobile `outbox_attendance`: owner/session/batch/retry state.
- mobile `api_get_cache`: owner/request/successful JSON/expiry metadata; network-only fallback.

## Security defense

1. Firebase token is signature/expiry/revocation verified.
2. UID must map to an active local user.
3. Non-admin user must have a club.
4. Endpoint checks role.
5. Query/object checks enforce club/ownership.
6. Guardian requires link and, for private detail, PIN unlock.
7. PIN is Argon2-backed, transactionally throttled, and never returned.
8. Signed unlock is user/player-bound and ten minutes old at most.
9. Serializers/forms validate inputs; trusted actor/club fields are server-derived.
10. Transactions and relational constraints enforce multi-row integrity.
11. Web flows add sessions, CSRF, password validation, and Axes lockout.
12. Production settings add HTTPS, secure cookies, HSTS, host/CORS allowlists, and Redis requirement.
13. Generic user creation excludes `PLAYER`; trusted and seed paths enforce active Club plus exactly one PlayerProfile.
14. Shared API policy never turns 401/403/other HTTP errors or protected unlock reads into cached success.
15. Notification list/read operations are current-user scoped; inbox persistence survives best-effort FCM failure.

## Top ten files to know cold

1. `footpath_cebu/lib/core/di/providers.dart`
2. `footpath_cebu/lib/data/repositories/firebase_auth_repository.dart`
3. `footpath_cebu/lib/data/network/authenticated_api_client.dart`
4. `footpath_cebu/lib/data/repositories/offline_first_attendance_repository.dart` + local outbox/cache
5. `backend/config/settings.py`
6. `backend/accounts/authentication.py`
7. `backend/accounts/services.py`
8. `backend/academy/models.py`
9. `backend/academy/views.py`
10. `backend/academy/notifications.py` + Flutter notification inbox/bell/listeners

## Test statement—say exactly this

> On August 21, 2026, `flutter analyze` passed with no issues, all 240 Flutter tests passed, and all 241 Django tests passed locally. The Django run includes the Club hierarchy matrix plus the new integrity, tenant-deletion, notification/photo, and readiness tests. GitHub Actions is configured to repeat backend tests/deploy checks/script validation/container build and Flutter analyzer/test gates.

## Top ten remaining weaknesses/boundaries

1. Assessment saves overwrite current fields; no versioned assessment history exists.
2. Rating range lacks comprehensive database enforcement.
3. Attendance is the only queued/replayed mutation; conflicts use simple last-write-wins.
4. Training times remain display strings even though serializer/model chronology validation is now enforced.
5. Roster/inbox list behavior needs a fuller pagination/server-search strategy for larger deployments.
6. Portal CSP still permits `unsafe-inline`/`unsafe-eval` for current assets.
7. Physical-device FCM and configured Supabase upload evidence remains environment-dependent.
8. Privacy consent/retention/deletion/incident-response artifacts remain incomplete.
9. Live deployment, monitor/alert exercise, scheduled backup, and restore drill are unverified.
10. Requirements still differ from the implemented rating scale; README architecture is now reconciled.

## Top 20 panel questions

1. **What is it?** A role-based youth academy operations/development system.
2. **Who uses it?** Six roles; coach/player/guardian mobile, coordinator/staff/admin web.
3. **Where is authorization?** Django roles, clubs, object/link checks—not Flutter.
4. **Firebase versus Django?** Firebase identity; Django domain authority/data.
5. **Supabase?** Optional PostgreSQL/private storage; server-only access; no RLS.
6. **AI?** Not implemented.
7. **Scouting?** Not implemented; disputes are not scouting.
8. **Offline?** Attendance is the only replayable write; eligible reads have an owner-scoped network-failure cache.
9. **Conflict resolution?** Complete-batch ordered replay; later write wins.
10. **Guardian privacy?** Login + link + hashed PIN + lockout + signed ten-minute token.
11. **Performance scale?** Code 0–99; requirements’ 1–10 is inconsistent.
12. **Assessment history?** Not implemented; current profile overwrites.
13. **Grades?** Not stored; eligibility enum/history only.
14. **Notifications?** Durable inbox/read state, bells, foreground feedback, and role-aware schedule/player/eligibility routing with a focused-inbox fallback are implemented; physical delivery is separate evidence.
15. **Tests?** Flutter analyze clean; Flutter 240/240 and Django 241/241 pass locally on 2026-08-21.
16. **Production ready?** Repository artifacts are ready; live deployment/monitoring/backup/restore execution is unverified.
17. **Biggest strength?** Server authority + privacy + owner-scoped resilience + durable notifications.
18. **Biggest remaining data gap?** No versioned assessment history.
19. **Cross-club attack?** Same-club backend lookups and server-derived ownership reject it.
20. **First improvement?** Reconcile the remaining rating requirement, retain live device/external-service evidence, and execute production recovery evidence.

## Defense red lines

Never claim:

- Firestore is the current database;
- Firebase roles/custom claims authorize the domain;
- Supabase RLS protects client queries;
- AI, scouting, grades, match stats, chat, or maps exist;
- locally tested notification routing proves physical-device Firebase/APNs delivery;
- every feature works offline;
- assessments have version history;
- stale test totals after the suite changes;
- the repository proves a live production deployment.

## Recommended first study session (90 minutes)

1. 15 min — memorize the opening and truth table.
2. 20 min — draw architecture and role/interface map from memory.
3. 20 min — trace login and attendance aloud with file/function names.
4. 15 min — explain guardian PIN and cross-club defense.
5. 10 min — recite absent features, external-service boundaries, and remaining weaknesses.
6. 10 min — answer the top 20 questions in one sentence each.

Start with architecture and truth boundaries, not every UI screen. Once “Firebase identity, Django authority, relational data, owner-scoped resilience, durable inbox” is automatic, the detailed workflows become much easier to recall.

## Reviewer navigation

- Project/scope: `01-project-overview.md`
- Architecture: `02-system-architecture.md`
- Flows: `03-system-flow.md`
- Important code: `04-code-explanation.md`
- Database: `05-database-and-data-flow.md`
- Security: `06-security-and-privacy.md`
- AI/advanced: `07-ai-and-advanced-features.md`
- Tests/limits: `08-testing-and-limitations.md`
- 80 panel questions: `09-panel-questions.md`
- 40 code questions: `10-code-defense-questions.md`
- Demo: `11-demo-script.md`
- Study plan: `12-seven-day-study-plan.md`
- Recall: `13-rapid-recall-sheet.md`
- Glossary: `14-technical-glossary.md`
- 30 attack questions: `15-panel-attack-mode.md`
- Full traces: `16-code-tracing.md`
