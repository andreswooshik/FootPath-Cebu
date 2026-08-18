# Testing, Verification, and Limitations

## Current verification result (2026-08-18)

| Check | Result | Interpretation |
|---|---|---|
| `flutter analyze` | PASS — no issues found | Flutter static analyzer accepted the current app |
| `flutter test` | PASS — 184 tests | Current Flutter test suite passed in this workspace |
| `python -m compileall -q backend` | PASS | Python source is syntactically compilable |
| `python manage.py check` | NOT RUN TO COMPLETION | Active local Python environment lacks installed `axes`, although it is declared in `backend/requirements.txt` |
| Django tests | NOT EXECUTED LOCALLY | Same missing-dependency environment blocker; do not report pass/fail from this run |
| GitHub Actions definition | PRESENT | CI installs requirements, runs Django tests/deploy check, Flutter analyze/test |

The verified local run completed all 212 Django tests and all 184 Flutter tests. The CI file remains evidence of the intended automated gates, not proof that the latest remote run passed.

## What the automated tests cover

The inspected suites contain coverage for:

- authentication/profile routing and role behavior;
- entity JSON conversion and use-case/controller delegation;
- mock and API repository behavior;
- screen/widget loading, error, validation, and interaction states;
- attendance queue ownership/replay and offline behavior;
- Django roles, club scoping, API validation, attendance, sessions, profiles, progress, injuries, disputes, eligibility, PIN/unlock, notifications, and portal workflows;
- account provisioning and compensation cases;
- production-oriented settings checks through CI.

Exact coverage percentage is not configured/reported, so do not claim “100% coverage.”

## Testing-type assessment

| Type | Current repository evidence | Status |
|---|---|---|
| Unit tests | Dart entity/use-case/repository/controller tests; Django service/model/view-focused tests | Implemented |
| Widget tests | Flutter screens/widgets render and simulate interactions/states | Implemented |
| API/integration-style tests | Django test client exercises endpoints, authz, persistence, portal workflows | Implemented in suite; not executed in this local review |
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
| Assessment | Same-club valid save | profile/audit saved; push scheduled after commit | Tests/source present; live FCM should be manual |
| Session | End before start | Should reject | **Current gap:** cross-field validation not found |
| Attendance | Valid in-window full batch | atomic upsert and omitted-row prune | Backend/client tests present |
| Offline attendance | Network write failure | current owner’s batch queued | Flutter tests pass |
| Offline attendance | Switch account before sync | other owner’s rows not replayed | Flutter tests pass |
| Confirmation | Player responds for non-today session | reject | Backend test coverage present; UX error visibility gap |
| Eligibility | Staff changes same-club status | current + history + audit, then push | Backend tests/source present |
| Injury | Guardian attempts write | 403 | Backend tests present |
| File upload | spoofed MIME/oversize image | validation error; path unchanged | Backend tests/source present |
| Provisioning | Firebase succeeds then DB fails | new Firebase identity compensated | provisioning tests exist |
| Player provisioning invariant | Coordinator/Admin flow creates player | role + non-null Club + exactly one profile; optional link same Club | **Implemented and regression-tested** |
| Notifications | foreground push while app open | visible feedback/navigation | **Not implemented; test cannot pass yet** |
| Session cancel failure | notification send occurs but delete later fails | avoid inconsistent “cancelled” push | **Risk:** current send precedes delete; add transactional/outbox design |
| Release config | HTTP API URL | build/runtime configuration rejects unsafe endpoint | source/test/CI evidence present |
| Deployment | restore latest backup | defined recovery-time/data result | **No completed evidence found** |

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
5. Notifications have backend send and token registration but lack a complete visible receive/inbox/deep-link experience.
6. Player-photo upload is web/admin only.
7. No historical performance-assessment snapshots; profile ratings overwrite.
8. No stored grades; only eligibility status/history.
9. Only attendance writes have offline support; most other operations require connectivity.
10. Search/filter is client-side over a loaded roster and is not paginated.
11. No complete production infrastructure manifest, monitoring dashboard, backup/restore evidence, or live-deployment proof was found.
12. Mobile navigation has no deep-link/named-route structure.

