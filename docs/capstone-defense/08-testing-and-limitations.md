# Testing, Verification, and Limitations

## August 21, 2026 hardening update

The current full outputs are **241/241 Django tests passing**, **240/240 Flutter tests passing**, and **clean `flutter analyze`**. Repository inspection also confirms the resolved Player aggregate/seed invariants, Coach-vs-Super-Admin progress scope, session-time validation, persistent notifications and role-aware routing, visible RSVP errors, shared HTTP/cache policy, and Coach photo-upload path described below.

## Current verification result (2026-08-21)

| Check | Result | Interpretation |
|---|---|---|
| `flutter analyze` | PASS — no issues found | Current final hardening run is clean |
| `flutter test` | PASS — 240/240 | Current final full mobile suite output |
| `python -m compileall -q backend` | PASS | Python source is syntactically compilable |
| `python manage.py check` | PASS — no issues | Django system checks completed in the installed backend environment |
| Django tests | PASS — 241/241 | Current full local backend suite output |
| GitHub Actions definition | PRESENT | CI installs requirements, runs Django tests/deploy check, validates operational scripts, builds the backend image, and runs Flutter analyze/test |

The **241/241 Django** and **240/240 Flutter** results plus clean analyzer output are the current verified local outputs. The CI definition is evidence of configured automated gates, not proof that the latest remote workflow or a production deployment passed.

## What the automated tests cover

The inspected suites contain coverage for:

- authentication/profile routing and role behavior;
- entity JSON conversion and use-case/controller delegation;
- mock and API repository behavior;
- screen/widget loading, error, validation, and interaction states;
- attendance queue ownership/replay, owner-scoped GET caching, and network-only fallback behavior;
- Django roles, club scoping, API validation, attendance, session chronology, Player aggregate/seed invariants, all-club Super Admin progress, injuries, disputes, eligibility, PIN/unlock, persistent notifications, Coach photo upload, and portal workflows;
- account provisioning and compensation cases;
- production-oriented settings checks through CI.

Exact coverage percentage is not configured/reported, so do not claim “100% coverage.”

## Testing-type assessment

| Type | Current repository evidence | Status |
|---|---|---|
| Unit tests | Dart entity/use-case/repository/controller tests; Django service/model/view-focused tests | Implemented |
| Widget tests | Flutter screens/widgets render and simulate interactions/states | Implemented |
| API/integration-style tests | Django test client exercises endpoints, authz, persistence, portal workflows | Implemented and included in the current 241/241 backend run |
| Full device end-to-end | No automated Firebase + live Django + real device suite was identified | Not found; manual live walkthrough required |
| Validation testing | Flutter form and DRF/Django form invalid-input cases | Implemented in multiple suites |
| Security testing | Role/club/PIN/object tests and CI deploy check; no external penetration-test report | Partial |
| Usability testing | UI/widget behavior tests exist; formal user-study/SUS artifact was not found | Not found as formal research evidence |
| Manual testing | Plans/checklists exist, but a completed signed test report was not verified | Documented/planned evidence only |

## Recommended testing matrix

