# FootPath Cebu — Project Overview

## Approved hierarchy

```text
SUPER ADMIN → CLUB → CLUB COORDINATOR → COACH / PLAYER / GUARDIAN / SCHOOL STAFF
```

Clubs are classified as School (status-only academic eligibility enabled) or
Independent (academic eligibility Not Applicable). FootPath Cebu never stores
raw student grades.

## One-sentence defense

FootPath Cebu is a role-based youth football academy management system that centralizes player development ratings, training schedules and attendance, eligibility, injuries, guardian access, disputes, and club account administration across a Flutter mobile app and Django web/API backend.

## 30-second explanation

> FootPath Cebu is a role-based system for a youth football academy. Coaches use Flutter to manage players, sessions, attendance, and development ratings; players and guardians view permitted records; coordinators and school staff use a Django portal; and administrators govern the platform. Firebase proves mobile identity, while Django enforces roles and clubs and stores the data. Its strongest advanced features are controlled guardian PIN access and offline attendance queueing.

## One-minute explanation

> Youth academies can fragment player ratings, attendance, schedules, injury notes, and eligibility decisions across paper or separate files. FootPath Cebu centralizes those records and gives six roles only the operations they need. Coaches manage development and training in Flutter. Players see their own records and confirm sessions. Linked guardians unlock a child’s private information with an additional household PIN. Coordinators provision club accounts, school staff maintain eligibility, and administrators manage the system through Django.
>
> The mobile app uses Riverpod and domain/repository layers. Firebase handles identity and push; Django REST verifies every token, enforces role, club, ownership, and family links, and persists through the ORM. Attendance writes can be queued locally during network failure, and safe authenticated GET responses have a Firebase-user-scoped cache. Notifications are stored in a current-user inbox, shown through unread bells, and handled while the app is foregrounded or opened from a push. Coaches also record same-club match results and per-player statistics, which players view as summaries, history, and rating trends. AI and scouting are not current features.

## Three-minute technical explanation

> The Flutter app starts in `main.dart`, initializes Firebase, enters a Riverpod `ProviderScope`, and shows `SessionBootstrapScreen`. A restored Firebase user still must call Django `/api/auth/me/`; Django verifies the ID token with revocation checking, maps its UID to an active local `User`, requires a club for non-admin roles, and returns the authoritative role. `HomeScreen` then selects the coach, player, or guardian mobile portal. Coordinator and school-staff operations use Django’s session-authenticated portal, and administrators use Django admin/protected APIs.
>
> Flutter is divided into presentation screens/providers, domain entities/use cases/repository contracts, and concrete data adapters. `core/di/providers.dart` composes mock or live implementations. Live repositories use a shared authenticated client for Firebase Bearer tokens, timeouts, typed errors, and owner-scoped safe-GET caching, then convert JSON with factories such as `Player.fromJson`. Django URL views apply role and object checks, serializers validate payloads, services handle cross-system work, and models persist relational data. SQLite is the default/test database; environment settings can select PostgreSQL, including Supabase-hosted PostgreSQL. Supabase Storage is optional for private player photos and is called through Django, so Supabase Auth and RLS are not part of the design.
>
> A representative coach write is assessment saving: the editor calls a Riverpod controller, `SavePlayerAssessment`, and `ApiPlayerRepository`; Django checks coach and same-club access, validates twelve ratings in the implemented 0–99 scale, updates `PlayerProfile`, audits, schedules FCM after commit, and returns the updated player for provider refresh. Attendance adds resilience: a complete batch is atomically upserted/pruned on Django, but a transport failure stores it in a Firebase-user-scoped sqflite outbox and replays it oldest first.
>
> Security is server-authoritative. Firebase proves identity; Django decides role, tenant, ownership, and guardian links. Guardian detail adds a hashed 4–6 digit PIN, five-attempt lockout, and a ten-minute signed user/player unlock token. Player provisioning now enforces the Player/Club/PlayerProfile aggregate across admin, portal, API, and seed paths. Match ownership and participating players are also enforced against the authenticated Coach's club. The project does not currently contain AI, scouting, grades, chat, or maps.

## Repository technical inventory

