# Panel Question Bank

Each item has a short answer to memorize, a stronger technical answer, and repository evidence. Do not claim planned or absent features as implemented.

## Required-category index

Questions are not duplicated when one answer covers several panel categories. Use this index for category-specific practice:

| Category | Questions |
|---|---|
| Project Questions | Q1–Q3, Q6–Q7 |
| Problem and Objectives | Q2, Q4–Q5 |
| Technical Architecture | Q11, Q13–Q17 |
| Flutter | Q12, Q14–Q15, Q18–Q20, Q63–Q66 |
| Database | Q59–Q62 |
| Authentication | Q21–Q23, Q27–Q32 |
| Security | Q24–Q34 |
| Data Privacy | Q27–Q35, Q50, Q56–Q57 |
| AI | Q8, Q47 |
| User Roles | Q3, Q24–Q26, Q36–Q58 |
| Scouting | Q9, Q51 |
| Training | Q36–Q43, Q52, Q54–Q55 |
| Academic Eligibility | Q48–Q49 |
| Performance Monitoring | Q44–Q47 |
| Testing | Q67–Q69 |
| Deployment | Q16–Q17, Q20, Q70 |
| Scalability | Q17, Q42, Q58, Q73 |
| Reliability | Q23, Q38–Q43, Q54–Q55, Q67–Q69 |
| Limitations | Q8–Q10, Q45–Q46, Q53, Q55, Q57, Q70, Q72–Q74 |
| Future Development | Q46, Q55, Q58, Q72–Q74 |
| Research/Methodology | Q4–Q7, Q45, Q67, Q75–Q80 |
| Difficult/Trick Questions | Q6, Q8–Q10, Q20, Q33–Q35, Q45–Q46, Q53, Q55, Q67–Q80 |

## Project and objectives

### Q1. What is FootPath Cebu?

- **Short:** A role-based youth football academy management system for development, training operations, safeguarding records, and controlled family access.
- **Technical:** Flutter serves coaches, players, and guardians; Django REST and web portals serve the data, authorization, coordinator, staff, and admin workflows.
- **Evidence:** `footpath_cebu/lib/presentation/screens/home_screen.dart`; `backend/academy/models.py`; `backend/portal/views.py`.

### Q2. What problem does it solve?

- **Short:** It replaces fragmented academy records with one club-scoped system.
- **Technical:** It connects roster/profile data, sessions, attendance, assessments, eligibility history, injuries, and disputes to authenticated users and relational records.
- **Evidence:** `backend/academy/models.py`; `docs/REQUIREMENTS.md`.

### Q3. Who are the users?

- **Short:** Super Admin, Club Coordinators, coaches, players, school staff, and guardians.
- **Technical:** All six exist in the backend role enum; `ADMIN` is the backward-compatible wire value for Super Admin. Coach/player/guardian have dedicated mobile portals, while Super Admin/coordinator/staff use web interfaces.
- **Evidence:** `backend/accounts/models.py`; `home_screen.dart`; `backend/portal/`.

### Q4. What is the general objective?

- **Short:** To centralize academy development and operations securely for each authorized role.
- **Technical:** This is reconstructed from requirements and code because a formally labeled objective statement was not found.
- **Evidence:** `docs/REQUIREMENTS.md`; modules in `backend/academy/` and `footpath_cebu/lib/`.

### Q5. What are the main specific objectives?

- **Short:** Digitize development records, schedules/attendance, controlled family visibility, traceable eligibility/disputes, and secure club administration.
- **Technical:** Each maps to an implemented model plus mobile/web workflow; offline attendance adds field reliability.
- **Evidence:** `academy/models.py`; `offline_first_attendance_repository.dart`; `portal/services.py`.

### Q6. Why is it called FootPath Cebu if there is no mapping?

- **Short:** The implemented meaning is a football-development pathway, not GPS navigation.
- **Technical:** No map, route, geolocation, or tracking dependency/workflow exists in executable source; the name should be explained as branding.
- **Evidence:** Flutter dependency list and repository-wide source search.

### Q7. What is your project’s unique value?