| Feature | Test case | Expected result | Current status |
|---|---|---|---|
| Login | Valid Firebase user with active local coach/club | Coach portal opens | Flutter/backend tests exist; live external run still needed |
| Login | Valid Firebase identity absent from Django | Access denied and Firebase session cleaned | Backend/client logic and tests present |
| Club isolation | Coach requests another club’s player/session | 403 or scoped not-found; no data | Backend tests present |
| Guardian privacy | Linked guardian uses correct PIN | ten-minute bound token and child detail | Tests present |
| PIN brute force | Five wrong attempts | 15-minute lock, 423 response | Tests present |
| Assessment | Rating below 0/above 99 | 400 and no profile change | Serializer/API tests present |
| Assessment | Same-club valid save | profile/audit and inbox record saved; FCM attempted after commit | Tests/source present; live FCM should be manual |
| Session | End before start or only one time supplied | 400; model and serializer reject/normalize the invalid pair | **Implemented and regression-tested** |
| Attendance | Valid in-window full batch | atomic upsert and omitted-row prune | Backend/client tests present |
| Offline attendance | Network write failure | current owner’s batch queued | Covered within the current 240/240 Flutter run |
| Offline attendance | Switch account before sync | other owner’s rows not replayed | Covered within the current 240/240 Flutter run |
| Offline/API read | HTTP 403/500 versus pre-response network failure | HTTP error remains visible; only a network failure may use current-owner cache/queued roll call | Implemented with typed-error/cache tests |
| Confirmation | Player responds for non-today session or submit fails | backend rejects invalid date; UI shows failure SnackBar/retry | Implemented with backend/widget coverage |
| Eligibility | Staff changes same-club status | current + history + audit, then push | Backend tests/source present |
| Injury | Guardian attempts write | 403 | Backend tests present |
| File upload | Coach uploads same-Club image or spoofed/oversize image | authenticated multipart succeeds with configured Supabase; invalid/cross-club input leaves path unchanged | Backend/mobile tests and source present; live storage still needs configured credentials |
| Provisioning | Firebase succeeds then DB fails | new Firebase identity compensated | provisioning tests exist |
| Player provisioning invariant | Coordinator/Admin flow creates player | role + non-null Club + exactly one profile; optional link same Club | **Implemented and regression-tested** |
| Seed integrity | Run either seed command against stale demo rows | active demo Club scope and exactly one Player profile repaired idempotently | **Implemented and regression-tested** |
| Squad progress | Coach versus Super Admin request | Coach sees own Club; Super Admin sees all Clubs | **Implemented and regression-tested** |
| Notifications | foreground/opened push, inbox row, and bell | persistent current-user inbox and read state; known trusted events route to authorized Schedule/Profile/Eligibility destinations, while unknown events or profile failures focus the inbox | Implemented in repository/tests; physical-device delivery remains manual |
| Session cancel failure | delete raises before completion | no false cancellation inbox/push is emitted | recipients snapshot; notification scheduled only after successful delete via `on_commit` |
| Shared API client | request times out or server returns 403/500 | typed network timeout/cache behavior; HTTP errors never become cached success | Implemented with client tests |
| Release config | HTTP API URL | build/runtime configuration rejects unsafe endpoint | source/test/CI evidence present |
| Deployment | build image, probe readiness, restore latest backup in isolation | repeatable procedure plus recorded deployment/restore evidence | Image/runbook/scripts exist; **no completed live deployment, alert, scheduled backup, or restore-drill evidence found** |

## How to reproduce verification

From `footpath_cebu/`:

```powershell
flutter pub get
flutter analyze
flutter test
```

From `backend/`, after creating an isolated environment and installing dependencies:

```powershell
python -m pip install -r requirements.txt
# Set DJANGO_SECRET_KEY to a long, disposable local-test value in your shell.
python manage.py test
python manage.py check
```

Use safe local placeholder secrets only for development/test; use a secret manager for production. CI always uses SQLite for the suite and mocks Firebase according to its comments/configuration.

## Functional limitations

1. No AI/ML feature.
2. No scouting role/report/recruitment workflow.
3. No match statistics or match-event model.
4. No chat/messaging.
5. Notification inbox/read and role-aware destination logic is implemented and locally tested; physical-device FCM delivery is not yet evidenced here.
6. Coach photo upload is implemented for same-Club Players, but live upload/display depends on configured Supabase server credentials.
7. No historical performance-assessment snapshots; profile ratings overwrite.
8. No stored grades; only eligibility status/history.
9. Attendance is the only offline mutation/replay workflow. Successful authenticated GETs have an owner-scoped network-failure cache, but this is not full offline editing.
10. Search/filter is client-side over a loaded roster and is not paginated.
11. Container/compose, readiness, optional Sentry, and backup/restore artifacts exist, but no verified live deployment, exercised monitor/alert, scheduled backup, or successful restore drill was supplied.
12. Unknown or unsupported notification events deliberately fall back to the focused inbox instead of opening an unauthorized or guessed destination.

## Technical limitations

- Only attendance writes have an offline persistence/replay design; the shared client separately caches successful authenticated GETs per owner for pre-response network failures.
- Current assessments overwrite rather than forming a time series.
- Academy REST adapters now share token injection, a 15-second timeout, typed errors, safe server messages, multipart handling, and network-only GET-cache fallback; `/api/auth/me/` remains a separate identity bootstrap boundary.
- Client-side roster filtering and unpaginated responses assume modest club size.
- Notification inbox, read-state, matching, duplicate suppression, and role-aware destination logic are implemented and locally tested; real Firebase/APNs transport remains outside the verified repository run.
- Several important invariants are serializer/service-level rather than database-enforced.

