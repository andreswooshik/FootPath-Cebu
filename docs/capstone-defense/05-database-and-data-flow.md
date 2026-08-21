# Database and Data Flow

## Database truth

Django ORM is the only application data-access authority. Development and automated tests use SQLite. When database environment variables are supplied, Django uses PostgreSQL and can connect to a Supabase-hosted PostgreSQL instance. Flutter never talks directly to SQLite/PostgreSQL/Supabase; therefore this project does not use Supabase Auth or RLS.

## Relational schema map

```text
Club
 ├─ User (role, firebase_uid, club)
 │   ├─ PlayerProfile (when role=PLAYER)
 │   │   ├─ PlayerPrivacyPin
 │   │   ├─ EligibilityHistory
 │   │   ├─ Attendance ── TrainingSession
 │   │   ├─ SessionConfirmation ── TrainingSession
 │   │   └─ InjuryRecord
 │   ├─ DeviceToken
 │   ├─ NotificationRecord (durable inbox/read state)
 │   └─ GuardianLink (guardian User -> player User)
 ├─ TrainingSession
 └─ club-scoped queries/disputes through related users

Dispute ── DisputeResponse
AuditLog (optional actor, textual target/detail)
AgeTierSetting (global configuration)
```

## Tables and important fields

| Model/table | Key fields | Important relationships/constraints |
|---|---|---|
| `Club` / `accounts_club` | name, slug, active, school affiliation, license/membership metadata | name and slug unique |
| `User` / `accounts_user` | Django identity fields, email, Firebase UID, role, club | Firebase UID unique/nullable; club `SET_NULL` |
| `GuardianLink` | guardian, player, created time | both point to users; guardian-player pair unique |
| `AgeTierSetting` | tier, min/max age | tier unique |
| `PlayerProfile` | user, birth/class/tier/position, 12 ratings, notes, eligibility, photo path | one-to-one with user |
| `PlayerPrivacyPin` | player, PIN hash, failures, lock time | one-to-one with player; plaintext never stored |
| `EligibilityHistory` | player, changed_by, old/new status, timestamp | player cascades; actor `SET_NULL` |
| `TrainingSession` | title/date/start/end/location/focus/tiers, creator, club | creator/club `SET_NULL`; age tiers stored as JSON |
| `Attendance` | player, optional session, status, effort, note, recorder, updated | `(player, session)` unique; session `SET_NULL`; player cascades |
| `SessionConfirmation` | player, session, response, time | `(player, session)` unique; both cascade |
| `InjuryRecord` | player, description/body/status/date/notes/timestamps | player cascades; player/date index |
| `Dispute` | raiser, subject player, category/status, summary/detail/time | user links `SET_NULL` to preserve thread |
| `DisputeResponse` | dispute, author, body, optional status transition, time | dispute cascades; author `SET_NULL` |
| `AuditLog` | actor, action, target, detail, time | actor `SET_NULL` |
| `DeviceToken` | user, token, platform, updated | token unique; user cascades |
| `NotificationRecord` | user, event type, title/body, data, read time, created time | user cascades; current-user inbox index/order |

`PlayerEligibility` is a proxy model and creates no separate table.

## Cardinality and relationship defense

| Relationship | Cardinality | Enforcement/meaning |
|---|---|---|
| Club → User | one-to-many | `User.club` nullable FK; required by mobile auth for non-admin |
| User(player) ↔ PlayerProfile | one-to-one | one development profile per player user |
| User(player) ↔ PlayerPrivacyPin | one-to-one | one household PIN state per player |
| Guardian ↔ Player | many-to-many through `GuardianLink` | unique guardian/player pair; both are `User` rows |
| Club → TrainingSession | one-to-many | session club assigned from scheduling coach |
| Player ↔ TrainingSession | many-to-many through `Attendance` | unique player/session attendance row; attendance retains null session after deletion |
| Player ↔ TrainingSession | many-to-many through `SessionConfirmation` | unique RSVP; cascades with session/player |
| Player → InjuryRecord | one-to-many | player owns writes; deletion cascades |
| Player → EligibilityHistory | one-to-many | append-only status transitions; changer optional FK |
| Dispute → DisputeResponse | one-to-many | timestamped append-only thread responses |
| User → DeviceToken | one-to-many | token itself globally unique |
| User → NotificationRecord | one-to-many | durable per-user inbox rows; read time nullable |

## Data creation and retrieval examples

### Player account creation

Trusted portal/admin input → provisioning service creates/links Firebase identity → Django `User` with active Club → exactly one `PlayerProfile` → optional same-Club `GuardianLink` → response. Generic account creation cannot select `PLAYER`, and both seed commands repair/create this same aggregate idempotently. Cross-system compensation removes a newly created Firebase identity if relational persistence fails.

### Squad retrieval

Coach request → token maps to a clubbed coach → queryset filters player users/profiles by the same club → serializer nests ratings and signed photo URL → Flutter `Player.fromJson` → local `RosterFilter` for display search.

### Attendance write

