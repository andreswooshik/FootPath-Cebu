# Security and Privacy Review

## Security model

FootPath Cebu uses layered controls:

```text
Firebase credential check
 -> signed/revocation-checked ID token
 -> active Django user lookup by Firebase UID
 -> role check
 -> club/tenant filter
 -> object ownership or guardian link
 -> optional household PIN unlock
 -> serializer validation
 -> database constraints/transaction
 -> audit/history
```

No single client-side check is treated as the security boundary.

## Identity and sessions

Mobile users authenticate with Firebase email/password. Django verifies every Bearer token using Firebase Admin with revocation checking enabled. It then requires a matching active local user and, except for administrators, a club. This prevents a valid Firebase account with no academy record from becoming an authorized academy user.

Coordinator, school-staff, and admin web access uses Django sessions. Django password validators and Argon2-first hashing are configured. `django-axes` supplies brute-force lockout at five failures for 30 minutes. CSRF middleware protects session-authenticated forms.

## Authorization

- broad endpoint permissions use authenticated/role checks;
- querysets and object lookups restrict by `request.user.club_id`;
- player-owned endpoints derive the player from `request.user`;
- guardian reads require an active `GuardianLink` and, for private detail, a signed unlock header;
- trusted fields such as `club`, `created_by`, and `recorded_by` are server-assigned;
- portal services force the coordinator’s club.
- notification list/read actions always filter by the authenticated user;
- Super Admin progress intentionally spans Clubs, while Coach progress remains filtered to the Coach’s Club.

Client role routing improves the experience, but backend checks provide the actual enforcement.

## Player household privacy PIN

The player establishes a 4–6 digit PIN. Django stores only a password hash using its configured hasher chain (Argon2 first), never plaintext. Verification locks the row, counts failures, and enforces a 15-minute lock after five failures. Success returns a Django-signed token bound to both guardian user and player and valid for ten minutes.

The guardian’s linked-player selector is redacted before unlock. Flutter keeps the unlock token only in memory and sends it as `X-Player-Unlock` for protected detail calls. Reset requires a recently authenticated Firebase claim (maximum five minutes), and the mobile flow reauthenticates first.

The PIN is additional household privacy; it is not a substitute for the guardian’s Firebase login or server-side link check.

## Tenant and object isolation

`Club` is the tenant boundary. Normal authenticated users are expected to have a club. Most roster, session, assessment, attendance, progress, and portal queries scope records to that club. A panel answer should mention both role-based access control and object/tenant authorization; saying “Firebase handles security” is incomplete.

## Input and file validation

- DRF serializers validate choices, required fields, rating/effort ranges, and payload shapes.
- Django forms validate portal inputs.
- Player photo upload checks role/same-Club access, file size, MIME type, and signature before server-side upload. Flutter sends bytes through Django and never receives the Supabase service-role credential.
- Training sessions require paired supported 12-hour start/end values with start before end at serializer and model-save boundaries.
- Coach license upload is size constrained.
- Public Club/Coordinator signup is disabled; the URL is informational and cannot mutate data.
- API actors cannot assign arbitrary trusted ownership fields.

## Secrets and transport

Production settings require a nontrivial Django secret, allowed hosts, explicit CORS origins, HTTPS redirect, secure cookies, HSTS, and a shared Redis cache. WhiteNoise serves static assets; structured logging and optional Sentry hooks are configured. Docker/Compose, liveness/readiness routes, and backup/restore scripts make the intended runtime reproducible. The release Flutter configuration requires HTTPS and can restrict the API host. Development is intentionally looser, including wildcard CORS.

These repository controls are not evidence that a live environment, alert path, backup schedule, or restore drill has actually run. Those operational artifacts must be supplied separately.

The repository contains ignored local environment/database/service-account files in the workspace. Their values were not copied into these notes. Firebase client configuration files are present as expected for Firebase clients; privileged Firebase Admin and Supabase service-role credentials belong only on the server.

## Auditability

Audit records capture an optional actor, action, target, detail, and time. Eligibility uses a dedicated history table with old/new status and changer. Dispute responses are append-only and timestamped. Attendance stores recorder/update time. These mechanisms improve accountability but are not a tamper-proof external audit ledger.

## Security strengths

