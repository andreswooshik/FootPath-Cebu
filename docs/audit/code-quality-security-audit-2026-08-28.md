# Code quality, architecture, and security audit

Audit date: 2026-08-28
Scope: tracked Django, Flutter, Android, web portal, CI, dependency, and
repository-organization code.
Benchmark: OWASP ASVS 5.0, OWASP MASVS, and the Django deployment checklist.

This is an engineering audit, not a penetration-test certification. It covers
static review, automated checks, architecture boundaries, and existing tests.

## Executive result

No unresolved Critical or High finding was identified in the reviewed scope.
The codebase has a sound foundation and is suitable for continued release
hardening, but it should not be described as perfectly SOLID or strict MVVM.

| Area | Result | Notes |
| --- | --- | --- |
| Repository structure | Good | Source, operations, docs, and artifacts now have clear homes. |
| Flutter architecture | Good | Clean Architecture with Riverpod-based MVVM-style presentation. |
| Django architecture | Acceptable | Correct Django MTV/service approach; several modules are too large. |
| SOLID | Good with SRP debt | Dependency direction is clean; large views/screens need gradual extraction. |
| Security controls | Good, conditional | Strong server authorization and production guards; medium hardening remains. |
| Automated verification | Strong | Backend, Flutter, dependency, static-security, and deployment checks pass. |

## Repository organization

The intended top-level layout is:

