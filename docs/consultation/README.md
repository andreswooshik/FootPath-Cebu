# Role and Permission Management Consultation

## Purpose

This document records a requirement that needs confirmation before further development:

> When the requirements say **“Admin: assign and manage role-based permissions,”** does this mean assigning users to fixed roles, or customizing individual permissions for each user?

The answer affects the database design, Admin interface, security rules, testing scope, and project schedule.

## Current System

FootPath Cebu currently uses **fixed role-based access control**. A user receives a predefined role, and the application code determines what that role can do.

The implemented roles are:

| Role | Current responsibility |
|---|---|
| Super Admin | Manages clubs, accounts, selected role changes, account status, age tiers, audits, and system records |
| Club Coordinator | Provisions and manages members belonging to one club |
| Coach | Manages schedules, attendance, assessments, match statistics, and disputes for the same club |
| Player | Views personal records and manages their own injury history |
| School Staff | Updates and reviews status-only academic eligibility for players in the same School Club |
| Guardian | Views permitted records for linked players, subject to the privacy gate |

The Admin can assign predefined roles and activate or deactivate accounts. The Admin cannot create new role types or customize individual permissions through checkboxes.

## Option A: Fixed Roles

Under this option, every role keeps one standard set of permissions.

Examples:

- Every Coach can manage schedules and attendance for their own club.
- Every School Staff account can manage eligibility for its School Club.
- Every Guardian can only read records for linked players.
- An Admin changes access by assigning a different supported role or deactivating the account.

Suggested requirement wording:

> **Admin: assign users to predefined roles and manage account access.**

### Advantages

- Matches the current implementation.
- Easier to explain, test, and defend.
- Lower risk of accidental permission combinations.
- Requires less development and administrative training.

### Limitations

- Two users with the same role cannot have different permissions.
- A new responsibility, such as Assistant Coach, requires a code and database change.
- The Admin cannot enable or disable individual actions for one user.

## Option B: Configurable Permissions

Under this option, the Admin can customize what an individual user or role may do.

Examples:

- Coach A may record attendance, while Coach B may only view it.
- One School Staff member may update eligibility, while another may only view history.
- An Assistant Coach role could be created with limited access.
- The Admin could enable permissions using controls such as “View players,” “Manage attendance,” or “Update eligibility.”

Suggested requirement wording:

> **Admin: configure roles and assign individual permissions to user accounts.**

### Advantages

- More flexible for larger organizations.
- Supports specialized staff responsibilities.
- Reduces the need to create code for every small role variation.

### Limitations

- Not currently implemented.
- Requires new permission models, Admin screens, authorization checks, audit events, and tests.
- Incorrect configurations could expose private player information or block required work.
- Increases project scope and maintenance complexity.

## Comparison

| Decision area | Option A: Fixed roles | Option B: Configurable permissions |
|---|---|---|
| Current implementation | Already implemented | New development required |
| Administration | Simple role assignment | Role and permission configuration |
| Security risk | Lower and easier to audit | Higher if permissions are misconfigured |
| Flexibility | Limited | High |
| Testing effort | Moderate | High; every permission combination needs coverage |
| Recommended for current capstone scope | Yes | Only if explicitly required |

## Incomplete or Unresolved Items for Project Planning

The following items should be discussed before the next development plan is approved. This list is based on the current implementation, not the superseded historical audit documents.

### A. Decisions Required Before Development

| ID | Item | Current situation | What must be decided |
|---|---|---|---|
| D1 | Meaning of “manage permissions” | Fixed roles, selected role changes, and account activation/deactivation are implemented. Individual permission switches are not implemented. | Approve fixed-role management or request configurable per-user permissions. |
| D2 | Official number of roles | The requirement says five roles, but the system has six: Super Admin, Club Coordinator, Coach, Player, School Staff, and Guardian. | Approve Club Coordinator as the sixth role or remove/merge that responsibility. |
| D3 | Who may create accounts | The requirement says account creation is restricted to Admin. The implemented hierarchy lets the Super Admin create the Club Coordinator, while the Coordinator provisions users within their own Club. | Approve the delegated Coordinator model or require all accounts to be created by Super Admin. |
| D4 | Authentication method for every role | Coach, Player, and Guardian use Firebase. Super Admin uses the Firebase-backed console. Club Coordinator and School Staff use Django web-session credentials. | Approve mixed authentication by interface or require Firebase authentication literally for all six roles. |
| D5 | Meaning of “performance trends” | Match-statistic trends and squad attendance/effort progress are implemented. Historical snapshots of the Player's editable profile attributes are not stored; a new assessment replaces the previous values. | Confirm whether current trends are enough or whether assessment-history charts are required. |