- **Short:** It combines development operations with layered role/club privacy and offline attendance.
- **Technical:** Firebase identity, Django RBAC/tenancy, household PIN unlock, audit/history, and a user-scoped outbox work together.
- **Evidence:** `accounts/authentication.py`; `pin_service.py`; `attendance_outbox.dart`.

### Q8. Is this an AI system?

- **Short:** No.
- **Technical:** Ratings are human-entered and progress is deterministic aggregation; no inference model, AI service, training pipeline, or predictive endpoint was found.
- **Evidence:** `academy/views.py`; `api_progress_repository.dart`; dependency manifests.

### Q9. Does the system have scouting?

- **Short:** No scout role or scouting report is implemented.
- **Technical:** A coach can raise a dispute/concern, but that is an internal issue workflow and not recruitment/scouting.
- **Evidence:** `accounts/models.py`; `academy/models.py`; `dispute_providers.dart`.

### Q10. What is outside current scope?

- **Short:** AI, scouting, match stats, chat, maps, mobile registration, and historical assessment versions.
- **Technical:** These lack executable models/endpoints/screens, even if older planning text mentions some of them.
- **Evidence:** source inventory; `README.md` and `docs/REQUIREMENTS.md` versus executable source.

## Architecture and technology

### Q11. What architecture did you use?

- **Short:** Layered Flutter clean architecture connected to a layered Django REST backend.
- **Technical:** Presentation calls domain use cases/contracts; data adapters implement external access. Django provides authentication, views, serializers/services, ORM models, and web portals.
- **Evidence:** `footpath_cebu/lib/{presentation,domain,data}`; `backend/{accounts,academy,portal}`.

### Q12. Why Flutter?

- **Short:** One typed UI codebase supports the role-based mobile experience.
- **Technical:** Flutter’s widget tests, Riverpod state, and adapter boundaries fit the three mobile portals and allow mock/live implementations.
- **Evidence:** `pubspec.yaml`; `presentation/`; `test/`.

### Q13. Why Django REST Framework?

- **Short:** It centralizes secure APIs, relational validation, web operations, and admin features.
- **Technical:** DRF serializers and permissions sit alongside Django ORM transactions, templates, admin, and middleware in one backend.
- **Evidence:** `requirements.txt`; `academy/views.py`; `serializers.py`; `portal/`.

### Q14. What is Riverpod doing?

- **Short:** Dependency injection and reactive async UI state.
- **Technical:** Providers assemble repositories/use cases, expose `AsyncValue` reads, manage mutation state, and invalidate data after writes.
- **Evidence:** `core/di/providers.dart`; `presentation/providers/`.

### Q15. Where is the composition root?

- **Short:** `core/di/providers.dart`.
- **Technical:** It selects mock/live repositories and wires domain use cases to controllers; `ProviderScope` activates the graph at startup.
- **Evidence:** `providers.dart`; `main.dart`.

### Q16. Is the backend Firebase or Supabase?

- **Short:** Django is the backend; Firebase supplies identity/push and Supabase is optional infrastructure.
- **Technical:** Django verifies Firebase tokens and owns authorization/ORM. Supabase may host PostgreSQL and private photos, but Flutter does not access it directly.
- **Evidence:** `settings.py`; `accounts/authentication.py`; `academy/storage.py`.

### Q17. Why not let Flutter call Supabase directly?

- **Short:** Central server authorization and secret isolation.
- **Technical:** Django can enforce roles, clubs, guardian links, transactions, audit, and storage mediation uniformly without distributing a service credential or duplicating policy.
- **Evidence:** `settings.py` comments; API repositories; `storage.py`.

### Q18. How is navigation implemented?

- **Short:** Role-based home selection plus direct `Navigator` routes and tab shells.
- **Technical:** There is no named/declarative router; portals use `IndexedStack` to retain bottom-tab state.
- **Evidence:** `home_screen.dart`; `portal_shell.dart`; screen `MaterialPageRoute` calls.

### Q19. How do mock and live modes differ?

