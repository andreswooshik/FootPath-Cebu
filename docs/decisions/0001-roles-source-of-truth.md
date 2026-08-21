# ADR 0001 — Roles live in Django, not Firebase custom claims

**Status:** Accepted · **Date:** 2026-07-10

## Context

The original blueprint (2-Week Execution Plan) assumes a pure Firebase stack:
roles are stored as **Firebase custom claims** and enforced by **Firestore
Security Rules** (`request.auth.token.role`). This project instead uses a
**Django REST backend** with its own database for application data.

We had to decide where a user's role (SUPER ADMIN / CLUB COORDINATOR / COACH /
PLAYER / SCHOOL STAFF / GUARDIAN) is stored and enforced.

## Decision

**Django is the single source of truth for roles and authorization.**

- Role is a field on the Django user model: `User.role` (`accounts/models.py`).
- Firebase is used **only for authentication** — verifying the caller's
  identity. `FirebaseAuthentication` validates the Firebase ID token and maps
  the `uid` to a provisioned Django user (`accounts/authentication.py`).
- Authorization is enforced by DRF permission classes built from the role:
  `role_required(...)` → `IsAdmin`, `IsCoach`, etc. (`accounts/permissions.py`).
- A valid Firebase token with **no** provisioned Django account is rejected.
  Super Admin creates Clubs and their Coordinators; each Coordinator normally
  provisions members only inside their own active Club.

## Consequences

**Positive**
- One authorization system to reason about (Django), not two.
- No client can self-assign a role or Club; both are established through the
  server-side hierarchy.
- Testable in CI without Firebase — see `accounts/tests.py` (Firebase
  verification is mocked; role enforcement is asserted per role).

**Trade-offs**
- The Flutter client learns its role from `GET /api/auth/me/` after login,
  **not** from the ID token. Frontend role checks are UX-only; the backend is
  authoritative.
- If we later adopt Firestore for any data, its Security Rules cannot rely on a
  `role` claim — that data path would need the Django API in front of it, or we
  would additionally mirror the role into a custom claim.

## Verification

`python manage.py test accounts` asserts:
- every `admin/*` endpoint rejects non-admin roles and accepts Super Admin;
- `auth/me/` requires authentication and returns the caller's role;
- a verified token maps to the right provisioned user;
- a verified token with no local account is rejected;
- Coordinators cannot provision across Clubs or create privileged roles.
