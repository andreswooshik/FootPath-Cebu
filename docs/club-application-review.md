# Super Admin club application review

## What existed before this change

The feature **partially existed**. Club applications are already actual `Club` records in Django, not a separate application table. The Super Admin reviews web and mobile submissions at `/admin/accounts/club/`, then opens `/admin/accounts/club/<id>/change/`. Flutter submits applications; this review interface is the Django/Jazzmin admin.

| Item inspected | Existing implementation |
| --- | --- |
| Application list and loading | `ClubAdmin` uses Django's changelist and ORM queryset. |
| Pending applications | Active club with an inactive Coordinator; previously there was no dedicated Pending status filter. |
| Details and evidence | `admin/accounts/club/change_form.html`; pending submitted fields are read-only. |
| Approval button and handler | `_approve_application` posts to `ClubAdmin.changeform_view()`, which calls `approve_registrations()`. It previously submitted immediately. |
| Rejection button and handler | `_not_approve_application` calls `disapprove_registrations()`. It previously said “Not approve” and used a generic `window.confirm()` without the club name. |
| Repository/service/backend | Django ORM plus `accounts.services.set_coordinator_firebase_disabled()`; no review repository, RPC, Edge Function, or Supabase Auth operation. |
| Status values | Derived `PENDING`, `APPROVED`, `NOT_APPROVED`, `INCOMPLETE`. There is no application-status column. |
| Confirmation components | The portal uses native `<dialog>`; admin uses Jazzmin/Bootstrap buttons and FootPath CSS tokens. |
| Loading/double-submit protection | Missing for the application-detail decisions. |
| Errors and success notifications | Django's existing messages framework, rendered as Jazzmin alerts. Approval already handled Firebase errors; rejection previously saved inactive flags and reported success even after Firebase failure. |
| RBAC | Session-authenticated Django admin, staff access, and model permissions; the role constant is `Roles.ADMIN`, displayed as “Super Admin”. Review actions now additionally enforce that existing role on the server. |
| RLS | Settings explicitly use Django as the database authorization boundary rather than Supabase Auth/database RLS. Supabase coach-license storage is private and accessed only through the server. |
| Coordinator creation | `register_coordinator()` calls `provision_club_coordinator()` during signup, creating one inactive Django Coordinator and a linked disabled Firebase identity. |
| Club creation | `register_coordinator()` creates the club during signup; approval updates the existing club. |
| Rejection reason/remarks | No field or collection step exists for club rejection. None was added. |

## Current approval and rejection flows

1. The Super Admin opens a pending application's details and presses **Approve** or **Reject**.
2. The dialog displays the actual club name and the effect of that decision. Names are HTML-escaped by Django and inserted into dialog text using `textContent`.
3. **Cancel** or Escape closes the dialog, leaves the details open, and sends no backend request.
4. Confirm sends one CSRF-protected POST to the **existing change-form URL**, with the existing decision field and `_confirm_application=1`.
5. `changeform_view()` verifies authorization and Pending state, then calls the existing approval or rejection method with `pending_only=True`.
6. That method locks the club and Coordinator, rechecks the state after acquiring the locks, updates Firebase through the existing service, then saves the existing active flags in a database transaction.
7. The existing handler redirects to the details view. `fetch()` follows that redirect; JavaScript reads the returned Django HTML to update the visible review status and the existing message area. The browser stays on the details page.
8. Decision buttons disappear once the returned state is no longer Pending. Returning to the existing registry fetches current database data. Its new Application status filter supports Pending, Approved, Not approved, and Incomplete.

Approval sets `accounts_club.is_active=True` and the linked `accounts_user.is_active=True`, deriving **APPROVED**. Rejection sets both flags to `False`, deriving **NOT_APPROVED**; the UI button says “Reject”, but the existing database/status vocabulary remains intact.

When JavaScript or native-dialog support is unavailable, the first POST renders a server confirmation page and performs no writes. Cancel returns to the details URL. Only the second, confirmed POST executes the decision. This fallback uses the same URL and handlers.

The existing bulk “Activate selected clubs and coordinators” and “Deactivate selected clubs and coordinators” actions intentionally support broader club lifecycle transitions, including reactivation. Their existing transitions remain available to authorized Super Admins; the detail-review path always passes `pending_only=True`. No new bulk workflow was introduced.

## Coordinator activation, authorization, and failures