- **Short:** The composition root swaps repository implementations.
- **Technical:** Debug defaults to mock unless `USE_MOCK=false`; release forces live API/Firebase behavior. Domain and screens remain unchanged.
- **Evidence:** `api_config.dart`; `providers.dart`; `mock_*` and `api_*` repositories.

### Q20. What is the risk of mock mode?

- **Short:** A demo could look functional without proving persistence.
- **Technical:** Since debug defaults to mock, the team must show live configuration, backend logs/database changes, and cross-role effects before claiming integration.
- **Evidence:** `api_config.dart`; `providers.dart`.

## Authentication, roles, and privacy

### Q21. Explain login end to end.

- **Short:** Firebase validates credentials, then Django validates the token and returns the authorized local profile.
- **Technical:** Flutter signs in, obtains an ID token, calls `/api/auth/me/`, Django checks revocation and maps UID to an active club-scoped user, then role routing occurs.
- **Evidence:** `login_screen.dart`; `firebase_auth_repository.dart`; `accounts/authentication.py`; `accounts/views.py`.

### Q22. Why call `/api/auth/me/` after Firebase login?

- **Short:** Firebase knows identity; Django knows academy role and club.
- **Technical:** It blocks Firebase-only accounts and retrieves the server-authoritative local `UserProfile` used for routing.
- **Evidence:** `firebase_auth_repository.dart`; `MeView`; `UserSerializer`.

### Q23. How is an existing session restored?

- **Short:** The app checks Firebase state, refreshes the token, and reauthorizes with Django.
- **Technical:** It does not trust a cached role. A 401/403 signs out; other failures can be retried.
- **Evidence:** `session_bootstrap_screen.dart`; `restore_session.dart`; `firebase_auth_repository.dart`.

### Q24. Where is access control enforced?

- **Short:** On Django, not only in Flutter.
- **Technical:** Token authentication is followed by endpoint role checks, club-filtered querysets, object ownership, and guardian-link/unlock verification.
- **Evidence:** `accounts/permissions.py`; `academy/views.py`; `player_unlock.py`.

### Q25. Can a user change their role in a request?

- **Short:** No; the backend reads role from the local authenticated user.
- **Technical:** Role and club decisions are not accepted from ordinary feature payloads. Client routing is only presentation.
- **Evidence:** `accounts/models.py`; authentication and view role checks.

### Q26. How is club isolation achieved?

- **Short:** Users and sessions carry a club, and server queries restrict objects to the caller’s club.
- **Technical:** Same-club lookups protect roster, sessions, attendance, assessments, and portal operations; non-admin users without a club are rejected during auth.
- **Evidence:** `accounts/authentication.py`; `academy/views.py`; `portal/services.py`.

### Q27. How does guardian access work?

- **Short:** Login, verified guardian link, player PIN, then a short-lived signed unlock token.
- **Technical:** The token is bound to guardian and player, valid ten minutes, memory-only in Flutter, and rechecked with the link on protected requests.
- **Evidence:** `pin_service.py`; `player_unlock.py`; `player_unlock_token_store.dart`.

### Q28. Is the player PIN encrypted?

- **Short:** It is one-way hashed, which is more appropriate than reversible encryption.
- **Technical:** Django `make_password` uses the configured hasher chain with Argon2 first; verification compares a candidate without recovering plaintext.
- **Evidence:** `pin_service.py`; password hasher setting in `settings.py`.

### Q29. What prevents PIN brute force?

- **Short:** Five failed attempts trigger a 15-minute lock.
- **Technical:** The PIN row is locked in a database transaction so concurrent failures cannot safely bypass the counter.
- **Evidence:** `academy/pin_service.py`.

### Q30. How is a PIN reset protected?

- **Short:** It requires recent Firebase reauthentication.
- **Technical:** The backend checks token authentication time within five minutes; the client reauthenticates before requesting reset.
- **Evidence:** `reauthenticate.dart`; auth repository; PIN reset view.

### Q31. How are web logins protected?

- **Short:** Django sessions, CSRF, strong hashing/validators, and Axes lockout.
- **Technical:** Five failed session logins cause a 30-minute lock; Argon2 is first in password hashers.
- **Evidence:** `settings.py`; `portal/`; `requirements.txt`.