| Category | Verified implementation |
|---|---|
| Languages | Dart, Python, HTML, CSS, JavaScript, platform configuration files |
| Frontend | Flutter with Material widgets |
| State/DI | Riverpod 3 (`ProviderScope`, `FutureProvider`, `Notifier`, `AsyncNotifier`) |
| Mobile architecture | presentation → domain use cases/contracts ← concrete data adapters |
| Backend | Django 5.2 and Django REST Framework 3.16 |
| Authentication | Firebase Auth for mobile; Django sessions for portal/admin |
| Authorization | Django role, club, object/ownership, GuardianLink, and PIN-unlock checks |
| Main database | Django ORM; SQLite default/test or configured PostgreSQL/Supabase host |
| Mobile local storage | Firebase-user-scoped sqflite attendance outbox and authenticated GET cache |
| Object storage | optional private Supabase Storage through Django |
| External services | Firebase Auth/Admin/FCM; optional Supabase database/storage infrastructure |
| Key Flutter packages | `firebase_core`, `firebase_auth`, `firebase_messaging`, `http`, `flutter_riverpod`, `sqflite`, `connectivity_plus`, `image_picker`, `flutter_svg`, `google_fonts`, `flutter_animate` |
| Key backend packages | Django, Jazzmin, DRF, Firebase Admin, CORS Headers, Axes, Argon2, python-dotenv, httpx, psycopg, Gunicorn, WhiteNoise, Redis, Sentry SDK |
| Platform configuration | Android/iOS/macOS/web/desktop Flutter scaffolding; Firebase client configuration is present for supported app platforms |
| AI/ML | not found |
| Testing | 2026-08-21 local verification: Flutter analyze clean, Flutter 240/240, Django 241/241; GitHub Actions CI configured |
| Major backend apps | `accounts`, `academy`, `portal`, `console`, `config` |
| Current status | core academy, notification-inbox, resilient-networking, and authorized-photo workflows implemented; production artifacts exist but operational evidence remains unverified; AI/scouting and listed absent features not found |

## What was actually inspected

This reviewer is based on the executable repository, not only on planning documents. The inspected implementation contains:

- a Flutter client in `footpath_cebu/lib/`;
- a Django 5.2 + Django REST Framework backend in `backend/`;
- Firebase Authentication and Firebase Cloud Messaging integration;
- Django ORM persistence using SQLite by default or PostgreSQL when configured;
- optional Supabase-hosted PostgreSQL and private Supabase Storage, both accessed by Django rather than directly by Flutter;
- a Django session-authenticated coordinator/school-staff portal and Django admin console;
- an offline attendance outbox and owner-scoped authenticated GET cache in the mobile app using SQLite (`sqflite`);
- a persistent notification inbox with unread state, foreground handling, and role-aware push-open navigation;
- container, readiness, observability hooks, and backup/restore runbooks for production operations;
- automated Django and Flutter tests plus GitHub Actions CI.

The repository inventory includes Python backend code, Dart mobile code, Django templates/static assets, automated tests, CI, container manifests, and operations scripts. Counts change as hardening work is added, so the defense should rely on current test output and source paths rather than an older snapshot count.

## Problem addressed

The implemented system addresses fragmented academy operations. Without a shared system, coaches may keep ratings, attendance, schedules, injury notes, and player concerns in different records; guardians have limited controlled visibility; and eligibility decisions can lack a traceable history. FootPath Cebu gives each authorized role a constrained view of the same club-managed records.

## Intended users and actual access channel

| Role | Main access channel | Implemented responsibilities |
|---|---|---|
| Super Admin (`ADMIN`) | Django admin and admin API | Create/classify Clubs, assign the single Coordinator, control lifecycle, inspect platform data |
| Club Coordinator | Django web portal | Maintain one club; normally create Coach/Player/Guardian and School Staff only for a School Club |
| Coach | Flutter mobile app | View squad, schedule sessions, record attendance and match statistics, assess performance, view trends/injuries, raise disputes |
| Player | Flutter mobile app | View own profile, development and match statistics, attendance, eligibility, injuries, and confirm today's session |
| Guardian | Flutter mobile app | Select a linked player and, after a player privacy PIN unlock, view permitted player information |
| School Staff | Django web portal | Review and change player eligibility for the same club; participate in dispute handling through authorized backend flows |

