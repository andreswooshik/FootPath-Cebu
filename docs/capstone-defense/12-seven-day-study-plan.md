# Seven-Day Defense Study Plan

Use 2 hours 30 minutes of active study per day plus a 15-minute break (2 hours 45 minutes elapsed). Each day ends with a closed-notes oral drill and one evidence-based code trace.

## Exact daily time blocks

| Day | 30 min theory/purpose | 45 min actual code | 15 min | 30 min system/data flow | 30 min panel questions | 15 min recall/self-test |
|---|---|---|---|---|---|---|
| 1 | problem, users, reconstructed objectives, scope | README/requirements alignment; roles in models/HomeScreen | Break | objective → feature → module → table mapping | Q1–Q10, Q71–Q75 | record 90-second opening; list five absent features |
| 2 | layered architecture, trust boundaries, OOP | `main.dart`, `providers.dart`, shared API client/cache, one repository stack | Break | draw startup/login architecture twice | Q11–Q20; C1–C14 | trace startup in 60 seconds without notes |
| 3 | Flutter/Riverpod async/state concepts | login, schedule, assessment, provider/controller files | Break | button → controller → use case → repository for three writes | Flutter/code questions C1–C14, C39–C40 | name ten Dart files and their responsibility |
| 4 | relational design, constraints, transactions | account/academy models, serializers, migrations | Break | attendance/profile/eligibility lifecycles and ERD | Q36–Q66; C18–C30 | redraw tables/FKs/deletion behavior |
| 5 | auth, RBAC, tenancy, privacy threats | authentication, permissions, PIN/unlock, portal security | Break | changed-ID and PIN-guess attack traces | Q21–Q35; C15–C23 | recite PIN numbers and server checks |
| 6 | testing, AI truth, limitations, reliability | offline outbox/cache, notification path, production artifacts, CI | Break | online/offline/cache and notification failure paths | Q67–Q80; attack A1–A30 sample | exact verification statement + remaining risks |
| 7 | full project recap and demo theory | open top ten files and rehearse code jumps | Break | timed 10–12 minute live/fallback demo | random 20 panel + 10 trace questions | score mock defense and review only misses |

The sections below give each day’s objectives, files, practical task, and expanded self-test.

## Day 1 — Truth, scope, and opening

### Learn

- Read `01-project-overview.md` and `13-rapid-recall-sheet.md`.
- Memorize the one-sentence defense, users, problem, reconstructed objectives, and scope boundary.
- Practice saying “not implemented” for AI, scouting, match stats, chat, and mapping without sounding apologetic.
- Understand the remaining rating-scale discrepancy and why the reconciled README now matches Django ORM as the data authority.

### Inspect

- `README.md` and `docs/REQUIREMENTS.md` to distinguish reconciled architecture from the remaining rating-specification drift.
- `backend/accounts/models.py` for six roles.
- `footpath_cebu/lib/presentation/screens/home_screen.dart` for three mobile roles.

### Deliverable

Record a 90-second opening. It must mention Flutter, Django, Firebase identity, relational persistence, roles, core value, and absent AI.

### Closed-notes drill

Answer Q1–Q10 and Q71–Q75 in under 12 minutes.

## Day 2 — Architecture and OOP

### Learn

- Read `02-system-architecture.md`, `04-code-explanation.md`, and glossary sections for layers/OOP.
- Draw the architecture from memory twice.
- Explain dependency inversion, repository polymorphism, and the offline decorator.
- Explain why `AuthenticatedApiClient` centralizes token, timeout, typed errors, multipart upload, and network-only safe-cache behavior.

### Inspect

- `main.dart`.
- `core/di/providers.dart`.
- one entity, repository interface, use case, controller, API repository, mock repository.
- `data/network/authenticated_api_client.dart` and `data/local/api_get_cache.dart`.

### Deliverable

Give a five-minute code tour without opening more than eight files.

### Closed-notes drill

Answer Q11–Q20 and code questions C1–C14. Trace startup from `main()` to role portal.

## Day 3 — Authentication, security, and privacy

### Learn

- Read `06-security-and-privacy.md`.
- Separate authentication, authorization, tenancy, object permission, and PIN privacy.
- Memorize PIN numbers: 4–6 digits, five failures, 15-minute lock, ten-minute unlock, recent auth within five minutes.

### Inspect

- `firebase_auth_repository.dart`.
- `accounts/authentication.py` and `permissions.py`.
- `academy/pin_service.py` and `player_unlock.py`.
- guarded guardian view helpers.

### Deliverable

Draw two threat traces: changed player ID and repeated PIN guessing. State every server check.

### Closed-notes drill

Answer Q21–Q35 and C15–C23. Have a teammate interrupt with “But Flutter can be hacked”; respond with backend evidence.