## Operational limitations

- Firebase, reachable Django, correct secrets, and optionally Supabase/Redis must be configured for live mode.
- No verified production URL, observability/alerting evidence, backup schedule, or restore-test result was found.
- No complete child-data consent/retention/deletion/incident-response procedure was verified.
- Local Django execution still requires an isolated environment with all declared requirements; the current installed environment completed 241/241 tests.
- A physical-device demo requires a device-reachable API address and `USE_MOCK=false`.

## Future improvements

1. Retain live external Firebase/FCM/Supabase device evidence for the completed repository paths.
2. Add remaining database integrity constraints identified by the audit.
3. Add append-only performance assessment snapshots and trend views.
4. Complete a supported physical-device Firebase/APNs delivery smoke test.
5. Add production request metrics/tracing around the shared authenticated API client.
6. Add pagination/server search for larger multi-club deployments.
7. Establish consent, retention, deletion, audit export, incident response, backup, and restore procedures.
8. Add live Firebase/Django device E2E tests and retain release/deployment evidence.

## Resolved hardening findings and remaining risks

### Player provisioning invariant (resolved)

All executable player-creation paths now call
`accounts.services.provision_player`. The service requires an active Club,
creates the `PLAYER` user and exactly one `PlayerProfile` transactionally, and
validates an optional Guardian as active and same-Club. Generic admin user
creation no longer accepts `PLAYER`, and Django admin directs Player creation to
the dedicated flow. Both seed commands also repair non-Admin demo Club scope
and ensure seeded Players have their one-to-one profile.

### Progress administrator mismatch (resolved)

`SquadProgressView` now applies Club filters only for a Coach. A Super Admin retains the all-profile/all-attendance querysets, so cross-Club aggregate visibility no longer depends on the Admin's normally-null Club.

### Time/rating integrity

Training times remain wire strings, but `TrainingSession.validate_time_window()` now requires a paired 12-hour format, normalizes both values, and rejects start-at/after-end through serializer and model save paths. Ratings are API-validated at 0–99, but comprehensive database check constraints were not found.

### Error feedback (resolved for audited paths)

Session-confirmation submission now shows a failure SnackBar and an initial-load **Retry RSVP** action. Academy API adapters use `AuthenticatedApiClient` for consistent timeout, typed auth/network/HTTP/decode errors, and safe server detail extraction.

### Offline read fallback (resolved)

Session-attendance write queueing and roll-call fallback now catch only `AttendanceNetworkException`. HTTP 401/403/500 responses remain visible. Queued roll call and general GET cache lookups are scoped to the active Firebase UID.

## Ten hardening defense cards

### W1. Player/Club invariant

- **Evidence:** `provision_player` requires the Club and creates User/Profile/link atomically; the dedicated admin path derives the Club from its selected Guardian.
- **Panel question:** “What prevents a Player from being created without the required Club?”
- **Best defense:** “No. Generic creation excludes Player and every Player flow delegates to the same invariant-preserving service.”

### W2. Generic Player creation

- **Evidence:** `CREATABLE_ROLES` excludes `PLAYER`; Django admin validation also rejects direct Player-user creation.
- **Panel question:** “What guarantees every provisioned Player has a profile?”
- **Best defense:** “Only `provision_player` can create Players, and it commits the User and one-to-one profile together or rolls everything back.”

### W3. Admin progress visibility (resolved)

- **Evidence:** `SquadProgressView` Club-filters only the Coach branch and leaves Super Admin querysets all-club.
- **Panel question:** “Does an admin see every club’s progress?”
- **Best defense:** “Yes. Super Admin receives all-club aggregates, while a Coach remains restricted to their Club.”
- **Regression guard:** multi-Club tests cover both branches.

### W4. Notification experience (implemented; live delivery still external)

- **Evidence:** `NotificationRecord` persists current-user history; list/count/read endpoints, badged bell, foreground SnackBar, inbox, opened/initial-message routing/focus, and tests exist.
- **Panel question:** “Show us the notification inbox.”
- **Best defense:** “The inbox and role-aware routing paths are implemented and locally tested. Session pushes open the schedule; assessment and eligibility pushes resolve an authorized Player/Guardian destination behind existing privacy gates; unknown events use the inbox. Physical-device FCM delivery still needs environment evidence.”
- **Regression guard:** current-user scoping/read-state tests plus Flutter model/repository/widget tests.

