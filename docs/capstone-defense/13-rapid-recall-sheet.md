# Rapid Recall Sheet

## One sentence

FootPath Cebu is a Flutter + Django role-based youth football academy system that uses Firebase for identity/push, Django for authorization/data, relational storage for operational history, and a local outbox for offline attendance writes.

## Architecture in five lines

1. Widget → Riverpod controller/provider.
2. Controller → domain use case → repository contract.
3. API adapter → Firebase Bearer token → Django REST.
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
- Flutter local SQLite = attendance outbox only.

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

## Implemented / partial / absent

### Implemented

Auth, roles/clubs, provisioning, roster/profile, ratings/position/notes, schedule CRUD, attendance, offline attendance writes, player RSVP, eligibility history, injuries, disputes, privacy PIN, audits, photo upload web-side.

### Partial

- notification token + backend sends; no complete in-app receive/inbox/navigation;
- production settings/CI; no verified live deployment artifact;
- photo upload web/admin only.

### Absent

AI/ML, scouting, match stats, chat, maps/GPS, mobile public registration, grades, assessment-version history, Supabase RLS.

## Verification facts (2026-08-18)

- Flutter analyze: pass, no issues.
- Flutter tests: all 184 pass.
- Backend Python compile: pass.
- Django tests: all 212 pass locally.
- Club hierarchy security matrix: all 24 required cases pass.
- CI workflow: exists and defines Django tests/deploy check + Flutter analyze/test.

## Top weaknesses

1. Player creation is centralized and requires an active Club.
2. Generic admin creation excludes Player, so a Player cannot be created without a profile.
3. Admin squad progress still filters by null club.
4. Session times are strings; order validation absent.
5. Rating constraints are not fully DB-enforced.
6. Session-confirmation errors are silent.
7. Notification UX incomplete.
8. Offline attendance read fallback catches too broadly.
9. API timeout/error handling is not centralized.
10. README/requirements drift from code.

## Ten evidence files

1. `footpath_cebu/lib/core/di/providers.dart`
2. `footpath_cebu/lib/data/repositories/firebase_auth_repository.dart`
3. `footpath_cebu/lib/data/repositories/offline_first_attendance_repository.dart`
4. `footpath_cebu/lib/data/local/attendance_sync_service.dart`
5. `backend/config/settings.py`
6. `backend/accounts/authentication.py`
7. `backend/accounts/services.py`
8. `backend/academy/models.py`
9. `backend/academy/views.py`
10. `backend/academy/pin_service.py` + `player_unlock.py`

## Best opening

> Our system centralizes academy development and training records across six roles. Coaches, players, and guardians use Flutter; coordinators and school staff use a Django portal; administrators use Django admin. Firebase proves mobile identity, while Django owns role/club authorization and relational data. Our most technically distinctive feature is a user-scoped offline attendance outbox combined with layered guardian privacy. AI and scouting are not part of the current implementation.

## Best limitation answer

> We distinguish complete, partial, and absent functionality. The main complete flows are academy operations and privacy. Notifications are send-side partial; assessment history is absent; and AI, scouting, and match statistics are not implemented. We also found two admin provisioning invariants that should be fixed before production.

## Future improvement order

1. Fix and regression-test player provisioning invariants.
2. Reconcile README/requirements and the 0–99 scale.
3. Add typed session-time and database rating constraints.
4. Complete notification/error UX and add versioned assessment history.
5. Prove deployment, monitoring, backups, privacy governance, and full live end-to-end tests.

## Emergency answer formula

**Direct result → server/client mechanism → evidence → limitation.**

Never guess. Say: “That behavior is not found in the current source; the closest implemented flow is …”