### Q32. What happens if a Firebase token is revoked?

- **Short:** Django rejects it.
- **Technical:** Firebase Admin verification uses `check_revoked=True` for API authentication.
- **Evidence:** `accounts/authentication.py`.

### Q33. Are secrets in Flutter?

- **Short:** Privileged server secrets should not be; Firebase client config is not a Firebase Admin secret.
- **Technical:** Django holds service-account, Django signing, DB, and Supabase service-role credentials through ignored/env configuration.
- **Evidence:** `settings.py`; `.env.example`; `academy/storage.py`; Firebase client option files.

### Q34. Do you use Supabase RLS?

- **Short:** No, because the app never queries Supabase directly.
- **Technical:** Django authorization and database queries are the policy boundary; Supabase is only a host/storage service in this topology.
- **Evidence:** explicit comments in `backend/config/settings.py`; `academy/storage.py`.

### Q35. What privacy law concerns remain?

- **Short:** Child-development/injury data needs consent, retention, access, deletion, and breach procedures.
- **Technical:** Code has minimization/access controls, but a complete Philippine Data Privacy Act governance package was not found.
- **Evidence:** stored fields in `academy/models.py`; absence of governance artifacts in repository.

## Core workflows

### Q36. How is a training session created?

- **Short:** Coach form → use case/API → coach/club validation → session save → audit/notification → refresh.
- **Technical:** Django assigns creator and club rather than trusting the payload and schedules FCM after commit.
- **Evidence:** `schedule_session_screen.dart`; `api_training_repository.dart`; session create view.

### Q37. Who can edit or cancel a session?

- **Short:** An authorized coach in the session’s club.
- **Technical:** The detail endpoint applies role and club-scoped lookup before PUT/DELETE.
- **Evidence:** `academy/views.py`; training repository use cases.

### Q38. What happens to attendance when a session is deleted?

- **Short:** Attendance history remains with a null session reference.
- **Technical:** The foreign key uses `SET_NULL`; confirmations use `CASCADE` and are removed.
- **Evidence:** `academy/models.py`.

### Q39. How is attendance recorded?

- **Short:** A coach submits the session’s complete marked roster as a batch.
- **Technical:** The backend validates coach, club, date window, player IDs, statuses/effort, then atomically upserts sent rows and deletes omitted rows.
- **Evidence:** `log_attendance_screen.dart`; `api_attendance_repository.dart`; attendance view.

### Q40. Why batch attendance?

- **Short:** It finalizes one coherent session roster in one transaction.
- **Technical:** Whole-set replacement avoids partially saved rows and makes offline queue serialization/replay straightforward.
- **Evidence:** attendance log use case/repository/view.

### Q41. How does offline attendance work?

- **Short:** Network-failed writes enter a user-scoped local queue and replay later.
- **Technical:** The decorator queues only `AttendanceNetworkException`, stores JSON in sqflite, and syncs oldest first; success deletes and failure records retry state.
- **Evidence:** `offline_first_attendance_repository.dart`; `attendance_outbox.dart`; `attendance_sync_service.dart`.

### Q42. What is the offline conflict strategy?

- **Short:** Ordered replay with later complete batches winning.
- **Technical:** There is no field merge/version vector. The replacement endpoint plus sequential queue gives a simple last-write-wins outcome.
- **Evidence:** outbox/sync service and attendance endpoint semantics.

### Q43. Can queued attendance leak between users on one phone?

- **Short:** The queue is filtered by Firebase owner UID.
- **Technical:** Each row stores `owner_uid`; sync loads/replays only the current owner’s items.
- **Evidence:** `attendance_outbox.dart`; `attendance_sync_service.dart`.

### Q44. How is player performance saved?

- **Short:** A coach updates twelve 0–99 ratings and notes for a same-club player.
- **Technical:** Flutter sends nested ratings; the serializer validates and flattens them into `PlayerProfile`; audit and notification follow.
- **Evidence:** `edit_performance_data_screen.dart`; `api_player_repository.dart`; assessment serializer/view.

### Q45. Why 0–99 instead of 1–10?

