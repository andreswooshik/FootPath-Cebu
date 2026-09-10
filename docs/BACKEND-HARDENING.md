# Backend audit fixes

This change addresses the findings in `BACKEND-CODE-AUDIT-2026-09-10.md`. That document records the original state; this document describes the resulting behavior and rollout requirements.

## Changes

| Audit finding | Resolution |
| --- | --- |
| PostgreSQL nullable-join locking | Tournament, injury-review, and match-statistics queries explicitly identify the rows being locked. |
| Concurrent schedule conflicts | API and portal schedule writers acquire a club row lock before reading or mutating bookings. This also works for an initially empty schedule. |
| Eligibility/history partial commits | A shared eligibility service locks and reloads the profile. Profile saves wrap signal-driven history, audit, inbox, and outbox writes in one transaction. Both portal and admin use the service. |
| Notification failures after commit | Request handlers persist inbox records and a durable outbox job inside the business transaction. A separate worker sends bounded batches and retries failures. |
| Stale dispute status | Portal and API use one service that locks and reloads the dispute before adding a response. |
| Concurrent attendance replacement | A shared service locks the club and session, validates the session state, and replaces the whole batch atomically. Missing, duplicate, and oversized batches are rejected. |
| Audit-chain ordering and attribution | New v2 digests include an immutable sequence and actor identifier. Existing v1 hashes are preserved and remain verifiable. |
| Device input validation | Request serializers enforce string identifiers, maximum lengths, and supported platforms. |
| Old/cancelled-session confirmation | Confirmation requires the scheduled day and rejects cancelled sessions. |
| Unbounded lists and session N+1 | Main roster, training, attendance, confirmation, and dispute lists use bounded windows. Session serialization computes club/tier counts in one aggregate query. |
| SQLite-only verification | Dedicated `TEST_POSTGRES_*` settings and a PostgreSQL CI job run the full suite and real concurrent-connection tests. The migration test restores the current schema after testing older migrations. |
| Implicit module dependencies | Wildcard imports and dynamic export lists were removed. Compatibility modules export explicit symbols. Portal tournament controllers are separate from account/staff controllers. Shared services own the sensitive workflows, and a replaceable push gateway isolates Firebase delivery. Ruff linting and formatting are enforced in CI. |

## Deploying the schema and worker

Stop application writers while applying migrations `0031_audit_sequence` and `0032_pushoutbox`. Migration 0031 assigns a sequence to historical audit rows in their original verification order; it deliberately does not rewrite external audit proofs. Existing corrupt chains remain detectable rather than being silently repaired. Do not run the old application version against the new non-null audit sequence column.

Run from `backend` using the target environment's normal deployment process:

```sh
python manage.py migrate --noinput
python manage.py verify_audit_log
python manage.py deliver_notifications --watch
```

The production Compose definition now includes a `notifications` worker that waits for the web service to become healthy after migration. Non-Compose deployments need an equivalent supervised worker. A one-shot `python manage.py deliver_notifications --limit 100` invocation processes a bounded set of due jobs.

Inbox records are immediately available after the business transaction commits, even if Firebase is unavailable. Failed delivery jobs retry with exponential backoff, capped at one hour. `PushOutbox.attempts`, `available_at`, `last_error`, and `completed_at` support operational inspection. Error records contain exception types, not tokens or provider response bodies. Monitor old incomplete jobs and the worker process, and define a retention policy for completed jobs.

Worker leases prevent ordinary concurrent workers from processing the same job. Successful batches are checkpointed, permanently unregistered tokens are removed, and tokens reassigned to another user are excluded on retry. Network delivery is **at least once**: a process crash after Firebase accepts a batch but before its checkpoint can repeat that batch. Each notification carries a stable `eventId` for client deduplication; retries do not recreate inbox rows.

Application database migrations were not applied to the project's configured shared/deployed database during this code change.

## List API compatibility

JSON list bodies remain arrays. The affected endpoints accept `limit` (default 200, maximum 500) and `offset` (default 0). Responses include `X-Page-Limit` and `X-Page-Offset`; when another page exists they include `X-Next-Offset` and a standard `Link` header with `rel="next"`. These headers are exposed to browser clients through CORS.

Consumers that need the entire roster/history must follow the next-page header. Frontend code was outside this change's scope. Dispute list items retain the existing `responses` field but include at most the newest 100 responses, displayed chronologically; the dispute detail endpoint remains the full thread.

## Development checks

Final local validation on 10 September 2026:

- PostgreSQL 16.2 (temporary, isolated instance): **440 tests passed**, including all seven concurrent-connection/locking tests.
- SQLite: **440 tests completed successfully**, with seven PostgreSQL-only tests skipped.
- Ruff lint and formatter checks: passed.
- Bandit at the configured CI severity threshold: passed.
- Migration drift: no changes detected.
- Django `check --deploy --fail-level WARNING`: no issues using isolated production-mode check settings.
- Compose and CI YAML parsed successfully; shared worker configuration and PostgreSQL CI job verified. Docker/container execution was not available locally.

Local test logs are under `backend/.runlogs/`: `backend-postgres-final.log`, `backend-sqlite-final.log`, and `postgres-concurrency-final.log`.

```sh
python -m pip install ruff==0.16.6
ruff check .
ruff format --check .
python manage.py test --noinput
python manage.py makemigrations --check --dry-run
```

Default tests use SQLite. For a disposable PostgreSQL instance, set `TEST_POSTGRES_HOST`, `TEST_POSTGRES_PORT`, `TEST_POSTGRES_USER`, `TEST_POSTGRES_PASSWORD`, and optionally `TEST_POSTGRES_NAME` before running the same test command. The test name must begin with `test_`; the test runner never uses normal `DB_*` credentials for these integration tests. Use a dedicated database role/instance because Django creates and drops its test database.

The PostgreSQL CI job uses PostgreSQL 17. Local database verification used PostgreSQL 16.2, with Firebase delivery mocked; the temporary instance was stopped after verification. Real external delivery, a production rollout, and a load test remain deployment validation tasks.
