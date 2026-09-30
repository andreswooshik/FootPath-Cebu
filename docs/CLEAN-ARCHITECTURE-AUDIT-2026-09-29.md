# Clean code and architecture audit

Date: 2026-09-29. Reviewed backend first, then Flutter frontend. Findings describe the current working tree, including existing uncommitted changes. No application code was changed for this audit.

The findings below preserve the original audit. The subsequent implementation and verification are recorded at the end of this document.

## Assessment

The backend is a modular Django application with partially extracted application services, rather than a framework-independent Clean Architecture implementation. Keeping Django models is a reasonable choice; the more urgent problem is inconsistent ownership of workflows, transactions, and errors.

Flutter has stronger enforced boundaries: domain imports remain independent of Flutter and infrastructure, repository contracts exist, and presentation does not directly import data adapters. Remaining gaps are in dependency wiring, wire-format ownership, and mutations still owned by widgets.

Priorities: P1 = data integrity issue to address first; P2 = functional or architectural issue for the next refactoring pass. Risks below are distinguished from behavior reproduced by tests.

## Backend findings

### B1 — P1: Injury changes and their audit records do not commit atomically

Evidence: `backend/academy/view_injuries.py:275` opens a transaction for review, but the audit write at line 311 occurs after that transaction exits. The same pattern occurs for status requests at lines 356/390 and status reviews at lines 407/450. Archive at lines 325–343 also saves the injury and records the audit as separate operations. `ATOMIC_REQUESTS` is not enabled in the inspected settings.

If the audit insert fails, the injury change remains committed while the request can fail. A retry may then reject the already-completed transition, and the required audit entry is missing. `AuditLog.record()` having its own transaction does not make it atomic with an already-committed injury update.

Recommendation: extract explicit injury application services that own authorization, state-transition validation, row locks, mutation, and the audit insert within one transaction. Views should validate transport input and translate results. Add a failure-injection test that makes the audit insert fail and verifies the injury/update request rolls back. This failure scenario was identified from transaction boundaries, not reproduced during this audit.

### B2 — P2: Tournament publication is implemented independently in two adapters

Evidence: `backend/academy/view_tournaments.py:253` and the publication branch of `backend/portal/view_tournaments.py:130` each orchestrate publication validation, fixture selection, conflict confirmation, published timestamps, training cancellation, and auditing.

Both paths use the club-write transaction decorator, so this finding is not a claim that the portal lacks scheduling serialization. The problem is duplicated policy and orchestration. Confirmation is already interpreted differently: the API uses `_confirmed()` with explicit accepted values, while the portal treats any nonempty POST value as confirmation.

Recommendation: introduce a shared `publish_tournament(actor, schedule_id, confirm_cancellations)` service, with a typed conflict/result. Let adapters parse their inputs and render their respective HTTP or template responses. Use the existing shared tournament-result and dispute services as local precedents. Test API/portal parity for validation, cancellation confirmation, and repeat publication.

### B3 — P2: Application services use incompatible transport-dependent errors

Evidence: `backend/academy/attendance_service.py:9` uses Django's HTTP-oriented `get_object_or_404`, and line 11 imports DRF exceptions. `backend/academy/dispute_service.py:4` also imports DRF exceptions. `backend/accounts/registration_service.py:25` defines a conflict as `APIException`, while `backend/academy/eligibility_service.py:3` uses Django core exceptions. `backend/academy/errors.py:7` defines a workflow conflict directly as an HTTP exception.

This makes shared workflows depend on the REST adapter and forces portal/command callers to know several error conventions. It also makes it harder to test workflow behavior separately from response representation.

Recommendation: use one small application-error vocabulary for forbidden operations, invalid input, missing objects, and workflow conflicts. Preserve stable machine-readable codes and details, then translate into DRF responses, form errors, or command errors at entry points. This can be incremental; it does not require replacing the Django ORM with a generic repository layer.

## Frontend findings

### F1 — P2: Mock mode still wires Player Stats to the live API

