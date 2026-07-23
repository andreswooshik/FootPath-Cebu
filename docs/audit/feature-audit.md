# FootPath-Cebu — Feature Audit

_Audit of the specified feature set against the actual implementation, with a
focus on whether each feature is **live with the backend** (real Django
endpoint + wired client/console, not a mock-only stub)._

Every repository in the Flutter app has a real Django API implementation that
is selected when `USE_MOCK=false` (release builds always run live). So the
gaps below are genuine — not mock-only stubs.

## Legend

- ✅ **Live** — real Django endpoint + wired client/console
- ⚠️ **Partial** — implemented differently than specified, or only via one surface
- ❌ **Missing / not live**

---

## RBAC & Authentication

| Feature | Status | Notes |
|---|---|---|
| RBAC across 5 roles, no public self-registration | ✅ | Roles enum + server-side permission checks; no register endpoint; account creation is `IsAdmin`-only |
| Firebase login for all roles, Admin-issued credentials | ✅ | `MeView` verifies the Firebase ID token → provisioned account |

## Admin

| Feature | Status | Notes |
|---|---|---|
| Provision accounts, incl. linked Guardian accounts | ✅ | `/api/admin/users/`, `/api/admin/guardian-links/` + web console (`/console/`) |
| Assign & **manage** role-based permissions | ⚠️ | Role is set **at creation**; no endpoint to change a role or manage granular permissions afterward |
| Configure age-tier settings | ❌ | Tiers are **hardcoded enums**; no config model/endpoint/UI |
| Three age tiers (Foundation 10–12, Development 13–15, Pathway 16–18) | ✅ | Implemented incl. `forAge` mapping |

## Coach

| Feature | Status | Notes |
|---|---|---|
| Create/manage training schedules | ✅ | `TrainingSessionListCreateView` + `ApiTrainingRepository` |
| Record attendance (Present/Absent/Excused), offline-first sync | ✅ | `OfflineFirstAttendanceRepository` + outbox + `AttendanceSyncService` (starts on login) |
| Rate performance on **1–10 rubric, position-aware + goalkeeper variant** | ⚠️ | A rating system exists, but it's the **0–99 six-attribute FUT model for all positions** — not a 1–10 rubric, not position-aware, no goalkeeper variant |
| Record qualitative feedback | ✅ | Per-session effort + note in the roll-call screen |
| View player profiles | ✅ | `PlayerProfileScreen` (radar + attributes) |
| View performance **trends** | ⚠️ | Player has a Progress tab; the **Coach's "Progress" tab is a "Coming soon" stub** |

## Player

| Feature | Status | Notes |
|---|---|---|
| View own profile (position, tier, attributes) | ✅ | |
| View training schedule & attendance record | ✅ | |
| View coach feedback & ratings | ✅ | Ratings on card; notes in Progress |
| View **match performance statistics** | ❌ | No match/game model anywhere (no goals/assists/stats) |
| Injury history (CRUD) | ✅ | `ApiInjuryRepository` |
| View current eligibility status (status only, no grades) | ✅ | Status shown on profile; grades never stored |

## School Staff

| Feature | Status | Notes |
|---|---|---|
| Update a player's eligibility status (no grades) | ⚠️❌ | The `eligibility` field exists and changing it works — but **only via Django admin (superuser)**. No School-Staff REST endpoint and no app screen (School Staff logs into the app → generic placeholder) |
| View eligibility **status history** of linked players | ❌ | No history model — the signal pushes a notification but records no history row |
| Eligibility gating by status flags only, never raw grades | ✅ | Only a status enum is stored; grades are never entered/exposed |

## Guardian

| Feature | Status | Notes |
|---|---|---|
| Login with own credentials, linked to ≥1 player | ✅ | `GuardianLink` + `players/linked/` |
| Read-only view of child's profile/attendance/ratings/schedule | ✅ | `GuardianDashboardScreen`, object-scoped authz |
| View child's academic eligibility status (status only) | ✅ | |

## System / Notifications

| Feature | Status | Notes |
|---|---|---|
| Deliver push notifications | ✅ | FCM fan-out for **schedule, assessment, eligibility**; device registration on login |
| Player/Guardian receive push (schedule, feedback, eligibility) | ✅ | All three event types wired |
| Dispute + audit-log foundation (Coach flag/respond, Staff, Admin review) | ⚠️ | Disputes fully live (append-only thread = audit trail); **no general audit log** beyond disputes |

---

## Missing-features checklist (not live with backend)

- [ ] **School Staff eligibility update** — add `PATCH /api/players/<id>/eligibility/` (role = School Staff/Admin) + a School Staff app/console screen. _(Backend field + push already exist; just no role-facing live path.)_
- [ ] **Eligibility status history** — add an `EligibilityHistory` model (who/when/old→new), write it from the existing signal, expose a read endpoint + Guardian/Player/Staff view.
- [ ] **1–10 position-aware rating rubric + goalkeeper variant** — currently a 0–99 six-attribute FUT model for everyone; needs the rubric redefined (and GK-specific fields) if the spec is firm.
- [ ] **Player match performance statistics** — no match model at all; needs `Match`/`MatchStat` models, endpoints, and player/guardian views.
- [ ] **Admin: configure age-tier settings** — tiers are hardcoded; needs a config model + admin UI (or confirm "fixed three tiers" is acceptable).
- [ ] **Admin: manage role permissions after creation** — add role-change / permission-management endpoint + console UI.
- [ ] **Coach performance-trends view** — the Coach "Progress" tab is a stub; wire it to the existing attendance/effort data (backend already has it).
- [ ] _(Optional)_ **General audit log** — only dispute threads are audited today.

---

## Notes on scope divergence

- **Everything implemented in the app is already live-capable** — every repository has a real Django API implementation selected when `USE_MOCK=false`; release builds force live. The ⚠️/❌ items are genuine gaps, not mock-only stubs.
- The **rating rubric** and **match statistics** items are where the spec and the build diverge most: the app has a _different_ rating model (FUT attributes) rather than a partial version of the requested 1–10 rubric, and match statistics do not exist at all.
- **School Staff** currently has no functional interface in either the app (routes to a placeholder) or the console (`IsAdmin`-only); eligibility is editable only through the Django admin site by a superuser.