### B. Implementation or Verification Still Incomplete

| Priority | Item | What exists now | Remaining work |
|---|---|---|---|
| High if selected | Configurable individual permissions | Fixed server-enforced roles are implemented. | Only required if consultation selects Option B: add permission data, Admin controls, enforcement, audit events, migrations, and security tests. |
| Medium | Live push-notification proof | Notification records, read state, device tokens, FCM sending, foreground handling, and navigation are implemented and locally tested. | Demonstrate and record delivery on supported physical devices with the real Firebase/APNs configuration. |
| Medium if required | Historical assessment trends | Current profile ratings and notes are saved, while match trends are historical. | Add append-only assessment snapshots, an API, charts, and migration/tests only if D5 requires this meaning of performance trends. |

### C. Recently Completed and Not Part of the Remaining Plan

The following should not be listed as unfinished:

- Coach creation and management of match records and Player match statistics.
- Player access to their own match-performance statistics and trends.
- Read-only match-statistics access for a Guardian who is linked to the Player and passes the existing privacy gate.
- Admin-configurable age-tier settings and the three default age tiers.
- Attendance offline queueing and automatic replay.
- Eligibility status/history without storing grades.
- General audit logging and Admin dispute review.
- School Staff dispute list, thread view, responses, and status changes in the session-authenticated portal.

### Suggested Planning Order

1. Resolve D1–D5 during consultation and record the approved wording.
2. Implement only the optional features selected during consultation.
3. Run the full automated regression suites.
4. Perform and record the physical-device notification test.
5. Update the requirements, user manual, diagrams, and defense documents so they all describe the approved behavior.

## Questions for Consultation

The adviser, client, or project owner should answer the following:

1. Should FootPath Cebu keep fixed roles, or allow configurable permissions?
2. Is **Club Coordinator** an official sixth role, or should the system contain only the five listed roles?
3. Should only the Super Admin create accounts, or may Club Coordinators continue creating accounts for their own club?
4. Should an Admin only assign roles, or also turn individual permissions on and off?
5. Do users with the same role ever need different access?
6. Is an additional role such as Assistant Coach required?
7. Which role changes should be allowed after an account is created?
8. If configurable permissions are required, which exact permissions must appear in the first version?

## Recommended Decision for the Current Scope

Unless the stakeholder explicitly requires per-user customization, retain **Option A: Fixed Roles** and approve this wording:

> The Super Admin assigns users to predefined roles and manages account access. Each role has server-enforced permissions, and club-scoped roles can access only records belonging to their authorized club or linked players.

This statement accurately describes the implemented system while preserving role and club security.

## Impact if Option B Is Selected

Selecting configurable permissions requires a new implementation plan covering at least:

- A permission catalogue with stable permission codes.
- Role-to-permission and optional user-to-permission database relationships.
- A secure Admin permission-management interface.
- Server-side permission checks for every protected endpoint and portal action.
- Rules for resolving role defaults, explicit grants, and explicit denials.
- Audit logs for every permission change.
- Protection against removing the final administrator’s access.
- Migration of existing accounts to safe default permissions.
- Backend, Flutter, portal, and security regression tests.
- Updated requirements, diagrams, manuals, and defense documentation.

No configurable-permission development should begin until the exact permission list and conflict rules are approved.

## Consultation Record

| Field | Record |
|---|---|
| Consultation date | ______________________________ |
| Adviser/client | ______________________________ |
| Participants | ______________________________ |
| Selected approach | ☐ Option A: Fixed roles  ☐ Option B: Configurable permissions |
| Official number of roles | ______________________________ |
| Authorized account creators | ______________________________ |
| Approved requirement wording | ______________________________ |
| Required follow-up changes | ______________________________ |
| Target completion date | ______________________________ |

## Approval

| Name and role | Signature | Date |
|---|---|---|
|  |  |  |
|  |  |  |

## Notes

Use this section during the meeting to record explanations, objections, and final instructions.

________________________________________________________________________________
________________________________________________________________________________

________________________________________________________________________________