Evidence: `footpath_cebu/lib/core/di/providers.dart:131` constructs `ApiPlayerStatsRepository()` unconditionally. A `MockPlayerStatsRepository` already exists at `footpath_cebu/lib/data/repositories/mock_player_stats_repository.dart:4`. Adjacent repository providers branch on `useMockData`.

Opening Player Stats during an explicitly mocked session therefore selects a live network/authentication adapter. This breaks isolated UI work and makes this feature behave differently from the rest of the mocked app.

Recommendation: apply the same mock/live selection as other providers and add a composition-root test proving mock mode selects the mock contract implementation. This is established by wiring inspection; no live network request was made to reproduce it.

### F2 — P2: Dependency wiring assumes capabilities absent from its declared contract

Evidence: `footpath_cebu/lib/core/di/providers.dart:139`, `:144`, and `:263` cast the result of `Provider<PlayerRepository>` to `DevelopmentAssessmentRepository`, `PlayerPhotoWriter`, and `PlayerDetailsReader`. The `PlayerRepository` declaration at `footpath_cebu/lib/domain/repositories/player_repository.dart:67` does not require these interfaces.

A replacement or test fake can correctly implement `PlayerRepository` and still fail with a runtime type error when one of these features is resolved. Current concrete implementations satisfying the casts does not make the substitution contract safe.

Recommendation: wire separately typed capability providers from a concrete implementation whose capabilities are checked by the compiler, or introduce a composition-only aggregate interface that explicitly requires them. Continue exposing narrow contracts to consumers. Test dependency overrides through those contracts.

### F3 — P2: Widgets still own application mutations and refresh orchestration

Evidence: `footpath_cebu/lib/presentation/screens/player_stats_screen.dart:363` owns save state, constructs a draft, invokes the repository, invalidates providers, and handles failures. `footpath_cebu/lib/presentation/screens/coordinator_person_details_screen.dart:225` directly deletes through a repository and manages list invalidation. Player Stats refresh at line 163 also fetches directly before invalidating and awaiting a provider that fetches again.

These screens mix rendering/navigation with mutation lifecycle and application coordination. The repository dependencies are abstractions, so this is a responsibility/MVVM issue rather than a direct concrete-data import violation. The stats refresh also performs redundant retrieval through two paths.

Recommendation: use feature controllers consistent with the existing `MutationController`, with one owner for execution, failure state, and invalidation. Keep dialogs and navigation in widgets. Move refresh into the stats provider/controller so it performs one authoritative fetch. Introduce use cases where there is shared policy; do not add empty wrappers solely to satisfy a diagram.

### F4 — P2: Most domain entities still own API serialization

Evidence: `footpath_cebu/lib/domain/entities/player.dart:258` parses API maps and line 295 emits them. `footpath_cebu/lib/domain/entities/player_stats.dart:49` parses transport keys, applies API defaults, and substitutes an epoch date on malformed/missing timestamps. The data layer has dedicated DTOs for notifications and disputes, but that boundary has not been applied consistently.

Domain objects therefore change with API field names and compatibility rules. Lenient decoding can turn malformed input into plausible domain values. Pure Dart imports alone do not protect against this form of infrastructure coupling.

Recommendation: extend the existing data DTO pattern, starting with Player Stats and Player. Decode and validate required fields in data adapters; map valid values into domain objects. Keep legitimate business defaults in the domain and wire compatibility defaults in DTOs. Add malformed-payload tests alongside successful mapping tests.

## Guardrails and strengths

- Keep the backend's existing attendance transaction/idempotency service, club scheduling lock, PIN service, and shared dispute/tournament-result workflows. They demonstrate patterns the remaining adapters can adopt.
- Keep Flutter's narrow repository interfaces, domain import test, presentation import test, offline attendance decorator, and shared mutation controller.
- `footpath_cebu/test/architecture_test.dart:35` checks serialization ownership for only the two migrated entities. Broaden it as migrations land, and add composition tests for mock routing and capability contracts. Import checks cannot detect widget-owned workflows or unsafe runtime casts.
- Add a modest backend dependency test for application services importing REST/view modules after establishing the intended rule. Avoid a large folder reorganization before fixing workflow ownership.

