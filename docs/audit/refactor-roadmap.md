# FootPath-Cebu — Refactor Roadmap

Prioritized action items from the [audit report](audit-report.md). Effort key:
✅ quick fix (<1h) · 🔄 refactor (1–8h) · 🏗️ architectural (1–3d).

---

## Ship-blockers — do before ANY production/release build

| # | Item | Effort | Why it blocks |
|---|---|---|---|
| F1 | Gate `initMock()` vs `initFirebase()` on `kReleaseMode` | ✅ <1h | A release build today authenticates anyone with `demo123` and self-assigns ADMIN. This is the single most dangerous line in the repo. |
| F2 | Build the missing DRF endpoints (`/api/players/…`, `/api/attendance/`, `/api/training-sessions/`) **or** keep the app explicitly on mocks | 🏗️ 1–3d | "Live mode" 404s on every screen. Nothing real works until these exist. |
| F3 | Object-level authorization on those endpoints (guardian↔player link check, coach↔squad scope) | 🔄 built with F2 | Without it, the endpoints are BOLA (any guardian reads any child). Design it in from the start. |
| F5 | Gate `CORS_ALLOW_ALL_ORIGINS` behind `DEBUG` | ✅ <1h | Wildcard CORS in prod. |
| F6 | Add `if not DEBUG:` HTTPS/HSTS/secure-cookie block; pass `manage.py check --deploy` | ✅ <1h | Admin/console session cookies over plaintext otherwise. |

> **Note:** the app is currently a functioning **front-end prototype on mock data**. That
> is fine for a capstone demo. "Production" here means the moment you flip to the real
> backend — F1–F6 must land in the same change.

---

## Before capstone submission — correctness & polish

| # | Item | Effort | Notes |
|---|---|---|---|
| F4 | Enable `check_revoked=True` on write/admin routes | ✅ <1h | Makes logout/disable actually cut off access. Keep off for cheap reads if you want. |
| F9 | Console: replace `innerHTML` with `textContent`/`createElement` | 🔄 1–2h | Latent stored XSS via free-text name fields. |
| F11 | Delete unused `_VerifiedFacilityCard` | ✅ <15m | Clears the only analyzer warning. |
| — | Add a CI workflow (`flutter test` + `flutter analyze` + `manage.py test` + `check --deploy`) | 🔄 2–3h | No `.github/workflows` exists. Cheap safety net for a graded project. |
| — | Resolve the `EditPerformanceData` TODO — persist assessments once a write endpoint exists | 🔄 with F2 | Currently in-memory only (documented at `edit_performance_data_screen.dart:15`). |

---

## Post-launch / deferrable

| # | Item | Effort | Notes |
|---|---|---|---|
| F7 | Explicit `adopt_existing` confirmation before linking a pre-existing Firebase account | 🔄 1–2h | Admin-only path; low risk today. |
| F8 | DRF pagination on admin lists (+ console pagination UI) | 🔄 2–4h | Only matters past ~thousands of users. App parsers already handle `{results:[…]}`. |
| F10 | `cached_network_image` (or `cacheWidth`) for player photos | ✅ <1h | Only bites once real photo URLs are served. |

---

## What the brief asked for that does NOT apply here

Recorded so reviewers don't expect these deliverables:

- **Offline-first SQLite / sync engine / conflict resolution / cache invalidation** — no
  on-device database exists; the app is online-only HTTP. If offline support is a real
  requirement, that is a **new 🏗️ epic**, not a refactor.
- **Route polylines / stops / transit N+M queries** — no transit domain.
- **Firestore rules / Cloud Functions / Storage buckets** — only Firebase **Auth** is used;
  there is nothing to lock down in Firestore/Functions/Storage.
- **Supabase Auth / RLS** — Supabase (if adopted) is only a Postgres host; auth is
  Firebase and authorization is Django RBAC.

If any of these are genuinely in scope for the capstone, treat them as greenfield features
and re-plan — they are not present to be refactored.
