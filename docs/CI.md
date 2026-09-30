# CI and release-build checks

The workflow is `.github/workflows/ci.yml`. It runs for pull requests, pushes to
`main`, merge queues, and manual dispatch. A newer run cancels an older run for
the same ref.

The six jobs are:

| Job | Checks |
| --- | --- |
| Django backend | Hashed dependencies, Ruff lint/format, full SQLite test suite, migration drift, production checks, operations scripts |
| Django PostgreSQL integration | Full suite against the isolated PostgreSQL 17 service, including locking/concurrency tests |
| Backend security checks | Dependency advisory audit and Bandit; runs independently so audit-service availability cannot prevent test logs being collected |
| Production container | Compose validation and image build, after backend and security checks pass |
| Flutter app | Locked dependency resolution, analysis, full VM suite, Chrome IndexedDB persistence test |
| Flutter release builds | Web and APK builds after all preceding checks pass |

No test/security failure is ignored. Bash's `pipefail` preserves failures when
test output is piped to `tee`. Test logs are uploaded even after failure and
retained for seven days. The release-build job uploads web/APK artifacts only
on success. APKs use a temporary CI signing key; these artifacts are for build
verification, not store publication. This workflow does not deploy production.
If branch protection uses a fixed list of required checks, include the new
`Backend security checks` and `Flutter release builds` checks alongside the
existing checks. The workflow itself already gates builds on both test jobs,
security, and container validation.

The runner is Ubuntu 24.04. Python remains on the application's 3.12 production
line. Flutter is pinned to the locally validated 3.44.2 SDK (Dart 3.12.2), and
Android builds explicitly install Java 17. Change `FLUTTER_VERSION` deliberately
alongside dependency/lockfile validation, rather than tracking the moving stable
release. SQLite native libraries are installed for the Flutter FFI tests, and
Chrome is resolved explicitly from the runner's installed browser.

Local `.env` files are disabled in CI; Django steps use explicit test/check
configuration. The PostgreSQL job uses only `TEST_POSTGRES_*` settings and a
`test_` database. No Firebase, Supabase, or deployment secrets are required.

## Local checks

From `backend`, using its virtual environment:

```text
python -m ruff check .
python -m ruff format --check .
python manage.py test --noinput
```

From `footpath_cebu`, using Flutter 3.44.2:

```text
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter test --no-pub --platform chrome test/data/web_attendance_outbox_browser_test.dart
```

Set `CHROME_EXECUTABLE` to your browser path if Flutter cannot locate Chrome.
Use the isolated configuration from the workflow when running migration or
deployment checks locally; do not reuse live database credentials.

## Validation of the September 29 update

- Fixed the four files rejected by the workflow's Ruff formatting check.
- Ruff lint, full backend formatting check, and Bandit passed locally.
- Workflow YAML was parsed with duplicate-key detection; job dependencies,
  release gates, timeouts, and failure propagation were checked.
- Locked Flutter dependencies resolved successfully from the local cache using
  `flutter pub get --offline --enforce-lockfile`, without changing the lockfile.
- Django migration drift and `check --deploy --fail-level WARNING` passed using
  the workflow's isolated environment values.
- The full backend suite was rerun with the workflow's explicit test environment
  and `.env` loading disabled: 511 tests ran successfully (7 skipped on SQLite).
  The preceding architecture-fix validation passed 478 Flutter tests. Local Python is 3.14;
  Python 3.12/Linux and PostgreSQL verification must still run in Actions.
- The local headless Chrome test reached the browser but stalled while loading
  the suite; a diagnostic retry also stalled and was stopped. Browser validation
  is therefore not claimed as passed. CI retains the test with a five-minute
  step timeout and captured output; it is not skipped or allowed to fail.

GitHub run history was unreachable during this update. Docker/PostgreSQL were
not available on the local PATH, so container and PostgreSQL jobs were not
executed locally. A hosted green run can be confirmed after these changes and
the accompanying application fixes are pushed. Manual dispatch runs the code
already present on the selected remote branch, not uncommitted local changes.

Action configuration references: [Flutter version pinning](https://github.com/subosito/flutter-action#use-specific-version-and-channel),
[Java setup](https://github.com/actions/setup-java), and
[artifact retention and upload](https://github.com/actions/upload-artifact).