## Technical limitations

- Only attendance writes have an offline persistence/replay design.
- Current assessments overwrite rather than forming a time series.
- Some API adapters duplicate token/status handling without a uniform timeout/retry contract.
- Client-side roster filtering and unpaginated responses assume modest club size.
- Notification receive/history/navigation is incomplete.
- Several important invariants are serializer/service-level rather than database-enforced.

## Operational limitations

- Firebase, reachable Django, correct secrets, and optionally Supabase/Redis must be configured for live mode.
- No verified production URL, observability/alerting evidence, backup schedule, or restore-test result was found.
- No complete child-data consent/retention/deletion/incident-response procedure was verified.
- Local Django execution requires an isolated environment with all declared requirements; the active review environment lacked Axes.
- A physical-device demo requires a device-reachable API address and `USE_MOCK=false`.

## Future improvements

1. Correct and centralize all player provisioning.
2. Add database check constraints and typed chronological session time validation.
3. Add append-only performance assessment snapshots and trend views.
4. Complete FCM foreground/opened-app handling and persistent inbox/read state.
5. Centralize the authenticated API client with timeouts, typed errors, safe retry, and observability.
6. Add pagination/server search for larger multi-club deployments.
7. Establish consent, retention, deletion, audit export, incident response, backup, and restore procedures.
8. Add live Firebase/Django device E2E tests and retain release/deployment evidence.

## Known defects or high-confidence code risks

### Player provisioning invariant (resolved)

All executable player-creation paths now call
`accounts.services.provision_player`. The service requires an active Club,
creates the `PLAYER` user and exactly one `PlayerProfile` transactionally, and
validates an optional Guardian as active and same-Club. Generic admin user
creation no longer accepts `PLAYER`, and Django admin directs Player creation to
the dedicated flow.

### Progress administrator mismatch

The squad progress view’s commentary/intent includes administrator visibility, but the queryset filters using `request.user.club_id`; an administrator normally has no club. The result is incomplete admin progress data.

### Time/rating integrity

Training times are strings and no cross-field start-before-end validation was found. Ratings are API-validated at 0–99, but comprehensive database check constraints were not found.

### Error feedback

Session-confirmation submission suppresses an exception without visible feedback. API adapters commonly reduce error detail to a status-based message and lack a centralized timeout policy.

### Offline read fallback

Session-attendance fallback may catch a broad attendance repository exception and return queued data even when the cause is not connectivity. The fallback should be limited to network failures.

## Ten weakness defense cards

### W1. Player/Club invariant

- **Evidence:** `provision_player` requires the Club and creates User/Profile/link atomically; the dedicated admin path derives the Club from its selected Guardian.
- **Panel question:** “Can an account endpoint create a club-null Player?”
- **Best defense:** “No. Generic creation excludes Player and every Player flow delegates to the same invariant-preserving service.”

### W2. Generic Player creation

- **Evidence:** `CREATABLE_ROLES` excludes `PLAYER`; Django admin validation also rejects direct Player-user creation.
- **Panel question:** “What guarantees every provisioned Player has a profile?”
- **Best defense:** “Only `provision_player` can create Players, and it commits the User and one-to-one profile together or rolls everything back.”

### W3. Admin progress visibility mismatch

- **Evidence:** `SquadProgressView` allows admin but filters `request.user.club_id`, normally null.
- **Panel question:** “Does an admin see every club’s progress?”
- **Best defense:** “Not correctly in this endpoint; its query differs from the all-club squad/session behavior.”
- **Fix:** explicit admin branch and multi-club tests.

### W4. Notification experience is incomplete

