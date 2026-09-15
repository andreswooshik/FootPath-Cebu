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
| Identity | Firebase Authentication (email/password, backend-provisioned identities) |
| Token verification | Firebase Admin SDK on the Django backend (ID token check per request) |
| Database | SQLite for local/tests; PostgreSQL configuration for deployment |
| Push notifications | Persistent Django inbox + Firebase Cloud Messaging |

Firebase is used for **identity only**. Roles, permissions, and all domain data
live in the Django database, keyed to the Firebase UID.

## Account and Club Hierarchy

The approved hierarchy is:

```text
SUPER ADMIN → CLUB → CLUB COORDINATOR → COACH / PLAYER / GUARDIAN
```

See [Account and Club Hierarchy](ACCOUNT-AND-CLUB-HIERARCHY.md) for the
authoritative provisioning and club-type policy.

- Role-based access control (RBAC) across all roles.
- Super Admin creates/manages Clubs, chooses `SCHOOL` or `INDEPENDENT`, and
  provisions the single Coordinator assigned to each Club.
- The Club Coordinator is the normal and trusted creator of Coach, Player, and
  Guardian accounts in their own Club.
- A prospective Coordinator may submit a public Club application. Django
  provisions its Firebase identity disabled, and Super Admin approval enables
  portal and mobile access together. A Firebase account alone grants no access;
  the backend rejects any UID it has not provisioned and activated.
- Firebase-authenticated login for mobile roles (Coordinator, Coach, Player,
  Guardian); Coordinators also use Django session login in the web portal.

## Age Tiers

Three age tiers, configurable by Admin:

| Tier | Ages |
|---|---|
| Foundation | 10–12 |
| Development | 13–15 |
| Pathway | 16–18 |

## Functional Requirements by Role

### Super Admin
- Create, classify, activate, and deactivate Clubs.
- Provision and manage the single Club Coordinator assigned to each Club.
- Configure platform-wide age-tier settings.
- Review platform-level configuration. Super Admin is not the normal creator
  of Player, Coach, or Guardian accounts.

### Club Coordinator
- Provision Coach, Player, and Guardian accounts only in their own active Club.
- Create Guardian links only between same-Club Guardians and Players.
- For a School Club, update a player's eligibility status (**Eligible, Not
  Eligible, Pending, Academic Warning**) without entering or exposing grades.

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
- Injury history (CRUD).
- View current academic eligibility status (**status only, no grades**).

### Guardian
- Log in with own credentials, linked to one or more player profiles.
- Read-only view of child's profile, attendance, performance ratings, and
  schedule.
- View child's academic eligibility status (status only).

## Cross-Cutting Requirements

- **Eligibility privacy:** eligibility gating is driven by status flags only —
  FootPath Cebu never stores raw student grades, GPA, subject grades, report
  cards, transcripts, or grade uploads.
- **Club types:** School Clubs enable Coordinator-managed, status-only academic
  eligibility. Independent Clubs receive Not Applicable behavior while all
  unrelated football functionality remains available.
- **Offline-first access:** successful authenticated reads are cached per
  Firebase user for connection-only fallback; offline-captured attendance
  batches sync automatically once connectivity returns.
- **Push notifications:** Django stores an authorized inbox record and delivers
  neutral FCM alerts; Players and Guardians receive schedule, feedback, and
  eligibility updates with foreground handling and tap routing.
- **Dispute and audit log foundation:** Coach can flag/respond, Coordinator can
  participate, and Admin reviews. All sensitive changes are auditable.

## Out of Scope for This Milestone (remaining 50%)

Everything not listed above, including (non-exhaustive): match management and
match statistics, advanced analytics/reporting, payments/fees,
messaging/chat, operating a verified live production environment, and public
self-registration for member account roles.

## Development Schedule Anchor

- **Day 1:** Django project setup; Firebase-authenticated login verification
  (Admin SDK token check) for all roles. ✅ (this commit)