- **Short:** The current code uses 0–99; the requirements document is inconsistent.
- **Technical:** UI/domain/serializer fields align to 0–99. The team must reconcile the specification instead of claiming both.
- **Evidence:** player entities/editor/serializers versus `docs/REQUIREMENTS.md`.

### Q46. Is performance history retained?

- **Short:** No; only the current profile ratings and notes are stored.
- **Technical:** There is no assessment/version model, so a new save overwrites current fields.
- **Evidence:** `PlayerProfile` in `academy/models.py`; migrations.

### Q47. How is progress computed?

- **Short:** Django aggregates deterministic attendance/effort data per player.
- **Technical:** The progress endpoint uses ORM counts/averages and returns `PlayerProgress`; this is analytics, not AI.
- **Evidence:** `SquadProgressView`; `api_progress_repository.dart`.

### Q48. How is eligibility changed?

- **Short:** School staff update status in the portal; signals create history and audit.
- **Technical:** `pre_save` captures the old status and `post_save` creates old/new history and an on-commit notification.
- **Evidence:** `portal/views.py`; `academy/signals.py`; `EligibilityHistory`.

### Q49. Are student grades stored?

- **Short:** No, only eligibility status and change history.
- **Technical:** UI language can imply grades, but no grade fields/model/endpoints exist.
- **Evidence:** `PlayerProfile` and `EligibilityHistory` models.

### Q50. Who owns injury records?

- **Short:** The player creates, edits, and deletes their own injuries.
- **Technical:** Coaches/admin and unlocked linked guardians have authorized reads, but write endpoints derive ownership from the player caller.
- **Evidence:** injury views; `api_injury_repository.dart`; injury screens.

### Q51. How do disputes work?

- **Short:** A coach raises a club-scoped concern; authorized participants append responses and status changes.
- **Technical:** `DisputeResponse` is timestamped and append-only; optional status transitions occur transactionally.
- **Evidence:** dispute models/views; `api_dispute_repository.dart`.

### Q52. How does player session confirmation work?

- **Short:** A player responds only for their own session scheduled today.
- **Technical:** The backend derives player from the token and uses `update_or_create` for the player/session pair.
- **Evidence:** `session_confirmation_button.dart`; confirmation repository/view/model.

### Q53. What is incomplete about confirmations?

- **Short:** Submission errors are caught without visible user feedback.
- **Technical:** This can leave the player uncertain whether the RSVP persisted; controller state should surface a retryable error.
- **Evidence:** session confirmation widget/controller.

### Q54. How do notifications work?

- **Short:** Django sends selected FCM pushes to registered device tokens after commits.
- **Technical:** Schedule, assessment, and eligibility events fan out through `academy/notifications.py`; invalid token cleanup is supported.
- **Evidence:** device repository/endpoints; `academy/notifications.py`; signals/views.

### Q55. Are notifications fully implemented?

- **Short:** No; sending/registration exist, but the in-app receive/inbox experience is incomplete.
- **Technical:** Bell callbacks are empty and no foreground listener/deep-link path was found.
- **Evidence:** coach/schedule screens; lack of Firebase Messaging listeners in `lib/`.

### Q56. How are player photos stored?

- **Short:** Django validates and uploads private objects to optional Supabase Storage.
- **Technical:** A service-role REST call stays server-side; reads use signed URLs and degrade when storage is unconfigured.
- **Evidence:** `academy/storage.py`; admin/portal upload views.

### Q57. Can players upload photos in Flutter?

- **Short:** No; upload is coordinator/admin web-side, while Flutter can display returned URLs.
- **Technical:** No Flutter picker/upload repository or endpoint call was found.
- **Evidence:** portal/admin photo handlers; player-card/profile image rendering.

### Q58. How does roster search work?

- **Short:** It filters the already loaded squad in memory.
- **Technical:** `RosterFilter.apply` uses local name/tier/position criteria; it is not server pagination/search.
- **Evidence:** squad providers/screens.

## Database, correctness, and OOP

### Q59. What database do you use?

