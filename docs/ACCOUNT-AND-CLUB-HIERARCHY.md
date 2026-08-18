# Account and Club Hierarchy

This document is the authoritative account-provisioning policy for FootPath
Cebu.

```text
SUPER ADMIN
    ↓ creates and manages
CLUB (SCHOOL or INDEPENDENT)
    ↓ owns exactly one
CLUB COORDINATOR
    ↓ provisions only inside that club
COACH / PLAYER / GUARDIAN / SCHOOL STAFF
```

`ADMIN` is the backward-compatible database/wire value for the product role
named **Super Admin**. A Super Admin creates a Club, selects its type, assigns
the Club's single Coordinator, and controls Club/Coordinator activation.

A Club Coordinator belongs to exactly one active Club. Normal member account
provisioning belongs to that Coordinator—not to Super Admin. The backend always
derives the tenant from `request.user.club`; a submitted `club_id` cannot move
the new account into another Club.

Players are created through one transactional service. A successful player
provisioning operation always creates:

- a `User` with role `PLAYER` and the Coordinator's non-null Club;
- exactly one `PlayerProfile`; and
- an optional same-Club `GuardianLink`.

Coach, Player, Guardian, and School Staff roles have no account-provisioning
permission. A Coordinator cannot create another Coordinator or manage Clubs.

## Club types

The existing `Club.is_school_affiliated` field remains the single stored source
of truth; the API exposes it as `SCHOOL` or `INDEPENDENT`. No redundant club-type
column was introduced.

```text
CLUB
├── SCHOOL
│   ├── School Staff accounts allowed
│   └── academic eligibility status enabled
└── INDEPENDENT
    ├── School Staff creation rejected
    └── academic eligibility = Not Applicable
```

Independent Clubs retain all unrelated football functionality.

## Academic-data boundary

FootPath Cebu never stores raw student grades. It does not store GPA, subject
grades, report cards, transcripts, or grade uploads. For School Clubs, academic
data is limited to these four status values and their status-change history:

- Eligible
- Not Eligible
- Pending
- Academic Warning

Not Applicable is an applicability response for an Independent Club; it is not
a fifth stored eligibility status.

## Enforcement points

- Super Admin Club API: `POST /api/admin/clubs/`
- Super Admin Coordinator API: `POST /api/admin/coordinators/`
- Super Admin Club lifecycle API: `PATCH /api/admin/clubs/<id>/`
- Coordinator portal account flow: `/portal/accounts/new/`
- Player invariant service: `accounts.services.provision_player`
- Same-Club guardian-link service: `portal.services.link_guardian`
- Independent-Club eligibility response: `applicable: false`, empty history

The 24 adviser-requested regression cases are implemented one-for-one in
`backend/accounts/test_club_hierarchy.py`.
