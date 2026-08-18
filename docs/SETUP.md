# FootPath-Cebu — Development Setup

Two parts: the Django backend (`backend/`) and the Flutter app
(`footpath_cebu/`). Both need one shared secret file — ask whoever gave you
this repo link for it (see step 0).

## 0. Get the shared secret file

Download **`firebase-service-account.json`** from the team Google Drive and
save it as:

```
backend/secrets/firebase-service-account.json
```

That's the only file you need from outside the repo. It's gitignored —
never commit it or share it outside the team.

## 1. Backend

```powershell
cd backend
py -m venv .venv                                  # first time only
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
copy .env.example .env                            # first time only
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py seed_users
.\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
```

Open `backend\.env` and set `DJANGO_SECRET_KEY` to any random string (or
generate one: `python -c "from django.core.management.utils import get_random_secret_key as k; print(k())"`).
Everything else in `.env.example` can stay commented out — no database
setup needed, it defaults to a local SQLite file.

`0.0.0.0` matters because it makes the development server reachable from an
emulator or a physical tablet. The Android emulator reaches the host via
`10.0.2.2`; a physical tablet must use the computer's LAN IP instead.

`seed_users` creates one Firebase + local account per role (idempotent,
default password `FootPath!2026`, override with `--password`):

| Email | Role |
|---|---|
| admin@footpathcebu.test | Admin |
| coach@footpathcebu.test | Coach |
| player@footpathcebu.test | Player |
| staff@footpathcebu.test | School Staff |
| guardian@footpathcebu.test | Guardian |

These five log into the **Flutter app** and the custom **admin console**
(`http://localhost:8000/console/`) with their email + the password above —
the console requires the ADMIN role.

The **Django admin site** (`http://localhost:8000/admin/`) is separate: it
needs a Django superuser, not a seeded account:

```powershell
.\.venv\Scripts\python.exe manage.py createsuperuser
```

Log in there with the **username** you set (not an email). Use it for Super
Admin Club and Coordinator setup—see section 2.

## 2. Web portal — club coordinators & school staff

The portal (`http://localhost:8000/portal/`) is the multi-club admin surface,
separate from the Flutter app. It is server-rendered and uses **Django session
login** (email + password), **not** Firebase — its users never touch the mobile
app.

**Super Admin setup, then Club Coordinator provisioning:**

1. Super Admin opens `/admin/` → **Clubs**, creates the Club, and selects School
   or Independent using the existing school-affiliation field.
2. Super Admin creates the Club's single `COORDINATOR` user, assigns that Club,
   and relays the generated/selected portal password. The protected API
   equivalents are `POST /api/admin/clubs/` and
   `POST /api/admin/coordinators/`.
3. The coordinator logs in at `/portal/login/` and, from **Create accounts**,
   provisions **players, coaches and guardians**—and **School Staff only for a
   School Club**. The server always stamps the Coordinator's own Club.

**School staff** — log in at `/portal/` and open **Academic eligibility** to set
their club's players' eligibility (Eligible / Not Eligible / Pending / Academic
Warning). Each change is recorded in the append-only eligibility history.
Independent Clubs receive Not Applicable behavior and cannot create School
Staff. FootPath Cebu never stores raw student grades.

> Everything is isolated per club: a coordinator, coach or staff member only
> ever sees their own club's players, roster, sessions and eligibility. Django
> superusers / the ADMIN role are the only cross-club view.

## 3. Flutter app

```powershell
cd footpath_cebu
flutter pub get
flutter run -d chrome --dart-define=USE_MOCK=false
```

**`--dart-define=USE_MOCK=false` matters** — in debug builds the app defaults
to in-memory mock data (no backend needed) unless this flag is set. Omit it
to work on UI without the backend running; include it to test against the
real backend. Release builds (`flutter run --release`) always use the live
backend regardless.

The app picks the backend URL automatically: `http://localhost:8000` on
web/desktop, `http://10.0.2.2:8000` on the Android emulator. Override with
`--dart-define=API_BASE_URL=http://<computer-lan-ip>:8000` for a physical
device on the same Wi-Fi. Use the computer's IP, not the tablet's IP.

### Physical Android tablet

First pair the tablet through Android **Developer options → Wireless
debugging**, then confirm that Flutter sees it:

```powershell
flutter devices
```

For wireless debugging, the pairing port and debug port are different:

```powershell
adb pair <tablet-ip>:<pairing-port>
adb connect <tablet-ip>:<debug-port>
```

Then run the live Flutter app using the tablet device ID and the computer's
LAN IP:

```powershell
flutter run -d <tablet-ip>:<debug-port> `
  --dart-define=USE_MOCK=false `
  --dart-define=API_BASE_URL=http://<computer-lan-ip>:8000
```

Example, where the tablet is `10.0.0.30:44107` and the computer is
`10.0.0.4`:

```powershell
flutter run -d 10.0.0.30:44107 `
  --dart-define=USE_MOCK=false `
  --dart-define=API_BASE_URL=http://10.0.0.4:8000
```

The tablet and computer must be on the same Wi-Fi network, and Windows
Firewall must allow inbound TCP traffic on port `8000`. The Flutter app needs
an actual Firebase account with a matching provisioned Django user when
`USE_MOCK=false`; mock/demo credentials are only for mock mode.

## Troubleshooting

- **"Token used too early"** on the Android emulator: clock drift — cold-boot
  the emulator (the backend already tolerates 10 s of skew).
- **Connection errors from the emulator**: confirm the server runs on
  `0.0.0.0:8000` and the manifest has `android:usesCleartextTraffic="true"`
  (dev-only; production uses HTTPS).
- **"Could not sign in" on a physical tablet**: confirm the app was launched
  with `USE_MOCK=false` and `API_BASE_URL=http://<computer-lan-ip>:8000`.
  `10.0.2.2` is for the Android emulator and `localhost` points to the tablet
  itself.
- **Debug APK signing error**: use `flutter run` or build with
  `flutter build apk --debug`. Release signing variables are intentionally
  required only for release builds.
- **`seed_users` fails / Firebase errors**: the service-account JSON is
  missing or in the wrong place — re-check step 0.
- **`Bad state: databaseFactory not initialized`** in the browser console when
  running the app on **Chrome/desktop**: the offline attendance queue uses
  `sqflite`, which only ships a platform database on Android/iOS. It is
  **non-fatal** — login and every screen still work; only the *offline*
  attendance sync is unavailable on web. Run on an Android emulator to exercise
  offline attendance.
- **Pylance/IDE import warnings in `backend/`**: point VS Code's Python
  interpreter at `backend\.venv\Scripts\python.exe`
  (Ctrl+Shift+P → "Python: Select Interpreter").

## No access to the shared file? Set up your own Firebase project

Only needed if you don't have the Drive file and can't get it — this spins
up a completely separate Firebase project for yourself.

1. <https://console.firebase.google.com> → **Add project** → any name.
2. **Build → Authentication → Sign-in method → Email/Password → Enable**.
3. **Project settings → Service accounts → Generate new private key** → save
   as `backend/secrets/firebase-service-account.json`.
4. `npm install -g firebase-tools && dart pub global activate flutterfire_cli`,
   then from `footpath_cebu/`: `flutterfire configure --project=<your-project>`
   (overwrites `lib/firebase_options.dart` — select at least android + web).
5. Continue from step 1 above. Note you'll only be able to log in with
   accounts `seed_users` creates in *your* project — you won't share
   accounts/data with teammates on the real project.