`ADMIN`, `COORDINATOR`, and `SCHOOL_STAFF` are present in the backend role enum. The mobile `HomeScreen` has dedicated destinations only for `COACH`, `PLAYER`, and `GUARDIAN`; the other roles receive a generic signed-in placeholder if they authenticate in the app. Their intended interfaces are the admin or web portal.

## Major implemented modules

1. Authentication and session restoration through Firebase ID tokens verified by Django.
2. Server-side account provisioning with Firebase/relational-record compensation.
3. Club-scoped roster and guardian-player links.
4. Player performance profile with twelve 0–99 ratings, position, notes, and aggregate progress.
5. Training-session create, update, list, and cancellation.
6. Attendance and per-session effort/note recording, including an offline mobile write queue.
7. Player session confirmation for sessions occurring today.
8. Eligibility changes with history and audit records.
9. Player-reported injury CRUD and authorized read access.
10. Dispute creation and append-only response/status history.
11. Player household privacy PIN with hashing, throttling, temporary signed unlock tokens, and guardian access headers.
12. Device-token lifecycle, persistent notification inbox/read state, selected FCM fan-out, foreground display, and role-aware push-open routing.
13. Private player-photo upload through Django from authorized web/admin and same-Club Coach mobile workflows, when Supabase credentials are configured.
14. Club-owned completed matches with per-player statistics, summaries, history, and coach-rating trends.
15. Coordinator and school-staff web workflows.

## Formal objectives: repository finding

No authoritative section explicitly titled **General Objective** and **Specific Objectives** was found in the inspected source or current requirements. The following are therefore defensible objectives derived from `docs/REQUIREMENTS.md` and implemented workflows; they must be described as reconstructed objectives, not quoted approved wording.

### Reconstructed general objective

To design and implement a secure, role-based academy information system that centralizes youth football player development and training operations while giving coaches, players, guardians, coordinators, school staff, and administrators access appropriate to their responsibilities.

### Reconstructed specific objectives

1. Digitize player profiles, position assignments, performance ratings, notes, and aggregate progress.
2. Allow coaches to schedule sessions and maintain club-scoped attendance with per-session effort feedback.
3. Give players and linked guardians controlled visibility into player development, attendance, eligibility, and injury information.
4. Record eligibility changes and disputes in traceable histories with actor and timestamp evidence.
5. Maintain role and club isolation using server-side authentication, authorization, object checks, and relational constraints.
6. Improve field reliability by queueing attendance writes during temporary network failures and synchronizing them later.
7. Give Coaches a historical match-performance workflow and Players a read-only view of their own statistics and trends.
8. Centralize club account provisioning while preventing public creation of active academy accounts.

## Objective-to-implementation mapping

| Objective | Feature | Code/module | Database/data | Evidence of achievement |
|---|---|---|---|---|
| Centralize player development | Current ratings, position, notes, roster | Flutter player repositories/editors; `PlayerAssessmentView`, `PlayerPositionView` | `academy_playerprofile` | Same-club coach can read/update and receive serialized player |
| Digitize training operations | Schedule CRUD, RSVP, attendance | training/attendance/confirmation repositories and views | `academy_trainingsession`, `academy_attendance`, `academy_sessionconfirmation` | API persists unique player/session records and returns refreshed UI data |
| Provide controlled family access | Linked-player selector and PIN unlock | guardian providers, `pin_service.py`, `player_unlock.py` | `accounts_guardianlink`, `academy_playerprivacypin` | Redacted pre-unlock list; guarded detail requires signed user/player token |
| Preserve accountability | Eligibility history, disputes, audit | `academy/signals.py`, dispute views, `AuditLog` calls | eligibility history, disputes/responses, audit table | Actor/time/status records are created by verified workflows |
| Enforce role/club isolation | Firebase-to-Django auth and endpoint checks | `accounts/authentication.py`, `permissions.py`, `academy/views.py` | `accounts_user.role/club_id`, related FKs | Server rejects wrong role/cross-club/unauthorized object requests |
| Improve field reliability | Offline attendance queue and safe-read cache | offline decorator, outbox, sync service, shared authenticated client, GET cache | mobile owner-scoped SQLite data then backend APIs | Transport-failed attendance batches replay; eligible GETs use scoped cache only for network failures, never HTTP errors |
| Track match performance | Coach match/performance entry and Player trend views | match use cases/repositories/screens; match API views | `academy_footballmatch`, `academy_playermatchperformance` | Same-club Coaches write bounded statistics; Players read only their own history and trends |
| Centralize trusted provisioning | Coordinator/admin account workflows | `accounts/services.py`, `portal/services.py` | users, profiles, guardian links, Firebase identity | Coordinator path creates linked domain records with Firebase compensation |