- **Evidence:** token registration/send helpers exist; bell callbacks are empty and no foreground listener/inbox exists.
- **Panel question:** “Show us the notification inbox.”
- **Best defense:** “There is no complete inbox; the feature is send-side partial.”
- **Fix:** add foreground/opened-app listeners, routed actions, persistent inbox/read state, and tests.

### W5. Training times are weakly modeled

- **Evidence:** start/end are strings; no start-before-end validation found.
- **Panel question:** “Can a session end before it starts?”
- **Best defense:** “The current contract can accept that inconsistent state; this needs typed fields and cross-field validation.”
- **Fix:** migrate to `TimeField`, validate chronology in serializers/forms, update Dart format contract.

### W6. Ratings lack full database enforcement

- **Evidence:** DRF enforces 0–99, but comprehensive model/DB check constraints were not found.
- **Panel question:** “Can Django admin or a script save 150?”
- **Best defense:** “Serializer clients cannot, but alternate ORM paths are not equally protected.”
- **Fix:** model validators + database `CheckConstraint`s and migration tests.

### W7. Confirmation failures are silent

- **Evidence:** `SessionConfirmationController.submit()` returns false after catch; widget does not show it.
- **Panel question:** “How does a player know the RSVP failed?”
- **Best defense:** “They currently may not; button state resets without clear error feedback.”
- **Fix:** expose error state/SnackBar and retain retryable intended selection.

### W8. Offline read fallback is overly broad

- **Evidence:** `fetchAttendanceForSession` fallback catches broad repository exceptions.
- **Panel question:** “Could offline data hide a permission error?”
- **Best defense:** “Yes, the read fallback should be network-specific like the write branch.”
- **Fix:** catch only `AttendanceNetworkException`; surface auth/server errors.

### W9. API client behavior is duplicated

- **Evidence:** multiple `Api*Repository` files repeat token/header/status code logic and frequently omit explicit timeouts/error bodies.
- **Panel question:** “What happens if a request hangs?”
- **Best defense:** “The async UI remains renderable, but without a consistent timeout the operation can remain loading too long.”
- **Fix:** shared authenticated API client with timeouts, typed safe errors, refresh/retry policy.

### W10. Specification drift

- **Evidence:** README contains Firestore/custom-claim planning; requirements say 1–10 while code uses 0–99; older audit says CI absent though it now exists.
- **Panel question:** “Which document should we believe?”
- **Best defense:** “Executable code/migrations describe the delivered system, but traceability documents must be reconciled before submission.”
- **Fix:** update requirements/README/ADRs and require change-linked acceptance criteria.

## Documentation and specification drift

- Root README/plans contain Firestore/custom-claims language that does not match the implemented Django source-of-truth design.
- Current requirements mention a 1–10 performance rubric, while code validates/stores 0–99 ratings.
- Planning artifacts mention match statistics and other later features that are absent.
- Older audit documents say CI was absent, but `.github/workflows/ci.yml` now exists.

Repository code and migrations describe current behavior; requirements should be reconciled before final submission.

## Honest limitation response

> Our strongest completed paths are identity/authorization, player development, schedules, attendance with offline queueing, eligibility history, injuries, disputes, and guardian privacy. We have not implemented AI, scouting, match statistics, or a complete notification inbox. We also identified two admin provisioning invariants and several validation/UX gaps for the next hardening cycle. We distinguish verified tests from planned CI and do not claim deployment evidence we do not possess.

## Pre-defense hardening priority

1. Fix both admin player-provisioning paths and add regression tests.
2. Reconcile the rating scale and README architecture statements.
3. Add session time-order validation and database rating checks.
4. Make confirmation and API errors visible and typed.
5. Complete foreground notification handling or explicitly remove the bell affordance.
6. Run Django tests in a clean installed environment and retain the full output.
7. Perform a live `USE_MOCK=false` device walkthrough against a disposable seeded backend.
8. Document deployment, backup/restore, privacy retention, and incident procedures.
