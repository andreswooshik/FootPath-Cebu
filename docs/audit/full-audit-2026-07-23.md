# FootPath-Cebu — Full-Scale Audit (July 23, 2026)

Supersedes the July 16 feature audit ([feature-audit.md](feature-audit.md)),
which is kept as a historical snapshot. Audited against
[docs/REQUIREMENTS.md](../REQUIREMENTS.md) (50% capstone defense scope) plus
everything merged since — PRs #5–#9 and the July 22–23 portal commits.

**Method:** read of the Django backend (`accounts`, `academy`, `console`,
`portal`), the Flutter client (`domain`, `data`, `presentation`, `services`),
both test suites executed, static analysis run, git/repo hygiene checked.

---

## Executive summary

| Area | Verdict |
|---|---|
| Backend test suite | ✅ 134/134 passing |
| Flutter test suite | ✅ 167/167 passing |
| Security posture | ✅ Strong (tenancy, object-level authz, secrets hygiene) |
| Spec coverage | ⚠️ ~85% — 2 features missing, 1 divergent, 1 data-loss bug |
| Repo hygiene | ⚠️ Minor issues (stray venvs, uncommitted generated files) |

Since July 16, the two biggest gaps closed: **School Staff eligibility
management** (now live in the web portal) and **eligibility status history**
(append-only trail + API + player/guardian views). A whole new surface landed:
**multi-club tenancy + coordinator portal** with public club registration.

The most important new finding is **F1: goalkeeper ratings are silently
dropped by the backend** — the GK assessment UI works, but the data never
persists in live mode.

> **Update — July 23 (afternoon):** F1, F5, and the housekeeping items are
> now fixed, and F4 was resolved by decision (club-registration signup is the
> sanctioned exception; every other account is provisioned by the
> coordinator). Backend suite is 143/143 after the fixes. Per-finding status
> notes below.

---

## Findings (ranked)

