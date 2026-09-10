# Backend code audit — 10 September 2026

Follow-up: the user-authorized fixes and final validation are documented in [Backend hardening](BACKEND-HARDENING.md). The findings below preserve the original audited state.

Reviewed commit: `4561b08`. Scope: Django backend application code, server-side portal/admin handlers, configuration, and backend CI. Frontend code and visual assets were excluded. This is an audit; application code was not changed.

**Assessment: useful engineering foundations, but not ready for a production-quality sign-off.** The main blockers are transaction correctness and PostgreSQL compatibility. Clean Code and SOLID are only partially reflected in the implementation: there are useful services, but many feature modules still share an implicit global namespace and duplicate application workflows.

Priority meanings: P1 = resolve before production sign-off; P2 = substantive correctness, reliability, or maintainability work. Findings explicitly distinguish isolated reproductions from source analysis. PostgreSQL race scenarios were not executed against a live PostgreSQL instance.

## Findings

### 1. P1 — Tournament locking queries include nullable joined tables

Locations: [view_tournaments.py:340](../backend/academy/view_tournaments.py#L340), [view_tournaments.py:203](../backend/academy/view_tournaments.py#L203), [portal/views.py:883](../backend/portal/views.py#L883), and [portal/views.py:631](../backend/portal/views.py#L631).

`_coordinator_mobile_fixture()` combines `select_related('schedule', 'age_bracket', 'completed_match')` with unrestricted `select_for_update()`. Both `age_bracket` and `completed_match` are nullable relationships. Publishing and portal result recording also lock a queryset with a nullable age-bracket join.

PostgreSQL rejects `FOR UPDATE` applied to the nullable side of an outer join. Consequently, normal fixture editing/result recording and tournament publishing have database-specific failure paths even though their SQLite tests pass. This is established from the query construction and Django's documented restriction, rather than a live PostgreSQL reproduction.

Fix: lock the fixture rows explicitly with `select_for_update(of=('self',))` where appropriate, and separately lock required schedule/bracket rows in a consistent order. Preserve any parent-locking requirements when narrowing the lock. Add PostgreSQL integration coverage for API and portal workflows. [Django locking documentation](https://docs.djangoproject.com/en/5.2/ref/models/querysets/#select-for-update).

### 2. P1 — Scheduling conflict checks do not serialize concurrent inserts

Locations: [schedule_conflicts.py:80](../backend/academy/schedule_conflicts.py#L80), [view_training.py:127](../backend/academy/view_training.py#L127).

The training conflict query locks existing scheduled sessions. If two requests create the first sessions for a club/date, both can observe an empty result, acquire no session lock, and insert overlapping bookings. The later audit-log advisory lock does not repair this: conflict validation already occurred before that lock. The comment describing conflict check plus insertion as authoritative overstates the guarantee. Tournament-versus-training checks similarly lack a common lock shared by all competing writers.

Fix: acquire a stable club/scheduling lock before reading conflicts and use that protocol across training creation, edits, and tournament publication. Consider a database exclusion constraint if the booking representation is normalized. Validate simultaneous requests with separate PostgreSQL connections, including the initially empty schedule. Evidence: source-level transaction interleaving analysis.

### 3. P1 — Eligibility can change without its required history

Locations: [portal/services.py:133](../backend/portal/services.py#L133), [signals.py:52](../backend/academy/signals.py#L52), [portal/views.py:457](../backend/portal/views.py#L457).

`set_player_eligibility()` saves the profile without an outer atomic transaction. Its `post_save` signal then writes eligibility history and the general audit log. The portal caller does not wrap this service in a transaction either. Under autocommit, the profile update is already committed if history creation fails.

Reproduced in an isolated in-memory database: inject `DatabaseError` into `EligibilityHistory.objects.create`, call the service, catch the error, and reload the profile. The new eligibility remains persisted.

Fix: make the service own the transaction and lock/reload the profile before deriving the transition. Commit the profile, history, audit entry, and durable notification intent together. Ensure admin and API entry points follow the same invariant. Signals alone do not create this transaction boundary. [Django transaction behavior](https://docs.djangoproject.com/en/5.2/topics/db/transactions/).

### 4. P1 — Notifications above 500 devices can fail an already committed request

Locations: [notifications.py:49](../backend/academy/notifications.py#L49), [notifications.py:86](../backend/academy/notifications.py#L86), [view_training.py:150](../backend/academy/view_training.py#L150).

Every recipient token is placed in one `MulticastMessage`. Its constructor runs outside the `try` protecting the send. Reproduced using the installed SDK: constructing a message with 501 tokens raises `ValueError`. Calls made through `on_commit` can therefore raise after the underlying session/tournament change has committed, producing an error response for a successful write.

Inbox creation also runs after commit and outside the exception handler. A crash between business commit and callback execution loses the notification; an inbox database error propagates into the response. Network delivery runs synchronously in the request process, and no durable retry is present.

Fix: write an outbox/inbox intent inside the business transaction, deliver asynchronously with retries and idempotency, and split delivery into SDK-supported batches. As an immediate containment step, protect message construction and callback failures, while recognizing that swallowing exceptions does not guarantee delivery. [Firebase multicast limit](https://firebase.google.com/docs/cloud-messaging/send/admin-sdk), [Django on-commit behavior](https://docs.djangoproject.com/en/5.2/topics/db/transactions/#performing-actions-after-commit).

### 5. P2 — API dispute replies can restore a stale status

Locations: [view_disputes.py:98](../backend/academy/view_disputes.py#L98), [view_disputes.py:116](../backend/academy/view_disputes.py#L116). Compare [portal/services.py:162](../backend/portal/services.py#L162).

The API loads the dispute before its transaction and does not lock it. It calls unrestricted `dispute.save()` even when the reply carries no status change. If request A reads OPEN, request B resolves the dispute, then A posts a comment, A writes its stale OPEN status back. The portal service already uses a parent-row lock, so equivalent workflows have different guarantees.

Fix: route both surfaces through a shared response service that locks and reloads the dispute inside the transaction, applies validated changes, and writes the audit event. Evidence: source-level interleaving analysis.

### 6. P2 — Attendance replacement lacks a session-level concurrency boundary

Location: [view_training.py:53](../backend/academy/view_training.py#L53).

The session and its state are loaded before the transaction. Individual attendance rows are upserted, then all omitted players are deleted, without locking the parent session. Concurrent replacement batches with disjoint players can each insert rows before either sees the other's uncommitted inserts, leaving a union instead of one complete replacement. Other schedules can lose rows or deadlock. A concurrent cancellation can also be overwritten by the stale session status being saved as COMPLETED.

Additionally, `request.data.get('records', [])` treats a missing required field as an instruction to delete all attendance and complete the session. An explicit empty replacement and a malformed request should be distinguishable.

Fix: validate a required bounded records list, reject duplicate player IDs, lock/reload the session before checking its state, and perform the entire replacement under that lock. Add concurrent replacement and cancellation tests on PostgreSQL. Evidence: source analysis.

### 7. P2 — Audit chain ordering can reject legitimate writes; actor is not protected

Locations: [model_operations.py:399](../backend/academy/model_operations.py#L399), [model_operations.py:415](../backend/academy/model_operations.py#L415), [model_operations.py:450](../backend/academy/model_operations.py#L450).

The timestamp is assigned before acquiring the PostgreSQL advisory lock, but both predecessor selection and verification order by timestamp. A request with an earlier timestamp can acquire the lock later, or different workers' clocks can disagree. The resulting insertion-order chain is then verified in a different order.

Reproduced without concurrency by recording two legitimate entries with the second timestamp one second earlier: `verify_chain()` returns false. Also, `_digest()` excludes the actor, and external proof logs omit the actor. Reassigning an entry's actor leaves its digest unchanged. Ordinary ORM update/delete guards help prevent accidental edits, but do not make this audit representation fully tamper-evident.

Fix: allocate chain order under the lock and verify by an immutable monotonic sequence. Include an immutable actor identifier in the hashed payload, with an explicit treatment for account deletion. Version the digest format and migration strategy. Retain independent external proof storage if tamper detection is a requirement.

### 8. P2 — Device registration accepts unvalidated payload types and lengths

Location: [view_notifications.py:11](../backend/academy/view_notifications.py#L11).

The endpoint invokes `.strip()` directly on user-supplied `token` and `platform` values. Isolated authenticated requests with `{"token":123}` and `{"token":"valid","platform":["android"]}` both raise uncaught `AttributeError` instead of a client validation response. Model field lengths (255/20) are not validated by this view, so oversized strings can reach database enforcement in production.

Fix: introduce a request serializer with string/type/length validation and a platform choice field. Use the validated values for both registration and deletion. Test malformed JSON shapes and maximum lengths.

### 9. P2 — RSVP validation allows old and cancelled sessions

Location: [view_training.py:308](../backend/academy/view_training.py#L308).

The error message says confirmation is allowed only on the scheduled day, but the condition rejects only future dates. There is also no cancelled-state rejection. Reproduced: a player confirmed a same-club CANCELLED session dated 30 days earlier and received HTTP 201.

Fix: enforce the agreed confirmation window explicitly, reject cancelled sessions, and validate any required tier eligibility. Cover yesterday/today/tomorrow and cancelled/completed states.

### 10. P2 — Unbounded list responses compound a confirmed N+1 query

Locations: [serializer_training.py:53](../backend/academy/serializer_training.py#L53), [view_training.py:119](../backend/academy/view_training.py#L119), [view_players.py:8](../backend/academy/view_players.py#L8), [view_disputes.py:28](../backend/academy/view_disputes.py#L28).

`get_eligiblePlayerCount()` executes a separate count for every serialized session. Reproduced with four already-loaded sessions: serialization issued four additional SQL queries. Training, squad, attendance, and dispute lists return entire querysets; dispute lists also prefetch whole response threads. Growth in historical data therefore increases response size, memory use, and query cost without a request-level bound.

Fix: aggregate counts once per club/tier or annotate appropriately; add query-budget tests. Introduce bounded pagination/date windows and a lightweight dispute list representation, coordinating any response-contract changes with API consumers. Merely setting DRF's default pagination will not paginate these custom APIView methods.

### 11. P2 — Test configuration prevents production-database verification

Locations: [settings.py:28](../backend/config/settings.py#L28), [settings.py:152](../backend/config/settings.py#L152), [.github/workflows/ci.yml:31](../.github/workflows/ci.yml#L31).

Every `manage.py test` invocation forces SQLite, even when PostgreSQL environment variables are provided. CI follows that same path. This bypasses PostgreSQL row locking, nullable-join lock restrictions, and varchar enforcement. The passing suite cannot establish the production properties implicated above. Django also documents that SQLite does not enforce `select_for_update()` locks.

Fix: keep fast SQLite unit tests, but add explicit isolated PostgreSQL test settings and a CI PostgreSQL service. Use `TransactionTestCase` plus independent connections for real commit/locking tests. Never point integration tests at the shared application database. [Django locking/test caveats](https://docs.djangoproject.com/en/5.2/ref/models/querysets/#select-for-update).

### 12. P2 — Feature extraction retains implicit dependencies and duplicated workflows

Locations: [_view_support.py:1](../backend/academy/_view_support.py#L1), [_view_support.py:309](../backend/academy/_view_support.py#L309), [model_operations.py:3](../backend/academy/model_operations.py#L3), [serializer_training.py:3](../backend/academy/serializer_training.py#L3), [portal/views.py](../backend/portal/views.py).

Feature views import everything from `_view_support`; model and serializer modules import earlier feature modules with wildcard imports. Dynamic `__all__` exports include private helpers and imported framework names. For example, training serializers obtain their framework/model dependencies through the player serializer module. Moving or removing an unrelated import can break another feature, and local dependencies are difficult to inspect.

The portal view module is 955 lines and account admin module 825 lines. Size alone is not a defect; the substantive issue is that HTTP handling, workflow validation, ORM writes, audit logging, and external effects are often coordinated directly in these surfaces. The divergent dispute transaction implementations demonstrate the cost of duplicated orchestration. Firebase and Supabase details are also concrete dependencies inside business workflow modules.

Fix: replace wildcard imports with explicit imports and explicit compatibility exports. Extract shared application services around real use cases: attendance replacement, scheduling, dispute responses, eligibility transitions, and provisioning. Separate focused query helpers and access policies. Introduce narrow identity/storage/notification adapters at external integration boundaries, without building a generic repository abstraction around every Django model. Add an enforced formatter/linter configuration; existing Bandit checks do not enforce these design properties.

## Clean Code and SOLID assessment

| Principle | Assessment |
| --- | --- |
| Single Responsibility | Partial. PIN and tournament-result services are useful examples; view/admin orchestration and the shared import hub need focused extraction. |
| Open/Closed | Partial. Repeated role branches and parallel workflow implementations require edits across surfaces when policies change. Prefer centralized policies/services where actual variation exists. |
| Liskov Substitution | No specific violation established in this review. Do not infer compliance or noncompliance from class counts. |
| Interface Segregation | Weak at module boundaries: wildcard imports expose broad implicit interfaces. Use explicit, narrow public exports. |
| Dependency Inversion | Partial. Service functions exist, but provisioning and delivery directly depend on vendor SDKs and environment-driven transport helpers. Narrow adapters would improve failure testing and separation. |
| Readability and consistency | Generally meaningful names and helpful domain comments; some comments claim transaction or failure guarantees that implementation does not supply. |

## Verification and limits

- Existing Django suite: **416 tests passed**, 49.459 seconds reported by the runner; Django system check reported no issues. Runner output is in `backend/.runlogs/backend-audit-tests.log` (local ignored artifact).
- `makemigrations --check --dry-run`: no changes detected, with the database environment explicitly restricted to local development.
- Bandit, using the backend CI paths/exclusions and `-ll -q`: passed; no findings at that configured threshold.
- `pip-audit --local --progress-spinner off`: no known vulnerabilities found in the installed Python environment at audit time. This does not certify a deployed image or all future dependency resolutions.
- Additional probes used a fresh in-memory SQLite database. They reproduced eligibility/history partial persistence, invalid device payload exceptions, old cancelled-session RSVP acceptance, session serialization N+1 queries, and audit timestamp ordering. The local SDK independently reproduced the 501-token constructor exception.
- No live PostgreSQL concurrency test, deployed-system penetration test, load test, external Firebase/Supabase delivery test, production deployment check, or restore drill was performed. Deployment configuration and CI were inspected, but the full CI/container build was not rerun.
- The review was risk-focused across the backend, not a proof that every endpoint or every invariant is defect-free. Existing upload hardening, role/tenant checks, PIN hashing and throttling, database constraints, dependency locks, and operational scripts are positive foundations.

## Recommended sequence

1. Add isolated PostgreSQL integration coverage and fix nullable-join locking, schedule serialization, and eligibility atomicity.
2. Contain notification callback failures, enforce batch sizes, then add durable delivery/retries.
3. Repair dispute/attendance concurrency, audit ordering, and request validation; add regression tests for the reproduced defects.
4. Replace implicit imports and consolidate shared workflows incrementally while preserving API contracts.
5. Bound list endpoints and enforce query budgets and formatter/linter checks in CI.
