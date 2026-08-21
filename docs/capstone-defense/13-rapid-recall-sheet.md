# Rapid Recall Sheet

## One sentence

FootPath Cebu is a Flutter + Django role-based youth football academy system that uses Firebase for identity/push, Django for authorization/data, relational storage for operational and notification history, and owner-scoped local resilience for attendance writes and safe reads.

## Architecture in five lines

1. Widget → Riverpod controller/provider.
2. Controller → domain use case → repository contract.
3. API adapter → shared authenticated client/cache policy → Firebase Bearer token → Django REST.
4. Django token/role/club/object validation → serializer → ORM transaction.
5. JSON → entity → provider invalidation → rebuilt UI.

## Roles

- `ADMIN`: Django admin/admin APIs.
- `COORDINATOR`: club portal/account creation.
- `COACH`: mobile squad, sessions, attendance, assessment, progress, disputes.
- `PLAYER`: mobile own profile, confirmation, injuries, history.
- `SCHOOL_STAFF`: portal eligibility.
- `GUARDIAN`: mobile linked-player reads after PIN unlock.

Dedicated Flutter role destinations: coach, player, guardian only.

## Truth boundaries

- Firebase = identity + FCM.
- Django = roles, clubs, authorization, data source of truth.
- SQLite = default/test DB.
- PostgreSQL/Supabase = optional configured DB host.
- Supabase Storage = optional private player photos via Django.
- Supabase Auth/RLS = not used.
- Flutter local SQLite = owner-scoped attendance outbox + eligible authenticated GET cache, not a server database replica.

## Guardian PIN numbers

- PIN: 4–6 digits.
- Lock: after 5 failures.
- Lock duration: 15 minutes.
- Unlock token lifetime: 10 minutes.
- Recent authentication for reset: within 5 minutes.
- Token binding: guardian user + player.

## Performance and attendance numbers

- 12 player rating fields.
- Actual rating range: 0–99.
- Requirements’ 1–10 wording: inconsistent/stale.
- Attendance effort: 0–100 when present.
- Attendance write window: session date through 2 days later.
- Assessment history: not implemented.

## Offline attendance

Live first → queue only network write failure → store whole batch + owner UID → replay oldest first → delete on success → increment retry/stop on failure → later complete batch effectively wins.

Eligible GETs: cache only successful JSON by owner/request → use only for network-classified failure → never hide 401/403/other HTTP/decode errors → never cache protected unlock responses → expire/clear owner on sign-out.

## Implemented / externally bounded / absent

### Implemented

Auth, roles/clubs, invariant-safe Player provisioning/seeds, roster/profile, ratings/position/notes, schedule CRUD with time-order validation, attendance, offline attendance writes and eligible cached reads, player RSVP with visible failures, eligibility history, injuries, disputes, privacy PIN, audits, persistent notification inbox/receive UX, and web/admin/same-Club Coach photo upload when Supabase is configured.

### Implemented with external-service boundaries

- notification inbox/read state, bells, foreground handling, and role-aware routing are implemented; session events enter schedules, Player/Guardian assessment and eligibility events respect the existing privacy gates, unknown events fall back to the inbox, and actual remote push still needs configured Firebase/APNs and a supported device;
- photo picker/multipart/API validation is implemented; object persistence needs configured Supabase Storage credentials.

### Operationally unverified

- production container/Compose, probes, logging/optional Sentry, CI, backup/restore scripts, and runbook exist;
- no verified live URL, alert exercise, scheduled backup, or completed restore drill is supplied.

### Absent

AI/ML, scouting, match stats, chat, maps/GPS, mobile public registration, grades, assessment-version history, Supabase RLS.

## Verification facts (2026-08-21)

- Flutter analyze: pass, no issues.
- Flutter tests: all 240 pass.
- Django tests: all 241 pass locally.
- Club hierarchy security matrix: all 24 required cases pass.
- CI workflow: exists and defines Django tests/deploy check/container validation + Flutter analyze/test.

## Top weaknesses

1. No versioned performance-assessment history; saves overwrite current values.
2. Rating constraints are not fully DB-enforced.
3. Attendance is the only queued/replayed mutation; conflict handling is simple last-write-wins.
4. Training times remain display strings despite serializer/model semantic validation.
5. Roster filtering is client-side and larger list/inbox workflows need a fuller pagination strategy.
6. Portal CSP still permits `unsafe-inline`/`unsafe-eval` for current assets.
7. Privacy consent, retention/deletion, breach-response, and formal user-study evidence remain outside executable code.
8. Physical-device push and configured Supabase upload need environment evidence.
9. Live deployment, monitoring/alert, scheduled backup, and restore drill are unverified.
10. The requirements rating-scale wording still differs from executable code; the README architecture itself is reconciled.

## Ten evidence files

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

## Best opening

> Our system centralizes academy development and training records across six roles. Coaches, players, and guardians use Flutter; coordinators and school staff use a Django portal; administrators use Django admin. Firebase proves mobile identity, while Django owns role/club authorization and relational data. Our technically distinctive features include layered guardian privacy, an owner-scoped attendance outbox/safe-read cache, and a durable notification inbox. AI and scouting are not part of the current implementation.

## Best limitation answer

> We distinguish implemented code, external-service verification, and absent scope. The main academy/privacy flows, Player invariants, notification inbox/receiving, shared API policy, session validation, and Coach photo workflow are implemented. Assessment history is absent, AI/scouting/match statistics are not implemented, and live deployment/recovery evidence is still required.

## Future improvement order

1. Reconcile the requirements and the 0–99 scale.
2. Add versioned assessment history and remaining database constraints.
3. Add pagination/scalability work and strengthen portal CSP assets.
4. Run physical-device push and configured-Supabase photo demonstrations.
5. Prove deployment, monitoring/alerts, scheduled backups, restore drills, privacy governance, and full live end-to-end tests.

## Emergency answer formula

**Direct result → server/client mechanism → evidence → limitation.**

Never guess. Say: “That behavior is not found in the current source; the closest implemented flow is …”