The client sends a session ID and a complete `records` list. The server looks up the session in the coach’s club and looks up each player in that club. Inside a transaction, it updates/creates submitted player rows and deletes rows omitted from the submitted set. The client cannot move a session/player across clubs by changing an ID.

### Eligibility history

Changing the current `PlayerProfile.eligibility` triggers signals. The prior value is captured before save; after save, a new append-only `EligibilityHistory` row and an audit entry are created. The current status is optimized for display while history supports accountability.

### Notification persistence

A committed notification event creates a `NotificationRecord` for each active recipient before best-effort FCM delivery. List/unread/mark-one/mark-all queries always filter by the authenticated user. The row remains available in the inbox even when a device token is absent or push transport fails.

## Mobile-local database

Flutter uses sqflite for two owner-scoped resilience stores, not as a replica of the Django database.

### Attendance outbox

| Column | Meaning |
|---|---|
| `id` | auto-increment queue identity |
| `owner_uid` | Firebase user that created the batch |
| `session_id` | target training session |
| `records_json` | serialized complete attendance batch |
| `created_at` | enqueue time |
| `retry_count` | replay attempts |
| `last_error` | diagnostic replay error |

Owner scoping prevents one user who later signs in on the same device from replaying another user’s queued writes. Sequential oldest-first replay preserves intended order.

### Authenticated GET cache

| Column | Meaning |
|---|---|
| `owner_uid` + `cache_key` | composite identity for one user and exact request |
| `status_code` | cached successful HTTP status |
| `body` | successful JSON response body |
| `headers_json` | serialized response headers |
| `updated_at` | age/expiry basis |

The shared API client writes only eligible successful JSON GET responses. It may read them only for a network-classified failure, never for HTTP 4xx/5xx or decode errors. Entries expire after 24 hours, protected unlock responses are excluded, and sign-out clears only the departing owner.

## Integrity mechanisms

- model foreign keys and one-to-one relationships;
- unique guardian links, attendance rows, confirmations, device tokens, and tier names;
- central Player aggregate provisioning plus idempotent seed repair for active Club + exactly one PlayerProfile;
- cross-field `TrainingSession` validation for paired supported 12-hour strings and start before end through serializer and model-save paths;
- DRF field ranges and choices;
- server-derived club/actor/player fields;
- `transaction.atomic()` for multi-record attendance, account, PIN, and dispute operations;
- `select_for_update()` for PIN failure/lock state;
- `transaction.on_commit()` for notifications so inbox/push events are not emitted for a rolled-back write;
- audit and eligibility history records.

## Deletion behavior worth knowing

- Deleting a player cascades to its profile-related attendance, confirmations, injuries, PIN, and guardian links.
- Deleting a training session sets existing attendance `session` to null, preserving a legacy record, but cascades confirmations.
- Deleting an actor referenced by history/audit can set the actor to null and preserve the event.
- Dispute responses cascade if their dispute is deleted.

## Data limitations and improvement targets

1. No performance-assessment history exists; new assessments overwrite the current twelve rating fields.
2. No grades are stored; only an eligibility enum/history is stored.
3. No match or scouting tables exist.
4. Training times remain strings for the existing wire/display contract; serializer and model validation now require paired supported 12-hour values and enforce start before end, but native database `TIME` columns would offer stronger engine-level typing.
5. `(player, session)` uniqueness includes a nullable session; SQL null semantics can allow multiple legacy null-session attendance rows.
6. Rating constraints are primarily serializer-level; model/DB checks do not comprehensively enforce 0–99 for every write route.
7. Player provisioning is centralized: every successful path commits a
   Club-scoped `PLAYER`, exactly one `PlayerProfile`, and an optional same-Club
   Guardian link; generic creation cannot select `PLAYER`.

## Database panel answers

**Why structure it relationally?** The academy domain is relationship-heavy: users belong to clubs, guardians link to players, and players relate to many sessions through attendance/confirmation. Foreign keys, unique pairs, transactions, and joins make these invariants explicit.

**How are duplicates/inconsistency prevented?** Unique fields/pairs, one-to-one profiles/PINs, central Player aggregate provisioning, serializer/model validation, server-derived ownership, atomic writes, and same-club checks work together. Remaining gaps include nullable-session uniqueness and DB-level rating ranges.

**How do tables relate?** `accounts_user` is the identity hub. A player user owns one profile and connects to guardians, sessions, attendance, confirmation, eligibility history, injury, and disputes through FKs/junction rows.

**What happens on deletion?** Child-operational rows often cascade with the player; historical actor references use `SET_NULL`; session deletion preserves attendance with null session but deletes confirmations. Exact policies are in `academy/models.py`.

## Database answer to memorize

> Django ORM owns the data. SQLite is the default and test database; configured deployments can use PostgreSQL, including Supabase-hosted PostgreSQL. The relational design uses club/user links, one-to-one player profiles, unique session records, append-only eligibility/dispute histories, durable notification rows, transactions, and server-derived tenant fields. Flutter keeps only a user-scoped attendance outbox and eligible GET cache, not a copy of the main database.