The Coordinator's Django user, password hash, `role=COORDINATOR`, `club_id`, and `firebase_uid` already exist after successful signup. The Firebase Auth account also exists and is disabled. Approval enables that **existing** Firebase account and activates the **existing** Django user. It does not create another account, change the role, create a new profile, or create a second club. The same signup credentials then work in the Coordinator portal and mobile app.

`has_review_permission()` requires an authenticated, active staff account with `Roles.ADMIN` **and** Django's existing Club change permission. The view and both action methods enforce it. Other roles cannot approve by forging a POST, even if they have Django's `change_club` permission. Review buttons and bulk review actions are hidden for those accounts. Django's existing admin login and CSRF protection remain in place.

No RLS policy, migration, Supabase function, credential, or Flutter code was changed. The project does not use client-side Supabase queries to approve clubs. Its configured database access goes through Django, and its private Supabase documents remain behind the existing server storage adapter. Remote Supabase policies were not inspected or changed.

Confirm sets a synchronous JavaScript `processing` guard before starting the request. Approve/Reject and Cancel become disabled, Escape cannot dismiss the processing dialog, and the confirmation button displays **Approving...** or **Rejecting...**. Repeated clicks therefore send one POST. Database row locks and a fresh Pending check also prevent another confirmed detail request from applying an already completed decision on PostgreSQL. SQLite does not implement row locks; the concurrency integration test requires isolated PostgreSQL.

Firebase failure leaves the local transaction unchanged and emits an error without a success message. A database save failure rolls back both flags and attempts to restore Firebase's previous disabled state using the same existing service. Firebase and Django cannot share a distributed transaction: if restoration also fails, the server logs that failure; an inactive local Coordinator/club still fails the existing portal/mobile access checks for a pending application.

If the browser loses the decision response, it performs a read-only GET to reconcile actual backend state. It never assumes Pending or claims success from an unconfirmed response. If even that GET fails, it disables further decisions and asks the administrator to reopen the application.

## Files changed

| File | Purpose |
| --- | --- |
| `backend/accounts/admin.py` | Reuse and guard existing review handlers, add server confirmation fallback, role checks, locked Pending checks, safe failure handling, and the derived-status registry filter. |
| `backend/accounts/templates/admin/accounts/club/change_form.html` | Add the club-name-aware native dialog, permission-aware review controls, status marker, and existing-message container. |
| `backend/accounts/templates/admin/accounts/club/review_confirmation.html` | Server-rendered confirmation when JavaScript/modal support is unavailable. |
| `backend/accounts/static/footpath/club_review.js` | Confirmation interaction, duplicate/loading guard, existing-endpoint POST, HTML-based status/message refresh, and uncertain-response reconciliation. |
| `backend/accounts/static/footpath/admin.css` | Style the native dialog and reviewed-status chips using FootPath's existing admin tokens. |
| `backend/accounts/test_club_application_review.py` | Regression coverage for confirmation, cancellation, failures, roles, CSRF, repeat decisions, lists, real browser behavior, and PostgreSQL concurrency. |
| `backend/accounts/browser_tests/club_review.cjs` | Optional Playwright runner against Django's actual templates and isolated live test server. |
| `backend/portal/tests.py` | Give the existing bulk-action test a real authorized Super Admin request; preserve its reactivation/deactivation assertions. |
| `docs/club-application-review.md` | Inspection findings, capstone explanation, method reference, and verification instructions. |

## Important methods

Python methods below are in `backend/accounts/admin.py`. Browser functions are in `backend/accounts/static/footpath/club_review.js`. Return types are descriptive; these files follow the project's existing unannotated style.