## Scope boundary

### In scope and implemented

- one Django deployment supporting multiple clubs through `User.club` and `TrainingSession.club`;
- six roles, with three mobile portals and web/admin access for operational roles;
- current player development ratings and coach notes;
- schedules, confirmations, attendance, effort, and notes;
- injury history, eligibility history, disputes, and audit entries;
- Firebase identity, token verification, password reset/change, and FCM sending;
- persistent notification inbox/read state, foreground handling, unread bells, and role-aware push-open routing;
- private photo storage through the server, including same-Club Coach mobile upload when Supabase is configured;
- local mock repositories for UI/demo development and real API repositories for live operation.

### Implemented with explicit boundaries

- **Notifications:** authenticated inbox/read-state APIs, current-user persistence, device-token lifecycle, FCM fan-out, foreground feedback, unread bells, and role-aware routing are implemented. Session events open the schedule; assessment/eligibility events open the authorized Player/Guardian destination behind existing privacy gates; unknown events fall back to the focused inbox. Actual remote delivery still depends on valid Firebase/APNs configuration and should be demonstrated on a supported device.
- **Player photos:** coordinator/admin and same-Club Coach mobile upload paths validate files and send them through Django. Storage succeeds only when the deployment has valid Supabase Storage credentials; mobile display retains an avatar fallback.
- **Academic eligibility:** School Clubs store only one of four eligibility statuses and its history. Independent Clubs receive Not Applicable. FootPath Cebu never stores raw student grades.

### Operationally unverified

- **Production deployment:** Docker/Compose, Gunicorn/WhiteNoise, health/readiness checks, optional Sentry hooks, CI validation, backup/restore scripts, and an operations runbook now exist. The repository does not prove an active live deployment, monitor/alert execution, scheduled backups, or a completed restore drill.

### Not found in executable source

- artificial intelligence, machine learning, recommendations, prediction, or computer vision;
- scout accounts, scouting workflows, scouting reports, or external club recruitment access;
- match statistics or match-event tracking;
- chat or real-time messaging;
- maps, GPS, route tracking, or the meaning suggested by the project name “FootPath”;
- a mobile public registration screen;
- a historical table of performance-assessment versions;
- Supabase Auth or row-level security policies;
- formal approved objective statements.

## Documentation alignment note

The root `README.md` now matches the implemented architecture: Firebase supplies identity and push, while Django is the authorization and relational-data source of truth. Supabase, when configured, is a PostgreSQL host and private object store. The approved requirements still contain a rating-scale mismatch documented elsewhere in this reviewer; do not silently rewrite that approved wording.

## Core value proposition

The project’s strongest defensible contribution is not an AI feature. It is the integration of role-scoped academy workflows with a deliberate security model: trusted identity from Firebase, authorization and tenancy in Django, relational history/audit records, household PIN protection for guardian access, resilient attendance writes and safe cached reads, plus a persistent notification channel.

## Short opening statement for the panel

> FootPath Cebu centralizes the recurring work of a youth football academy. Coaches manage sessions, attendance, and player development in Flutter; players and guardians receive controlled views; coordinators and school staff use a Django portal; and administrators govern the system. Firebase establishes identity, but Django makes every authorization and data decision. The current implementation emphasizes role isolation, traceability, and resilient attendance entry rather than AI or scouting features.