- **Short:** SQLite by default/test and PostgreSQL when configured, optionally hosted by Supabase.
- **Technical:** Django’s engine changes via environment settings; domain code and ORM queries do not change.
- **Evidence:** `backend/config/settings.py`; `.env.example`.

### Q60. Why relational storage?

- **Short:** The domain depends on clear links, uniqueness, transactions, and history.
- **Technical:** Guardian-player, player-profile, player-session, and dispute-response relations benefit from FKs and database constraints.
- **Evidence:** `accounts/models.py`; `academy/models.py`.

### Q61. What constraints prevent duplicates?

- **Short:** Unique guardian links, attendance per player/session, confirmation per player/session, device tokens, and age tiers.
- **Technical:** Model constraints supplement `update_or_create` and serializer validation.
- **Evidence:** model `unique_together`/unique fields and migrations.

### Q62. Why use transactions?

- **Short:** To keep multi-record state all-or-nothing.
- **Technical:** Attendance replacement, provisioning, PIN counters, and dispute response/status changes must not leave partial records.
- **Evidence:** service/view `transaction.atomic()` usages.

### Q63. What is polymorphic in the Flutter code?

- **Short:** Different repositories implement the same domain contracts.
- **Technical:** API and mock adapters—and the offline attendance decorator—can be injected without changing use cases/screens.
- **Evidence:** `domain/repositories/`; `data/repositories/`; `providers.dart`.

### Q64. Why use use-case classes if they are thin?

- **Short:** They name application actions and isolate UI from data mechanisms.
- **Technical:** They provide a stable seam for validation/policy/tests and preserve dependency inversion even when current behavior delegates.
- **Evidence:** `domain/usecases/`; controller tests.

### Q65. What is composition in your code?

- **Short:** The offline attendance repository wraps a live repository and an outbox.
- **Technical:** It adds behavior without subclassing the HTTP adapter, keeping each component replaceable.
- **Evidence:** `offline_first_attendance_repository.dart` constructor/implementation.

### Q66. Where is encapsulation visible?

- **Short:** Repositories hide transport/storage and PIN services hide security mechanics.
- **Technical:** Screens handle domain values rather than Firebase Admin, raw SQL, storage credentials, or hash operations.
- **Evidence:** repository contracts; `pin_service.py`; `storage.py`.

## Testing, deployment, and limitations

### Q67. What tests currently pass?

- **Short:** In this workspace, Flutter analyze passes, all 184 Flutter tests pass, and all 212 Django tests pass.
- **Technical:** The backend suite, including the exact 24-case Club hierarchy security matrix, completed successfully.
- **Evidence:** verified local run on 2026-08-18.

### Q68. How many backend tests are there?

- **Short:** The current Django suite executes 212 tests.
- **Technical:** All 212 passed locally, including 24 dedicated account-and-Club hierarchy regressions.
- **Evidence:** `backend/accounts/tests.py`, `test_provisioning.py`, `academy/tests.py`, `portal/tests.py`.

### Q69. Do you have CI?

- **Short:** Yes, GitHub Actions defines backend and Flutter jobs.
- **Technical:** It installs dependencies, runs Django tests and deployment checks, then Flutter analyze/test on pushes to main and pull requests.
- **Evidence:** `.github/workflows/ci.yml`.

### Q70. Is the system production deployed?

- **Short:** The repository shows production configuration and a plan, not proof of a live deployment.
- **Technical:** No complete infrastructure manifest, monitoring evidence, active URL, or backup/restore result was verified.
- **Evidence:** `settings.py`, CI, and planning docs; absence of deployment artifact/proof.

### Q71. What is your biggest technical strength?

- **Short:** Server-authoritative security combined with offline attendance resilience.
- **Technical:** Identity/authz separation, club/object checks, PIN unlock, transactions, and owner-scoped ordered replay address realistic risks.
- **Evidence:** authentication/views/PIN files and offline attendance files.

### Q72. What is your biggest defect?

- **Short:** Admin player provisioning can violate the required club/profile invariants.
- **Technical:** One path omits club; another permits a player user without `PlayerProfile`. Both need one centralized service and regression tests.
- **Evidence:** `accounts/views.py`; admin serializers/services; `PlayerProfile` expectations.