| Method | Parameters and return | Caller, purpose, backend operation, and result |
| --- | --- | --- |
| `ClubRegistrationStatusFilter.lookups()` | `request, model_admin` → tuple of value/label pairs | Django renders the existing derived status choices in the registry filter. No writes. |
| `ClubRegistrationStatusFilter.queryset()` | `request, queryset` → Club QuerySet | Django filters active flags and the Coordinator relation for the selected state. No writes. |
| `ClubAdmin.has_review_permission()` | `request, obj=None` → bool | Called by the view, action methods, and `get_actions()`. Checks the existing role and model permission; performs no decision. |
| `ClubAdmin.get_actions()` | `request` → action dictionary | Django loads bulk controls; unauthorized accounts lose the review actions. No writes. |
| `ClubAdmin.changeform_view()` | `request, object_id=None, form_url='', extra_context=None` → HTTP response | Existing admin change route renders details/confirmation, denies unauthorized users, or delegates a confirmed Pending decision to the existing methods. Adds current state to rendered HTML. |
| `ClubAdmin.approve_registrations()` | `request, queryset, *, pending_only=False` → int | Confirmed detail view uses `True`; existing lifecycle bulk action uses the default. Locks records, enables Firebase, saves both active flags, reports errors/success, and returns the number approved. |
| `ClubAdmin.disapprove_registrations()` | `request, queryset, *, pending_only=False` → int | Same callers and locking pattern. Disables Firebase/revokes refresh tokens through the existing service, saves both inactive flags, reports errors/success, and returns the number rejected/deactivated. |
| `ClubAdmin._restore_coordinator_identity()` | `coordinator, *, disabled` → None | Either action calls this after a local save failure following a completed Firebase update. Restores the prior Firebase flag; logs restoration failure. |
| `initialise()` | no arguments → undefined | DOM-ready callback attaches dialog/form listeners. The fallback page only gets a submission/loading guard. No request during initialization. |
| `notify()` | `text, level` → undefined | Uncertain-response handling renders an existing-style alert safely as text. No backend operation. |
| `setProcessing()` | `value` boolean → undefined | Dialog/form handlers set the synchronous guard, disabled controls, busy attributes, and progress text. No backend operation. |
| `refreshFromHTML()` | `html, showMessages` → undefined; throws for missing state | Confirmation response/reconciliation reads Django's returned status marker and messages, updates the panel, and removes completed review controls. No database writes. |
| Form submit handler | DOM `event` → undefined | Initial decision click prevents submission and opens the named confirmation. No backend request. |
| Confirmation click handler | no arguments → Promise resolving undefined | Calls the existing admin URL with FormData only after confirmation; awaits the result, refreshes state/messages, handles uncertain results with a GET, and releases the guard. |

The existing `_registration_state(club)` remains the status interpreter. `set_coordinator_firebase_disabled(user, *, disabled)` remains the Firebase boundary. `register_coordinator()` and `provision_club_coordinator()` remain the signup/provisioning path and are not called by confirmation. No repository or service was duplicated.

## Verification and reproduction

Local verification results:

- The targeted run completed **19 tests: 17 passed, 2 skipped** (the optional browser test and PostgreSQL concurrency test). The browser test was then run separately and passed.
- The headless Chrome integration test passed against actual Django templates and JavaScript, with Firebase mocked.
- The full SQLite suite ran **524 tests: 513 passed, 9 skipped, 2 failed**. The two signup failures report unavailable coach-license storage and were reproduced using the original `HEAD` versions of the changed Python modules. They are pre-existing failures in this isolated configuration, not review regressions.
- Repository-wide Ruff lint passed. Formatting passed for all three changed Python files. The full working-copy formatting check found mixed line endings in six untouched files; their committed `HEAD` versions passed formatting.
- Django system checks, migration-drift checks, Python compilation, both JavaScript syntax checks, static asset collection into temporary output, and `git diff --check` passed.
- The PostgreSQL concurrency test was added but was not executed locally because the available test database is SQLite. It runs in the existing isolated PostgreSQL CI job. No live Supabase/Firebase operation was used for verification.

Run backend commands from `backend/`, using its existing virtual environment and isolated test configuration:

```text
python manage.py test accounts.test_club_application_review portal.tests.ApprovalActionTests --noinput
python manage.py test --noinput
python manage.py check
python manage.py makemigrations --check --dry-run
ruff check .
ruff format --check accounts/admin.py accounts/test_club_application_review.py portal/tests.py
node --check accounts/static/footpath/club_review.js
node --check accounts/browser_tests/club_review.cjs
```

The optional browser test requires Node and a locally installed Playwright module. Set `FOOTPATH_PLAYWRIGHT_MODULE` to that module's absolute path and optionally set `FOOTPATH_BROWSER_EXECUTABLE` to installed headless Chrome/Edge when Playwright's own browser is unavailable. Then run:

```text
python manage.py test accounts.test_club_application_review.ClubApplicationReviewBrowserTests --noinput
```

It uses a temporary Django test database, a local test server, a test administrator session, and mocked Firebase calls. It covers confirmation/cancellation, Escape, double clicks, loading, both Firebase failures, retry after a network failure, a committed decision with a lost response, a stale second reviewer, refreshed Pending listings, and the no-JavaScript fallback.

The concurrent-reviewer test runs in the repository's existing PostgreSQL CI job when `TEST_POSTGRES_*` points at an isolated test database. It is skipped under local SQLite. Do not use production database credentials for tests.
