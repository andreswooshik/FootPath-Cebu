# Mobile Club Registration

## Architecture discovered

FootPath does not use Supabase Auth. Mobile identities are managed by Firebase Auth, Django owns users, roles, clubs, validation, and approval, and Supabase is used as private object storage (and may host PostgreSQL). The Flutter client never receives a Supabase service key.

The web portal already submits `CoordinatorSignupForm` to `register_coordinator()`. That service creates one `Club` and one Django `User` with role `COORDINATOR`, `is_active=False`, and no `firebase_uid`. The admin's existing Club review actions activate or reject the records. The mobile endpoint calls this same form and service.

## Registration flow

1. Login shows the secondary `Register your club` action.
2. The applicant enters the existing portal fields and selects a license.
3. Flutter validates required values, matching passwords, extension, and the 50 MB byte limit.
4. `ApiClubRegistrationRepository.submit()` sends one multipart request to `POST /api/public/club-registrations/`.
5. Django repeats authoritative validation, sanitizes the document, uploads it through the existing private storage adapter, and calls `register_coordinator()`.
6. The response is `PENDING`; the app shows the success screen and can return to login.
7. The existing admin Club review screen approves or rejects the same `Club` and coordinator records used by web applications.
8. Approval enables the Django portal account. Under the current architecture, an approved coordinator enables mobile access from the portal, which provisions or links their Firebase identity. Registration itself never creates Firebase access.

## Database and status

No new table or migration was added. The existing `accounts_club` columns are used: `name`, `slug`, `is_active`, `is_school_affiliated`, `school_name`, `head_coach_name`, `coach_license`, `cvfa_membership`, and `created_at`. The existing `accounts_user` row stores the coordinator name, normalized email, hashed Django password, `role=COORDINATOR`, `club_id`, `is_active`, and nullable `firebase_uid`.

There is no separate application-status column. The existing admin derives status from the current records: active club plus inactive coordinator is `PENDING`; active club plus active coordinator is `APPROVED`; inactive club is `NOT_APPROVED`.

## Coach license

Flutter uses the existing `file_picker` dependency. `FilePicker.pickFile()` returns a `PlatformFile`; the screen reads its bytes and maps `.jpg`/`.jpeg`, `.png`, or `.pdf` to the matching MIME type. Both the displayed help and client validation use 50 MB (`52428800` bytes).

Django still gives the web portal its existing 5 MB rule. The same `CoordinatorSignupForm`, validator, limited reader, and sanitizer accept a configurable cap, and only `MobileClubRegistrationView` passes 50 MB. Both raw and sanitized sizes are checked. Files retain the existing random object name `coach-licenses/<uuid>.<ext>` inside the private `coach-licenses` bucket, and `Club.coach_license` stores that object path. The storage upload timeout is 120 seconds for larger mobile uploads.

Deployment must configure the existing Supabase bucket's own file-size limit to at least 50 MB. This repository cannot inspect or change the remote bucket setting. `backend/.env.example` now documents that requirement.

## Authentication, RBAC, and RLS

The public endpoint is intentionally anonymous because applicants do not yet have an identity. It is restricted to one operation, throttled to five requests per hour per client IP, validates every submitted value server-side, and never accepts a role or status from Flutter.

`register_coordinator()` alone assigns the existing `Roles.COORDINATOR` value and always creates this applicant inactive. Admin approval remains the authorization boundary. Normal mobile API access still requires a verified Firebase token mapped to an active Django user in an active club.

Supabase Storage stays private. Flutter does not call Supabase, so no public Storage RLS insert policy or service-role key is required in the app. Django's server-held service key performs the upload and authorized admin reads use short-lived signed URLs. Database tenancy and role checks remain in Django; no RLS rule was disabled or bypassed.

## Flutter state and navigation

`ClubRegistrationScreen` is a `ConsumerStatefulWidget`; its `ConsumerState` owns and disposes the `TextEditingController` objects because typed text is view state. A `Form` and `GlobalKey<FormState>` run synchronous field validators. Riverpod's auto-disposed `ClubRegistrationController` owns selected-license metadata, password visibility, loading, field errors, and submission state.

The widget uses `ref.watch` to rebuild from state and `ref.read` for commands. `Future`, `async`, and `await` cover file selection and network submission. No `ref.invalidate` is needed because a public application does not refresh authenticated data.

This project uses `Navigator` and `MaterialPageRoute`, not GoRouter. Login pushes Registration; successful submission replaces Registration with Success; popping Success or tapping `Back to login` reveals the original Login route without duplicating it. `WidgetRef`, `Ref`, `context.push`, `context.go`, and `context.pop` are not used in this implementation.

## Important methods

- `MobileClubRegistrationView.post(request)` in `backend/portal/api_views.py`: accepts multipart data, runs the 50 MB version of the shared form, calls `register_coordinator()`, and returns 201/PENDING or structured field errors.
- `CoordinatorSignupForm.__init__(..., coach_license_max_bytes)` in `backend/portal/forms.py`: configures the same form for the portal's 5 MB or mobile's 50 MB boundary.
- `validate_coach_license_upload(upload, max_bytes)` and `sanitized_coach_license(upload, max_bytes)` in `backend/accounts/validators.py`: verify extension/MIME/signature, enforce size, remove unsafe metadata or PDF actions, and return the sanitized upload.
- `read_limited_upload()`, `sanitize_image()`, `sanitize_pdf()`, and `sanitize_document()` in `backend/config/upload_security.py`: enforce the caller's byte cap while preserving the existing fail-closed parsing.
- `split_coordinator_name(full_name)` and `register_coordinator(...)` in `backend/portal/services.py`: map the portal's one name field to Django first/last names and atomically create the existing pending records.
- `ApiClubRegistrationRepository.submit(application)` in Flutter's data layer: builds the unauthenticated multipart request, applies a two-minute client timeout, parses field errors, and returns `ClubRegistrationResult`.
- `ClubRegistrationController.setLicense(...)`: validates the actual byte length and supported extension before storing a `CoachLicenseUpload`.
- `ClubRegistrationController.submit(...)`: blocks duplicate calls, trims input, invokes `SubmitClubRegistration`, and preserves form text while exposing backend errors.
- `_pickLicense()` and `_submit()` in `ClubRegistrationScreen`: bridge the picker/form UI to the controller and navigate only after a confirmed server success.

## Files changed

- Backend validation/storage: `accounts/validators.py`, `accounts/storage.py`, `accounts/test_storage.py`, `config/upload_security.py`, `config/settings.py`, `config/urls.py`, and `.env.example`.
- Shared portal workflow: `portal/forms.py`, `portal/services.py`, and `portal/views.py`.
- Public mobile API: `portal/api_views.py`, `portal/api_urls.py`, and `portal/test_mobile_registration_api.py`.
- Flutter domain/data/DI: `club_registration.dart`, `club_registration_repository.dart`, `submit_club_registration.dart`, both API/mock repositories, and `club_registration_dependencies.dart`.
- Flutter UI/state/tests: `club_registration_controller.dart`, `club_registration_screen.dart`, `login_screen.dart`, and `club_registration_screen_test.dart`.

## Verification

- Dart analyzer: no issues.
- Flutter tests: 452 passed.
- Django tests: 500 passed, 7 skipped.
- Django migration check: no changes detected.