### Q73. Why is `academy/views.py` a maintainability risk?

- **Short:** It concentrates many workflows and repeated authorization/query logic.
- **Technical:** Large view modules increase coupling and inconsistent edge cases; scoped services and reusable queryset/permission helpers would improve reviewability.
- **Evidence:** size and breadth of `backend/academy/views.py`.

### Q74. What would you improve first before defense?

- **Short:** Fix provisioning invariants, reconcile specs, run backend tests in a clean environment, and demonstrate live mode.
- **Technical:** Then add time/rating DB validation, visible errors, and complete notification receive behavior.
- **Evidence:** identified code risks, test result, `ApiConfig` mock default.

### Q75. Why should the panel trust your claims?

- **Short:** Every claim is tied to executable paths, and absent/partial features are labeled honestly.
- **Technical:** The review distinguishes planning documents from models/endpoints/screens and distinguishes static test counts, local execution, CI definition, and deployment proof.
- **Evidence:** this reviewer’s cited paths and the 2026-08-18 verification record.

### Q76. What development methodology did the team use?

- **Short:** The repository contains phased/day execution plans and CI, but no single formally approved methodology artifact was verified.
- **Technical:** Commit history/plans suggest iterative implementation and audit/refactor cycles; it would be overclaiming to label that Scrum without sprint roles, ceremonies, backlog, and empirical records.
- **Evidence:** `docs/footpath-execution-plan.md`, `docs/implementation-plan.md`, audit documents, `.github/workflows/ci.yml`.

### Q77. How did you trace requirements to implementation?

- **Short:** Each derived objective is mapped to a feature, code path, table, and executable evidence.
- **Technical:** Conflicts are recorded rather than hidden—for example Firestore planning versus Django ORM and 1–10 requirements versus 0–99 code.
- **Evidence:** objective matrix in `01-project-overview.md`; actual models/views/entities; `docs/REQUIREMENTS.md`.

### Q78. How were stakeholder roles identified?

- **Short:** The delivered roles come from the backend role enum and actual interfaces.
- **Technical:** Six operational roles are verifiable in code. A formal stakeholder interview/validation dataset was not found, so research claims beyond repository roles need the team’s external capstone records.
- **Evidence:** `backend/accounts/models.py`; `home_screen.dart`; `backend/portal/`.

### Q79. What evidence shows usability or user acceptance?

- **Short:** Widget behavior is tested, but a formal user-acceptance study or SUS report was not found in the repository.
- **Technical:** Automated UI tests verify expected interactions; they do not substitute for representative user observation, acceptance criteria sign-off, or usability metrics.
- **Evidence:** `footpath_cebu/test/`; absence of a completed usability study artifact.

### Q80. How would you evaluate whether the objectives were achieved?

- **Short:** Use objective-linked acceptance tests, role-based live demonstrations, integrity/security cases, and stakeholder sign-off.
- **Technical:** Measure successful end-to-end persistence and correct rejection for each mapped flow, offline replay reliability, defect rates, task completion/usability, and deployment/recovery evidence—without counting absent AI/scouting as achieved.
- **Evidence:** objective matrix, testing matrix, demo script, CI definition, and known-gap register.

## Rapid drill: strongest 15 answers

1. Django is the data and authorization authority.
2. Firebase proves mobile identity and sends push.
3. Supabase is optional PostgreSQL/private storage, never direct client authorization.
4. Six backend roles; three dedicated mobile portals.
5. No public mobile signup; active accounts are provisioned.
6. Guardian reads add link + PIN + signed ten-minute token.
7. Attendance alone has offline write resilience.
8. Ratings are current 0–99 values; requirements saying 1–10 are stale/inconsistent.
9. Eligibility status is stored; grades are not.
10. No AI, scouting, match stats, chat, or mapping.
11. Notifications are partially implemented.
12. Flutter analysis and all 184 tests pass locally.
13. All 212 Django tests pass locally.
14. Two admin provisioning paths can violate player invariants.
15. A live defense must run with `USE_MOCK=false`.