1. Firebase token verification includes revocation checks.
2. Identity is mapped to an active local domain user.
3. Authorization is server-side and usually both role- and club-scoped.
4. Guardian links and time-limited signed tokens protect child detail.
5. PINs are hashed and brute-force throttled with transactional locking.
6. Portal login has CSRF and Axes controls.
7. Writes validate payloads and derive trusted fields server-side.
8. Multi-row operations use database transactions.
9. Notification events are deferred until successful commit. Cancellation snapshots recipients, commits the delete, and only then creates inbox records/attempts push, preventing false cancellation messages on a failed delete.
10. Production configuration includes TLS/cookie/HSTS/CORS safeguards.
11. Uploads are mediated by Django; the mobile client never receives service-role storage credentials.
12. Offline outbox and eligible GET-cache records are scoped to the Firebase owner UID; protected unlock reads are not cached, and HTTP errors never trigger cache fallback.
13. Persistent notification/read-state rows provide a current-user inbox even when best-effort FCM transport is unavailable.

## Concrete concerns and severity

| Severity | Concern | Consequence | Recommended remediation |
|---|---|---|---|
| Resolved | Player/Club/Profile invariant | Every executable Player flow delegates to `provision_player` | 24-case hierarchy suite plus provisioning tests |
| Resolved | Generic Player creation | `PLAYER` removed from generic choices and direct admin creation rejected | invariant tests pass |
| Resolved | Squad-progress administrator scope | Super Admin now receives all Clubs; Coach remains scoped to the verified Coach’s Club | Role-branch regression tests |
| Medium | Portal CSP allows `unsafe-inline` and `unsafe-eval` for CDN UI scripts | Weakens XSS defense | Bundle/pin scripts locally and use nonces/hashes |
| Resolved | Notification receiving, durable history, and trusted routing | Current-user inbox/read APIs, unread bells, foreground feedback, and role-aware Schedule/Profile/Eligibility destinations are implemented; unknown events/profile failures fall back to the focused inbox | Preserve role, linked-child, and privacy gates; keep physical-device FCM/APNs smoke evidence separate from repository coverage |
| Resolved | Duplicated HTTP timeout/error behavior | Shared authenticated client applies one timeout, typed errors, safe messages, multipart handling, and eligible GET-cache policy | Maintain repository tests when adding endpoints |
| Resolved | Attendance fallback masked broad errors | Outbox/roll-call fallback catches network-specific failures only; 401/403/5xx remain visible | Preserve typed exception boundary |
| Resolved | Session confirmation feedback gap | Failed submit shows a SnackBar; initial load failure exposes `Retry RSVP` | Preserve widget regression tests |
| Resolved | Session time order was not validated | Serializer and model paths require paired supported 12-hour values and start before end | Preserve serializer and ORM/admin regression tests |
| Low/Medium | Rating integrity is mainly serializer-enforced | Admin/ORM paths can bypass 0–99 | Add model validators and database check constraints |
| Operational | Production execution remains unverified | Manifests/runbook/probes/monitoring hooks/backup and restore scripts exist, but no live URL, alert exercise, scheduled backup, or restore evidence is supplied | Execute and attach the runbook evidence checklist in the target environment |

## Threat examples and defenses

### A guardian changes the player ID

Django checks both the signed token’s player/user binding and the current guardian link. Changing only the URL ID invalidates the binding.

### A coach submits a player from another club

The backend resolves the session and player through same-club querysets; it does not trust the client’s club field.

### A stolen old Firebase token is used

Firebase Admin checks expiration/signature and `check_revoked=True`. Revocation can therefore be enforced, subject to Firebase availability and token behavior.

### Repeated PIN guessing

The PIN row is locked transactionally; failed attempts are counted, and the PIN is locked for 15 minutes after five failures.

### Direct Supabase access

The client has no database/storage service credential. Django is the only intended caller. RLS is not part of this topology and should not be claimed.

## Privacy/data minimization observations

- Guardian selector data is redacted until PIN unlock.
- Academic grades are not collected, reducing sensitive academic data scope.
- PIN plaintext is never stored.
- Unlock tokens are memory-only on the client.
- Player photos are represented by private object paths and short-lived signed URLs when storage is configured.
- Cached API reads are separated by Firebase UID, expire, are cleared on owner sign-out, and exclude guardian unlock responses.
- Injury and child-development data remain sensitive; a production project still needs consent, retention/deletion policies, breach response, and applicable Philippine Data Privacy Act review. Those governance artifacts were not found in executable code.

## Security answer to memorize

> Firebase authenticates the mobile identity, but Django authorizes every academy action. It verifies the revoked-token state, maps to an active local user, then checks role, club, object ownership, and guardian relationships. Child detail adds a hashed, throttled PIN and a ten-minute signed unlock token. Serializers, transactions, constraints, CSRF/Axes, server-only secrets, and production TLS settings add defense in depth.
