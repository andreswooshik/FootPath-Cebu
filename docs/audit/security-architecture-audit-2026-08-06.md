# FootPath Cebu Security and Architecture Audit

Audit date: 2026-08-06  
Scope: Django backend, Flutter client, Android release configuration, local persistence, CI configuration, and authenticated API flows.

## 1. Executive Summary

- Detected language/framework: Python 3 / Django 5.2 / Django REST Framework; Dart / Flutter / Riverpod; Android Kotlin Gradle DSL.
- Overall security rating: MEDIUM (improved; production deployment prerequisites remain).
- Code quality and standards rating: ACCEPTABLE, progressing toward production-ready.
- Key risk summary: The most important risk was relying on a client-only privacy-PIN gate and an account-agnostic offline attendance queue. Both now have server-issued unlock grants and owner-scoped persistence, but the deployment must use the required production secret, host, HTTPS, cache, and signing configuration before release.

## 2. Security Vulnerabilities

### Remediated: client-only player privacy gate

- Vulnerability: Sensitive player data was protected only by Flutter UI state. Severity: HIGH.
- Standard mapping: OWASP A01 Broken Access Control; CWE-862 Missing Authorization.
- Location: `backend/academy/views.py` player profile, attendance, eligibility, and injury read views; `footpath_cebu/lib/presentation/widgets/player_privacy_gate.dart`.
- Exploit scenario: A caller could bypass the UI and request a linked player's data directly with an otherwise valid bearer token.
- Secure remediation: `backend/academy/player_unlock.py` issues a signed, ten-minute, player-specific grant. Guardian-sensitive reads require `X-Player-Unlock`; PIN verification/setup returns the grant; Flutter stores only the short-lived token in memory.

### Remediated: offline attendance cross-account replay

- Vulnerability: The SQLite attendance outbox did not identify the signed-in account. Severity: HIGH.
- Standard mapping: OWASP A01; CWE-862; CWE-922 Insecure Storage of Sensitive Information.
- Location: `footpath_cebu/lib/data/local/attendance_outbox.dart` and `attendance_sync_service.dart`.
- Exploit scenario: Attendance queued under one account could be displayed or replayed after another account signed in on the same device.
- Secure remediation: schema version 2 stores `owner_uid`, all reads require the current Firebase UID, legacy unowned rows are discarded during upgrade, and tests cover two-account isolation.

### Remediated: production bearer-token transport and Android signing guardrails

- Vulnerability: Release configuration could target arbitrary HTTP/local endpoints and Android release builds used the debug signing key. Severity: HIGH when misconfigured.
- Standard mapping: OWASP A02 Cryptographic Failures; CWE-319 Cleartext Transmission; CWE-321 Use of Hard-coded Cryptographic Key.
- Location: `footpath_cebu/lib/core/config/api_config.dart` and `footpath_cebu/android/app/build.gradle.kts`.
- Secure remediation: release builds require HTTPS and reject local development hosts; release signing now requires externally supplied keystore variables and fails closed when absent. The Android network-security configuration remains free of invalid XML comments.

### Remediated: token revocation and distributed throttling

- Vulnerability: Firebase revocation was checked only for non-read requests, and production cache configuration was process-local. Severity: MEDIUM.
- Standard mapping: OWASP A07 Identification and Authentication Failures; CWE-613 Insufficient Session Expiration; CWE-307 Improper Restriction of Excessive Authentication Attempts.
- Location: `backend/accounts/authentication.py`, `backend/config/settings.py`.
- Secure remediation: every authenticated API request checks revocation; production requires `REDIS_URL`, while local development/tests retain LocMemCache.

### Remediated: uploaded image validation

- Vulnerability: player photo upload accepted declared image types without size/signature validation. Severity: MEDIUM.
- Standard mapping: OWASP A04 Insecure Design; CWE-434 Unrestricted Upload of File with Dangerous Type.
- Location: `backend/academy/storage.py`, `backend/academy/views.py`, `backend/portal/views.py`.
- Secure remediation: JPEG, PNG, and WebP allowlist, 5 MB limit, and magic-byte validation are applied before storage upload.