```text
FootPath-Cebu/
|-- .github/             CI and dependency-update configuration
|-- backend/             Django API, portal, admin, and operations scripts
|-- docs/                Audits, architecture, operations, and reviewed artifacts
|-- footpath_cebu/       Flutter application and tests
|-- compose.production.yml
`-- README.md
```

Changes made during this audit:

- moved the dated root audit into `docs/audit/`;
- moved defense study notes into `docs/capstone-defense/`;
- moved the reviewed tracing PDF into `docs/capstone-defense/artifacts/`;
- moved PDF utilities into `docs/tools/` and updated their paths;
- added `docs/README.md` as the documentation index;
- ignored disposable root `tmp/` and `output/` workspaces; and
- removed the accidentally tracked Git commit-message scratch file.

## Architecture audit

### Flutter and MVVM

The Flutter application is better described as Clean Architecture with an
MVVM-style Riverpod presentation layer:

- **View:** `presentation/screens/` and `presentation/widgets/`;
- **ViewModel/state:** controllers, `Notifier`/`AsyncNotifier`, and presentation
  providers;
- **Model/business rules:** domain entities, use cases, and repository
  interfaces;
- **Infrastructure:** API, Firebase, SQLite outbox, and repository
  implementations in `data/`; and
- **Composition root:** `core/di/providers.dart` selects and wires concrete
  implementations.

Static import checks found no domain-to-data/presentation import, no
data-to-presentation import, and—after this audit—no presentation-to-data
import. Notification repository construction was moved out of presentation and
into the composition root. This restores dependency inversion.

### Django

Django appropriately uses MTV rather than MVVM. Models and serializers define
the data and API contracts, views handle transport/orchestration, and service
modules contain cross-model workflows. Django ORM writes to the configured
Supabase PostgreSQL database in production; SQLite remains test/development
fallback only.

The main maintainability weakness is module size. Examples at audit time:

- `backend/academy/views.py`: about 1,780 lines;
- `backend/academy/models.py`: about 924 lines;
- `backend/academy/serializers.py`: about 812 lines;
- `backend/portal/views.py`: about 638 lines; and
- `footpath_cebu/lib/presentation/screens/log_attendance_screen.dart`: about
  873 lines.

These are not automatically defects, but they increase review cost and make
single-responsibility regressions more likely. Split them feature-by-feature,
while preserving public imports and tests, instead of doing one risky rewrite.

## SOLID assessment

| Principle | Assessment |
| --- | --- |
| Single Responsibility | Partial. Layer responsibilities are clear, but large backend modules and Flutter screens combine too many feature details. |
| Open/Closed | Good. Repository interfaces and Riverpod overrides permit new implementations without changing views/use cases. |
| Liskov Substitution | Good. Mock, API, and offline-first implementations are exercised through shared interfaces. |
| Interface Segregation | Mostly good. Focused repository contracts exist; runtime capability casts such as writer interfaces should eventually become explicit providers without casts. |
| Dependency Inversion | Good after the notification-provider fix. Domain code has no framework/infrastructure dependency. |

## Security assessment

### Controls verified

- production settings fail closed when the secret, allowed hosts, PostgreSQL,
  Redis, or secure origins are missing;
- Django production middleware enables HTTPS redirect, HSTS, secure cookies,
  CSRF protection, clickjacking protection, MIME sniffing protection, and
  explicit CORS origins;
- Argon2id is the preferred Django password hasher and django-axes provides
  login lockout;
- Firebase bearer tokens are verified server-side and accepted only for active,
  Admin-provisioned users with server-owned roles;
- club and player authorization is rechecked server-side, including Guardian
  links and School Staff affiliation;
- Supabase service credentials stay in Django; Flutter receives authorized,
  short-lived signed storage URLs rather than storage credentials;
- privacy PINs are hashed, rate-limited, and exchanged for short-lived,
  player-scoped unlock grants;
- general authenticated GET responses are no longer stored on-device by
  default; no production repository opts into that cache;
- Android application backup is disabled, reducing leakage of the required
  offline attendance outbox;
- static HTML help text uses `format_html` with escaped values instead of a
  broad `mark_safe` call;
- Python dependency minimums exclude all advisories detected in the audited
  environment; and
- CI now runs dependency auditing, medium/high Bandit checks, production Django
  checks, tests, Flutter analysis, and Flutter tests. Dependabot monitors Python,
  Dart, npm, Docker, and GitHub Actions weekly.

### Remaining findings

| ID | Severity | Finding | Recommended action |
| --- | --- | --- | --- |
| CQ-01 | Medium | Large views, serializers, models, and screens weaken single responsibility. | Extract one bounded feature at a time into services/controllers/widgets and keep regression tests around each extraction. |
| SEC-01 | Medium | Offline attendance must temporarily persist attendance state and notes in ordinary app-private SQLite. It is owner-scoped, deleted after acknowledgement, and excluded from Android backup, but is not application-layer encrypted. | Encrypt the outbox with a Keystore-backed database/key, minimize free-text notes, and enforce a retry/expiry retention policy. |
| SEC-02 | Medium | Admin and Coordinator accounts do not enforce MFA. | Require Firebase MFA or an equivalent second factor for privileged roles and protect recovery flows. |
| SEC-03 | Low | Release traffic requires HTTPS, but the mobile app does not pin certificates. | Add renewable backup pins for controlled API endpoints if the deployment threat model requires MASVS-NETWORK-2. |
| REL-01 | Medium | Android still uses `com.example.footpath_cebu`. | Migrate the application ID and matching Firebase Android app together before store release. |
| SUP-01 | Low | Python dependencies have security floors but no hash-locked, fully transitive production lock file. | Generate and maintain hashed production constraints; build images only from reviewed lock updates. |

Canonical football, identity-mapping, eligibility, injury, match, and schedule
data remains server-authoritative in PostgreSQL/Supabase. The attendance outbox
is a temporary synchronization queue required by the offline-first feature; it
must never become the source of truth.

## Verification evidence

- Django: 321 tests passed.
- Flutter: 276 tests passed.
- Flutter analyzer: no issues.
- Django deployment check: no issues.
- Django migration drift: none.
- Python `pip check`: no broken requirements.
- Python dependency audit after upgrade: no known vulnerabilities.
- Bandit medium/high scan: no findings.
- npm dependency audit: no known vulnerabilities.
- Flutter dependency review: several compatible updates are available; weekly
  Dependabot updates are enabled so they can be upgraded and tested separately.
- Android APK verification: the machine's global Gradle cache reproduced its
  existing corrupted-lock error. An isolated fresh cache passed configuration
  and compilation and reached native-library merging, then the C: drive ran out
  of space. No fresh APK was produced; this is an environment/storage blocker,
  not a source-level test failure.

## Recommended order of follow-up work

1. Replace the Android application ID together with Firebase configuration.
2. Add privileged-role MFA.
3. Encrypt and expire the offline attendance outbox.
4. Introduce hashed Python production constraints.
5. Split `academy/views.py` and the largest Flutter screens along feature
   boundaries, without changing behavior.

## Standards used

- OWASP Application Security Verification Standard 5.0:
  <https://owasp.org/www-project-application-security-verification-standard/>
- OWASP Mobile Application Security Verification Standard:
  <https://mas.owasp.org/MASVS/>
- Django 5.2 deployment checklist:
  <https://docs.djangoproject.com/en/5.2/howto/deployment/checklist/>
- Django 5.2 system checks:
  <https://docs.djangoproject.com/en/5.2/ref/checks/>