## Day 4 — Data and major workflows

### Learn

- Read `03-system-flow.md` and `05-database-and-data-flow.md`.
- Learn key relationships, unique constraints, transactions, and deletion behavior.
- Practice assessment, schedule, attendance, eligibility, injury, dispute, and confirmation flows.

### Inspect

- `academy/models.py`, relevant serializers, and relevant sections of `academy/views.py`.
- Flutter assessment and attendance call chains.
- `academy/signals.py`.

### Deliverable

On paper, reconstruct the schema map and trace one write with success and failure paths.

### Closed-notes drill

Answer Q36–Q66 and C24–C30.

## Day 5 — Offline sync, tests, and limitations

### Learn

- Read `08-testing-and-limitations.md` and the offline sections of the trace chapter.
- Memorize verified test facts and what was not executed.
- Understand complete-batch replacement, owner scoping, ordered replay, and last-write-wins.
- Study the resolved Player aggregate, Super Admin progress, session-time, RSVP, notification, and fallback findings, then distinguish them from current limitations.

### Inspect

- `attendance_outbox.dart`, `api_get_cache.dart`, `authenticated_api_client.dart`, `attendance_sync_service.dart`, and `offline_first_attendance_repository.dart`.
- `accounts/services.py`, both seed commands, and Player invariant tests.
- notification model/helper/endpoints plus Flutter inbox/bell/FCM listeners.
- `.github/workflows/ci.yml`, production Compose/Docker files, and `docs/PRODUCTION-OPERATIONS.md`.

### Deliverable

Explain offline attendance to a nontechnical listener in one minute, then to a developer in three minutes.

### Closed-notes drill

Answer Q67–Q80 and C31–C41. Quote only the latest verified command output; never reuse an older count after tests change.

## Day 6 — Demo rehearsal and attack mode

### Learn

- Read `11-demo-script.md` and `15-panel-attack-mode.md`.
- Prepare live disposable data and a reset snapshot.
- Ensure `USE_MOCK=false` and test each external dependency.

### Rehearse

1. Run the full demo timed.
2. Run the three-minute fallback.
3. Simulate one network failure and one PIN failure.
4. Rehearse the inbox/foreground-push boundary and Coach photo upload with configured disposable services.
5. Practice switching to code/evidence calmly.
6. Have a teammate ask all 30 attack questions randomly.

### Deliverable

A demo run under 12 minutes with zero secret exposure and an explicit limitations close.

### Closed-notes drill

Answer 20 randomly selected panel questions, 10 code questions, and 10 trace questions.

## Day 7 — Full mock defense and correction

### Morning

- Read the master reviewer once.
- Write the architecture, roles, tables, and top 20 chains from memory.
- Review only missed items, not the entire pack repeatedly.

### Mock panel

Run a 30–45 minute session:

1. 90-second opening.
2. 10-minute live demo.
3. 15 minutes of panel questions.
4. 10 minutes of code tracing.
5. 5 minutes of attack questions and limitations.

Require the mock panel to ask where the AI is, how cross-club access is stopped, whether Supabase uses RLS, whether tests really passed, and why the specification differs.

Also require proof-oriented questions: “Is the live deployment verified?”, “Did a restore drill run?”, “Can a 403 be hidden by cache?”, and “What remains when FCM transport fails?”

### Final correction

- Correct facts, not delivery style only.
- Bookmark ten high-value files.
- Verify demo credentials/data without printing secrets.
- Stop making feature changes unless a critical fix is already tested and controlled.
- Sleep; do not trade recall and judgment for an unstable last-minute feature.

## Daily scoring rubric

Score each area 0–2:

| Area | 0 | 1 | 2 |
|---|---|---|---|
| Accuracy | Invents/contradicts code | Mostly correct | Exact and bounded |
| Architecture | Cannot trace | Names layers | Explains dependencies/trust |
| Security | Says “Firebase protects it” | Names roles | Explains token + club/object/PIN |
| Evidence | No file/function | Vague module | Direct path/symbol |
| Limitations | Hides/guesses | Admits | Explains impact/remediation |
| Delivery | Rambling | Understandable | Direct short then technical |

Daily target: at least 10/12. Final-day target: 12/12.

## Best response pattern

Use this four-part form:

1. Direct answer in one sentence.
2. Technical mechanism in two or three sentences.
3. Exact evidence path/function.
4. Limitation or tradeoff if material.

Example:

> No, we do not use Supabase RLS. Flutter never accesses Supabase directly; Django verifies Firebase identity and applies role, club, and object authorization before ORM access. Supabase can host PostgreSQL/storage only. The evidence is `settings.py`, `accounts/authentication.py`, and `academy/storage.py`.