### Residual security items

- Temporary account passwords are still part of the current provisioning response contract. They must be replaced with one-time password-reset links before a public production launch; responses should remain `Cache-Control: no-store`.
- The local development `.env` must never be deployed. Production requires a generated high-entropy `DJANGO_SECRET_KEY`, explicit `DJANGO_ALLOWED_HOSTS`, HTTPS, and `REDIS_URL`.
- Firebase web configuration values are client configuration, not service credentials. Server-only Firebase and Supabase service credentials must remain outside source control.

## 3. Industry Standards and Architectural Anti-Patterns

### Remediated: unbounded sensitive data returned to selectors

- Anti-pattern / violation: linked-player selector returned full player profiles.
- Principle broken: Least privilege and Interface Segregation.
- Impact: a screen needing only identity and age tier received ratings, eligibility, and profile data before the privacy gate.
- Recommendation implemented: `PlayerSelectorSerializer` returns only selector fields; detailed profile reads use `PlayerDetailsReader` and an unlock grant.

### Remediated: serializer query count and duplicate age-tier values

- Anti-pattern / violation: per-session attendee counting and duplicate requested age tiers caused unnecessary work and unstable input handling.
- Principle broken: DRY and predictable data access.
- Recommendation implemented: annotated attendance counts and deterministic de-duplication in `backend/academy/serializers.py` and `views.py`.

### Remediated: signed-photo URL cache without expiry

- Anti-pattern / violation: an unbounded process cache could retain expired signed URLs.
- Principle broken: explicit resource lifecycle management.
- Recommendation implemented: Django cache entries expire before the signed URL lifetime; production uses shared Redis.

### Remediated: authentication/session concerns mixed into UI state

- Anti-pattern / violation: unlock state and PIN values were too closely coupled to widgets.
- Principle broken: Single Responsibility and Dependency Inversion.
- Recommendation implemented: a domain use case returns a server grant, a memory-only token store owns grants, and repositories inject the grant at the API boundary. Sign-out clears the grant store globally.

## 4. Performance and Logic Flaws

- Resolved N+1 attendee counting by using a filtered database annotation.
- Resolved cross-user offline replay and made sync dynamically follow the current authenticated UID.
- Added a 15-second timeout to session restoration so a dead API cannot hang startup indefinitely; transient server failures no longer forcibly sign the user out.
- Added storage URL caching with an expiry aligned to the signed URL lifetime.
- Remaining improvement: the remaining Flutter repositories should use a shared HTTP client with consistent timeout, retry, and cancellation policy before high-volume production use.
- Remaining improvement: push notifications are still synchronous in the request path; a production deployment should move them to a durable background worker such as Celery/RQ.

## 5. Production-Ready Refactored Code

The refactored implementation is in the repository. The principal files are:

- `backend/academy/player_unlock.py`
- `backend/academy/views.py`
- `backend/academy/serializers.py`
- `backend/academy/storage.py`
- `backend/academy/migrations/0013_playerunlock_indexes.py`
- `backend/accounts/authentication.py`
- `backend/config/settings.py`
- `footpath_cebu/lib/core/security/player_unlock_token_store.dart`
- `footpath_cebu/lib/data/local/attendance_outbox.dart`
- `footpath_cebu/lib/data/local/attendance_sync_service.dart`
- `footpath_cebu/lib/core/config/api_config.dart`
- `footpath_cebu/android/app/build.gradle.kts`

No secrets, service-account material, passwords, bearer tokens, private keys, or real deployment credentials are included in this report.

## Verification

- Flutter analyzer: passed with no issues.
- Flutter tests: 183 passed.
- Django tests: 186 passed.
- Django production deployment check with sanitized CI values: passed with no issues.
- `makemigrations --check --dry-run`: no changes detected.
- `git diff --check`: passed.

## Deployment actions still required

1. Set a unique production `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS`, `CORS_ORIGINS`, and `REDIS_URL`.
2. Provide Android release keystore variables to the protected build environment.
3. Replace temporary-password responses with one-time reset links.
4. Complete the shared Flutter HTTP-client timeout policy and move notifications to a durable worker.
