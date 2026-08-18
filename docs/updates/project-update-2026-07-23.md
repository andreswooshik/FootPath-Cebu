# FootPath-Cebu — Project Update (July 23, 2026)

> **Historical snapshot:** Public Club registration described below was later
> removed. The current architecture is documented in
> [Account and Club Hierarchy](../ACCOUNT-AND-CLUB-HIERARCHY.md).

**To:** Team Leader
**From:** Ralf Andre Ebuna
**Period covered:** July 16 – 23, 2026

## TL;DR

A very productive week. The two biggest functional gaps from the July 16 audit —
School Staff eligibility management and eligibility status history — are now
live, and we shipped a whole new surface: a multi-club web portal with public
club registration, coordinator account provisioning, and school-staff
eligibility tools. Both test suites are fully green (134 backend, 167 Flutter).
The main remaining risks for the 50% defense are the rating-rubric spec
divergence and match statistics, which have not been started.

## What shipped this week

**Club Coordinator & School Staff web portal (PR #9 + follow-ups)**
- Public club registration form with coach-license upload (up to 50 MB) and
  CVFA membership details; new clubs stay pending until a superadmin approves.
- Multi-club tenancy across the whole backend: every player, coach, guardian,
  and staff account belongs to a club, and all queries/permissions are
  club-scoped server-side.
- Coordinators can provision Players, Coaches, Guardians, and (for
  school-affiliated clubs) School Staff, with one-time credentials generated
  per account.
- School Staff now have a working eligibility screen — they can update a
  player's academic status from the portal, which writes the append-only
  history row and pushes notifications to the player and guardians. This
  closes the biggest ❌ from the last audit.
- Portal restyled with Tailwind (green sidebar), plus dedicated Coaches and
  Guardians pages.

**Eligibility history (PR #8)**
- New append-only `EligibilityHistory` trail written on every status change,
  regardless of which surface made it (admin, console, portal).
- Read API with strict object-level access (player, linked guardians, staff,
  admin — deliberately not coaches), surfaced in the Player and Guardian
  dashboards.
- Guardians can now also view a linked child's injury history (read-only).

**Coach & scheduling flows (PRs #6–#7 + this week's commits)**
- Attendance & evaluation screen with per-session effort and notes;
  evaluation notes now save correctly (bug fixed July 20).
- Session RSVPs for players, persisted server-side; attendance logging is
  gated to a window around the session; Player/Guardian schedule views no
  longer show coach-only controls.
- Goalkeeper assessment variant in the UI (GK-specific attribute set with its
  own overall).
- Coach position assignment is now wired end-to-end to a real endpoint
  (was a client-side stub).

**Quality**
- Backend: 134 tests passing. Flutter: 167 tests passing.
- Security posture is solid: club tenancy enforced server-side, object-level
  authorization on every sensitive read, secrets/DB out of git, env-driven
  settings with production hardening.

## What's left for the 50% milestone

1. **Match performance statistics** — not started; no model, endpoint, or UI.
2. **Rating rubric decision needed** — the spec says a 1–10 position-aware
   rubric; the build uses a 0–99 six-attribute model. We should either get the
   spec amended or plan the rework now.
3. **GK ratings persistence bug** (found in today's audit) — the goalkeeper
   attributes are edited in the UI but silently dropped by the backend; needs
   a small backend fix before GK assessments can be trusted in live mode.
4. **Admin: configurable age tiers** and **post-creation role management** —
   both still pending.
5. **Coach performance-trends tab** — still a stub.

## Decisions / sign-offs needed from you

- The portal's **public club registration** is a deliberate extension, but the
  requirements doc says "no public self-registration." It is gated behind
  superadmin approval, but we should get this divergence signed off (or the
  requirements updated) before the defense.
- Confirmation on the **1–10 rubric vs 0–99 attribute model** question above.
