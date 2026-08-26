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