### W5. Training-time integrity (resolved)

- **Evidence:** model and serializer share `validate_time_window()` for paired 12-hour parsing, normalization, and strict chronology.
- **Panel question:** “Can a session end before it starts?”
- **Best defense:** “No through supported API, admin/form, or ORM save paths; invalid pairs are rejected before persistence.”
- **Regression guard:** create/update/model tests cover missing, malformed, equal, and reversed times.

### W6. Ratings lack full database enforcement

- **Evidence:** DRF enforces 0–99, but comprehensive model/DB check constraints were not found.
- **Panel question:** “Can Django admin or a script save 150?”
- **Best defense:** “Serializer clients cannot, but alternate ORM paths are not equally protected.”
- **Fix:** model validators + database `CheckConstraint`s and migration tests.

### W7. Confirmation failure visibility (resolved)

- **Evidence:** the widget checks the controller's false result, shows a retry-oriented SnackBar, and renders **Retry RSVP** for initial-load errors.
- **Panel question:** “How does a player know the RSVP failed?”
- **Best defense:** “The intended state is not shown as saved; the player gets visible feedback and can retry.”
- **Regression guard:** widget tests cover load and submit failures.

### W8. Offline read fallback (resolved and scoped)

- **Evidence:** attendance fallback catches only `AttendanceNetworkException`; the shared GET cache also falls back only before an HTTP response and keys entries by owner UID.
- **Panel question:** “Could offline data hide a permission error?”
- **Best defense:** “No. HTTP auth/server responses remain errors and never become cached or queued success.”
- **Regression guard:** tests distinguish network exceptions from 401/403/500 behavior.

### W9. API client behavior (centralized)

- **Evidence:** academy `Api*Repository` adapters delegate authentication, timeout, typed errors, safe detail extraction, multipart, and GET-cache policy to `AuthenticatedApiClient`.
- **Panel question:** “What happens if a request hangs?”
- **Best defense:** “The shared client ends the request after 15 seconds and surfaces a typed network error or a safe owner-scoped cached GET when eligible.”
- **Regression guard:** shared-client tests cover timeout, HTTP, decode, privacy-header, and cache cases.

### W10. Specification drift

- **Evidence:** README architecture is now reconciled; requirements say 1–10 while code uses 0–99; older audit snapshots also predate the current CI and hardening work.
- **Panel question:** “Which document should we believe?”
- **Best defense:** “Executable code/migrations and the current architecture docs describe the delivered system; the remaining requirements discrepancy is disclosed rather than hidden.”
- **Fix:** reconcile the approved requirements and require change-linked acceptance criteria.

## Documentation and specification drift

- Root README architecture now matches the implemented Firebase-identity/Django-authority design.
- Current requirements mention a 1–10 performance rubric, while code validates/stores 0–99 ratings.
- Planning artifacts mention match statistics and other later features that are absent.
- Older audit documents say CI was absent, but `.github/workflows/ci.yml` now exists.

Repository code and migrations describe current behavior; requirements should be reconciled before final submission.

## Honest limitation response

> Our strongest completed paths are identity/authorization, invariant-preserving Player provisioning, player development, schedules, attendance with owner-scoped offline handling, eligibility history, injuries, disputes, guardian privacy, persistent notifications with role-aware routing, and Coach photo upload. We have not implemented AI, scouting, match statistics, or chat. The repository includes production/runbook/backup/restore artifacts, but we do not claim a live deployment, exercised monitoring, scheduled backup, restore drill, or physical-device external-service result without evidence.

## Pre-defense hardening priority

1. Retain a signed live-device Firebase/FCM/Supabase walkthrough record.
2. Reconcile the remaining approved rating-scale requirement discrepancy.
3. Add remaining database rating checks.
4. Add assessment-history snapshots and pagination/server search.
5. Execute and retain evidence of Android/iOS push delivery against the real Firebase/APNs configuration.
6. Retain the current 241/241 Django and 240/240 Flutter outputs with the clean analyzer result.
7. Execute and record a disposable live deployment/readiness/alert test.
8. Execute and record scheduled backup plus isolated restore; complete privacy retention and incident procedures.