### F1 — HIGH · GK assessment ratings are not persisted
The client's assessment screen edits and sends **twelve** rating fields
(`PlayerRatings.toJson` in
[player.dart:125](../../footpath_cebu/lib/domain/entities/player.dart#L125)
includes `diving`, `handling`, `kicking`, `reflexes`, `speed`, `positioning`),
but the backend model
([academy/models.py:67-72](../../backend/academy/models.py#L67-L72)) only has
the six outfield columns:

- `AssessmentSerializer`
  ([serializers.py:82-99](../../backend/academy/serializers.py#L82-L99))
  accepts only the outfield six → GK values dropped on write, with a 200 OK.
- `PlayerSerializer.get_ratings`
  ([serializers.py:63-71](../../backend/academy/serializers.py#L63-L71))
  returns only the outfield six → `PlayerRatings.fromJson` zero-fills the GK
  fields on read.

**Failure scenario:** a coach assesses a goalkeeper in live mode, the save
succeeds, and after the next fetch every GK attribute reads 0. The mock
repository *does* carry GK data, which is why demos and the current tests
(fake-repo based) look fine.
**Fix:** add the six GK columns to `PlayerProfile` + migration, and include
them in both serializers.

> **Status: FIXED (July 23).** GK columns added (migration 0010), both
> serializers carry all twelve ratings, and an outfield-only payload leaves
> stored GK values untouched. Covered by three new regression tests
> including the wire-contract test.

### F2 — MEDIUM · Rating rubric diverges from spec
Spec: standardized **1–10 rubric, position-aware, goalkeeper variants**.
Build: **0–99 six-attribute FUT model**, now with a GK attribute-set variant
in the UI (a real step toward "position-aware"), but still not a 1–10 rubric
and outfield positions all share one attribute set. Needs a deliberate
decision: amend the spec or rework the model.

### F3 — MEDIUM · Match performance statistics missing entirely
In scope for the 50% milestone ("Player: view match performance statistics")
but there is no match/stat model, endpoint, or screen anywhere. Largest
unstarted item.

### F4 — MEDIUM · Public club registration contradicts the requirements
[portal signup](../../backend/portal/views.py#L44) is a public self-serve
registration flow (club + pending coordinator). The requirements say account
creation is Admin-only and public registration is "permanently out of scope by
design." The superadmin-approval gate (`is_active=False` until approved)
mitigates it, but this is a governance divergence that should be signed off or
the requirements updated before the defense.

> **Status: RESOLVED by decision (July 23).** Club registration is the one
> sanctioned public signup — every other account is provisioned by the
> club's coordinator (or Admin). REQUIREMENTS.md now records this.

### F5 — LOW · Age tiers hardcoded (spec: Admin-configurable)
`AgeTier` is a fixed enum
([academy/models.py:15-18](../../backend/academy/models.py#L15-L18)); no
config model, endpoint, or UI.

> **Status: FIXED (July 23).** New `AgeTierSetting` model (seeded 10–12 /
> 13–15 / 16–18), editable in the Django admin and the admin console's new
> Age Tiers card via `GET/PUT /api/age-tiers/` (writes Admin-only, overlap
> rejected). New players are now placed by the configured bands from their
> date of birth — both the console and coordinator-portal flows previously
> left age 0 / tier DEVELOPMENT silently. Existing players keep their stored
> tier by design.

### F6 — LOW · No role/permission management after creation
`/api/admin/users/` is list+create only; there is no endpoint or UI to change
a role or adjust permissions post-creation.

### F7 — LOW · Coach "Progress" (trends) tab is still a stub
[coach_bottom_nav.dart:44-47](../../footpath_cebu/lib/presentation/widgets/coach_bottom_nav.dart#L44-L47)
shows "Coming soon." for the Progress destination (and
[player_profile_screen.dart:153](../../footpath_cebu/lib/presentation/screens/player_profile_screen.dart#L153)
has another coming-soon action). Backend already has the attendance/effort
data a trends view needs.

### F8 — LOW · School Staff cannot *view* eligibility history in the portal
The REST endpoint permits staff reads, but the portal's
[staff eligibility page](../../backend/portal/templates/portal/staff_eligibility.html)
shows only the roster + update form — no history list. Spec explicitly gives
staff "view the eligibility status history of linked players."

### F9 — INFO · School Staff / Coordinators no longer use Firebase login
Spec: "Firebase-authenticated login for all roles." Staff and coordinators are
now **web users** with Django session auth (`provision_web_user`); app roles
still use Firebase. Reasonable architecture, but document the divergence.

### F10 — INFO · No general audit log
Disputes (append-only threads) and eligibility history are proper audit
trails; other sensitive changes (assessments, role/club edits) have none.

### Housekeeping — all done July 23
- ~~Two stray virtualenvs in `backend/` (`venv/` and `venc/`), neither of
  which has Django installed~~ — deleted. The real environment is the hidden
  `backend/.venv` (Django 5.2.15); the global Python also has Django 5.2.16,
  which is what the test runs here used.
- ~~Uncommitted generated-plugin changes for desktop targets~~ — these were
  line-ending phantoms only; `git add` normalized them away and the working
  tree is clean.
- ~~Stale docstring on `InjuryRecord` ("guardians see nothing")~~ — corrected
  to match the view (linked guardians read, writes stay player-only).

---

## Feature matrix vs REQUIREMENTS.md

Legend: ✅ live · ⚠️ partial/divergent · ❌ missing

### RBAC & Authentication
| Feature | Status | Notes |
|---|---|---|
| RBAC, no public self-registration | ✅ | RBAC solid (6 roles incl. Coordinator); club-registration signup accepted as the one sanctioned exception (F4 decision, July 23) |
| Firebase login for all roles | ⚠️ | App roles yes; staff/coordinators are Django-session web users (F9) |

### Admin
| Feature | Status | Notes |
|---|---|---|
| Provision accounts incl. guardian links | ✅ | API + console + coordinator portal |
| Manage role permissions | ⚠️ | Create-time only (F6) |
| Configure age tiers | ✅ | Fixed July 23: `AgeTierSetting` + admin/console UI + API (F5) |
| Three age tiers | ✅ | |

### Coach
| Feature | Status | Notes |
|---|---|---|
| Create/manage training schedules | ✅ | Club-scoped |
| Attendance (P/A/E), offline-first | ✅ | Outbox + sync service |
| 1–10 position-aware rubric + GK variant | ⚠️ | 0–99 FUT model (F2 divergence remains); GK variant now persists end-to-end (F1 fixed July 23) |
| Qualitative feedback | ✅ | Per-session note + standing coach notes |
| View player profiles | ✅ | |
| View performance trends | ⚠️ | Tab is a stub (F7) |
| Position assignment | ✅ | **New:** wired end-to-end July 23 |

### Player
| Feature | Status | Notes |
|---|---|---|
| Own profile | ✅ | |
| Schedule & attendance | ✅ | Plus RSVPs (beyond spec) |
| Coach feedback & ratings | ✅ | |
| Match statistics | ❌ | Not started (F3) |
| Injury history CRUD | ✅ | |
| Eligibility status | ✅ | Plus history view (new) |

### School Staff
| Feature | Status | Notes |
|---|---|---|
| Update eligibility (no grades) | ✅ | **New:** live via portal, club-scoped, school-affiliated clubs only |
| View eligibility history | ⚠️ | API allows it; no portal surface (F8) |
| Status flags only, never grades | ✅ | |

### Guardian
| Feature | Status | Notes |
|---|---|---|
| Login, linked to ≥1 player | ✅ | |
| Read-only child profile/attendance/ratings/schedule | ✅ | Plus injury history (new, link-scoped) |
| Child eligibility status | ✅ | Plus history |

### System
| Feature | Status | Notes |
|---|---|---|
| Push notifications | ✅ | Schedule, assessment, eligibility |
| Dispute + audit foundation | ✅/⚠️ | Disputes + eligibility trail live; no general audit log (F10) |

### Beyond spec (new since July 16)
Multi-club tenancy · Coordinator role + portal (registration/approval,
provisioning, roster/coaches/guardians pages, Tailwind restyle) · coach
license upload (50 MB, sanitized filenames) · session RSVPs · attendance
session-window gating · guardian injury visibility.

---

## Quality & security assessment

**Tests:** backend 134/134 and Flutter 167/167 passing. Coverage is broad
(provisioning, tenancy, authz, offline sync, portal flows). Gap: nothing
exercises the live GK-ratings round-trip (which is why F1 survived).

**Security (good):** env-driven `SECRET_KEY`/`DEBUG`, prod hardening block,
CORS allowlist outside DEBUG, secrets/DB/venvs untracked, randomized
upload filenames with extension whitelist, 50 MB form-level cap with a 6 MB
non-file body backstop, consistent object-level authorization (attendance,
injuries, eligibility history), server-side club tenancy derived from
`request.user` (never client input), school-staff gating on school
affiliation enforced in both view and service.

**Architecture:** clean layering on both sides — Django views → services,
Flutter domain/data/presentation with Riverpod DI and swappable mock/API
repositories (release builds force live). Wire enums mirrored between client
and server.

## Recommended order of attack

~~F1 (GK persistence)~~, ~~F4 (registration decision)~~, ~~F5 (tier
config)~~, and ~~housekeeping~~ were closed on July 23. Remaining:

1. Decide F2 (1–10 rubric vs 0–99 attributes) with the team lead.
2. Build F3 (match stats) — biggest remaining scope item.
3. Close the small ones: F8 staff history view, F7 trends tab, F6 role
   management.