## Verification

- Backend: `manage.py test academy.test_injury_workflow academy.test_tournament_training_conflicts academy.test_backend_audit --noinput` — 32 tests passed, Django system check clean. Test database was isolated SQLite.
- Flutter: `flutter test test/architecture_test.dart test/wiring_and_assessment_test.dart test/providers/mutation_controller_test.dart` — 14 tests passed.
- Flutter: `flutter analyze` — no issues found.
- These are targeted checks, not full-suite validation. PostgreSQL concurrency, live Firebase/storage behavior, and browser rendering were not exercised. Passing checks do not disprove the structural and failure-path findings above.
- Portal server-side workflows were included in the backend review. Browser JavaScript received only a limited inspection; the frontend findings principally concern Flutter.

## Recommended sequence

1. Make injury state changes and audit entries atomic; add rollback coverage.
2. Centralize tournament publication, then standardize service errors.
3. Correct Player Stats mock wiring and remove unchecked capability casts.
4. Move remaining screen mutations into controllers and simplify stats refresh.
5. Migrate API serialization out of domain entities incrementally and extend architecture checks.

## Implementation follow-up

Implemented after the audit at the user's request:

- **B1:** Injury review, archive, recovery requests, and recovery review now use `academy/injury_service.py`. Services own locking, policy, persistence, and audit writes in one transaction. Report creation, editing, and withdrawal also wrap their writes and audits atomically; editing/withdrawal lock the selected injury. Added failure-injection coverage for report creation, review, archive, recovery requests, and recovery review, including rollback of both injury and recovery-request rows.
- **B2:** API and portal publication call `academy/tournament_publication.py`. The service owns club/schedule locks, publication validation, conflict confirmation, cancellation, timestamps, and auditing. Both adapters accept explicit true confirmation values. Tests cover portal-to-API repeat publication, false confirmation, and rollback on audit failure.
- **B3:** Added transport-independent errors in `config/application_errors.py` and REST translation in `config/api_errors.py`. Attendance, disputes, eligibility, registration, injury transitions, and publication use those errors. The admin eligibility adapter translates them into Django exceptions. Existing REST response status behavior is retained; import-boundary and error-mapping tests guard the extracted services.
- **F1:** Player Stats now selects the existing mock repository when mock mode is enabled. A composition test exercises this without a live API.
- **F2:** Added the data-layer `PlayerDataSource` aggregate capability contract. Concrete adapters satisfy it at compile time, and the composition root exposes narrow providers without runtime casts. The ordinary `PlayerRepository` contract stays narrow enough for existing read/write test fakes. Tests that substitute the whole adapter now override `playerDataSourceProvider`.
- **F3:** Player Stats saves and person deletion now run through feature mutation controllers. Those controllers own error/loading state and invalidation; screens retain form values, confirmation, feedback, and navigation. Stats refresh uses one provider refresh, and the parent screen no longer repeats invalidation after a successful save.
- **F4:** Completed the recommended initial DTO migration for Player, Player Ratings, Player Stats, and their Growth serialization dependencies. JSON decoding/encoding now lives in three data DTO modules. Domain objects retain business behavior. Required stats timestamps reject malformed/missing values instead of substituting the epoch. Updated consumers and round-trip tests, added malformed-input coverage, and extended the architecture guard to these migrated files. Other legacy entity serializers remain candidates for later incremental migration; this change does not claim a repository-wide DTO conversion.

Final verification:

- `python manage.py test --noinput`: **511 tests ran, successful with 7 skipped**. This includes console and the new backend regression/architecture tests. PostgreSQL-only tests remain skipped on SQLite.
- `flutter test --no-pub --reporter expanded`: **478 tests passed**.
- After removing a redundant parent-screen invalidation, the affected Player Stats screen and new controller/wiring tests were rerun: **13 passed**.
- `flutter analyze --no-pub`: no issues found.
- `ruff check backend` and `git diff --check`: passed.

No database migration or live service access was needed. Existing unrelated working-tree changes were retained.
