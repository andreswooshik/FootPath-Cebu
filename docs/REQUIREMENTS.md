# FootPath-Cebu — Requirements (50% Capstone Defense Milestone)

FootPath-Cebu is a youth football academy management system for Cebu. It manages
player development across three age tiers with role-based access for academy
staff, players, and their guardians.

This document captures the scope committed for the **50% capstone defense**.
Anything not listed here belongs to the remaining 50% and is out of scope for
this milestone.

## Architecture

| Layer | Technology |
|---|---|
| Mobile/web app | Flutter (`footpath_cebu/`) |
| Backend API | Django + Django REST Framework (`backend/`) |
| Identity | Firebase Authentication (email/password, Admin-issued credentials only) |
| Token verification | Firebase Admin SDK on the Django backend (ID token check per request) |
| Database (dev) | SQLite (PostgreSQL planned for production) |
| Push notifications | Firebase Cloud Messaging (foundation) |

Firebase is used for **identity only**. Roles, permissions, and all domain data
live in the Django database, keyed to the Firebase UID.

## Roles

Five core roles: **Admin, Coach, Player, School Staff, Guardian** — plus
**Club Coordinator**, added with multi-club support: a coordinator owns one
club and provisions every account in it through the web portal.

- Role-based access control (RBAC) across all roles.
- Account creation for end users (Coach, Player, School Staff, Guardian) is
  **restricted to Admin and the club's Coordinator** — there is no public
  self-registration for these roles. A Firebase account alone grants no
  access; the backend rejects any UID it has not provisioned.
- **Club registration is the one public signup** (decision, July 23 2026):
  a coordinator registers their club through the portal, the account stays
  inactive until a superadmin approves it, and all other accounts in that
  club are then provisioned by the coordinator.
- Firebase-authenticated login for app roles (Coach, Player, Guardian) using
  issued credentials; Coordinators and School Staff are web-portal users with
  Django session login.

## Age Tiers

Three age tiers, configurable by Admin:

| Tier | Ages |
|---|---|
| Foundation | 10–12 |
| Development | 13–15 |
| Pathway | 16–18 |

## Functional Requirements by Role

### Admin
- Provision user accounts for all roles, including linked Guardian accounts.
- Assign and manage role-based permissions.
- Configure age-tier settings.

### Coach
- Create and manage training schedules.
- Record attendance (**Present, Absent, Excused**) with **offline-first**
  support — capture works without connectivity and syncs automatically once
  connectivity returns.
- Rate player performance on the standardized **1–10 rubric**, position-aware
  with goalkeeper variants.
- Record qualitative feedback on players.
- View player profiles and performance trends.

### Player
- View own profile (position, age tier, attributes).
- View training schedule and attendance record.
- View coach feedback and ratings.
- View match performance statistics.
- Injury history (CRUD).
- View current academic eligibility status (**status only, no grades**).

### School Staff
- Update a player's eligibility status (**Eligible, Not Eligible, Pending,
  Academic Warning**) without entering or exposing grades.
- View the eligibility status history of linked players.

### Guardian
- Log in with own credentials, linked to one or more player profiles.
- Read-only view of child's profile, attendance, performance ratings, and
  schedule.
- View child's academic eligibility status (status only).

## Cross-Cutting Requirements

- **Eligibility privacy:** eligibility gating is driven by status flags only —
  raw grades are never stored or exposed anywhere in the system.
- **Offline-first sync:** offline-captured records (attendance) sync
  automatically once connectivity returns.
- **Push notifications:** the system delivers push notifications; Players and
  Guardians receive them for schedule, feedback, and eligibility updates.
- **Dispute and audit log foundation:** Coach can flag/respond, School Staff
  participate, Admin reviews. All sensitive changes are auditable.

## Out of Scope for This Milestone (remaining 50%)

Everything not listed above, including (non-exhaustive): match management
beyond viewing statistics, advanced analytics/reporting, payments/fees,
messaging/chat, production deployment hardening (HTTPS, PostgreSQL), and
self-registration for Coach/Player/School Staff/Guardian accounts
(permanently out of scope by design — the approval-gated club registration
signup is the sanctioned exception).

## Development Schedule Anchor

- **Day 1:** Django project setup; Firebase-authenticated login verification
  (Admin SDK token check) for all roles. ✅ (this commit)
