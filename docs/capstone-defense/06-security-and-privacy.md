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
- Player photo upload checks file size, MIME type, and signature before server-side upload.
- Coach license upload is size constrained.
- Public Club/Coordinator signup is disabled; the URL is informational and cannot mutate data.
- API actors cannot assign arbitrary trusted ownership fields.

## Secrets and transport

Production settings require a nontrivial Django secret, allowed hosts, explicit CORS origins, HTTPS redirect, secure cookies, HSTS, and a shared Redis cache. The release Flutter configuration requires HTTPS and can restrict the API host. Development is intentionally looser, including wildcard CORS.

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
9. Schedule create/update, assessment, and eligibility pushes are deferred until successful commit; cancellation deliberately sends before delete so recipients can still be resolved.
10. Production configuration includes TLS/cookie/HSTS/CORS safeguards.
11. Uploads are mediated by Django; the mobile client never receives service-role storage credentials.
12. Offline records are scoped to the Firebase owner UID.

## Concrete concerns and severity

| Severity | Concern | Consequence | Recommended remediation |
|---|---|---|---|
| Resolved | Player/Club/Profile invariant | Every executable Player flow delegates to `provision_player` | 24-case hierarchy suite plus provisioning tests |
| Resolved | Generic Player creation | `PLAYER` removed from generic choices and direct admin creation rejected | invariant tests pass |
| Medium | Squad-progress “admin all” behavior still filters by admin club | Incorrect/incomplete administrator data rather than an access expansion | Branch explicitly for admin, mirroring other queryset helpers |
| Medium | Portal CSP allows `unsafe-inline` and `unsafe-eval` for CDN UI scripts | Weakens XSS defense | Bundle/pin scripts locally and use nonces/hashes |
| Medium | Notification receiving/inbox UI is incomplete | Users may not see pushes while using the app or cannot revisit them | Add `onMessage`, opened-app routing, and a server-backed inbox/read state |
| Medium | Some HTTP calls lack explicit timeouts and detailed error parsing | Requests can wait too long; diagnosis/user feedback is generic | Centralize an API client with timeout, typed errors, and safe server-message mapping |
| Medium | Attendance read fallback catches broad repository errors | A queued view may mask an authorization/server error | Fall back only on a network-specific exception |
| Medium | Session confirmation silently catches submission errors | Player can believe an RSVP was saved when it was not | Expose controller error and show retry feedback |
| Low/Medium | Session time order is not validated | End time may precede start time | Use typed time fields/serializer cross-field validation |
| Low/Medium | Rating integrity is mainly serializer-enforced | Admin/ORM paths can bypass 0–99 | Add model validators and database check constraints |
| Operational | Production requires Redis and external secrets/storage setup | Misconfiguration blocks startup or weakens behavior | Document deployment, secret manager, backups, and monitoring |

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
- Injury and child-development data remain sensitive; a production project still needs consent, retention/deletion policies, breach response, and applicable Philippine Data Privacy Act review. Those governance artifacts were not found in executable code.

## Security answer to memorize

> Firebase authenticates the mobile identity, but Django authorizes every academy action. It verifies the revoked-token state, maps to an active local user, then checks role, club, object ownership, and guardian relationships. Child detail adds a hashed, throttled PIN and a ten-minute signed unlock token. Serializers, transactions, constraints, CSRF/Axes, server-only secrets, and production TLS settings add defense in depth.
