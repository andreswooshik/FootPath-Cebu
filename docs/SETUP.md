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

`0.0.0.0` matters: the Android emulator reaches the host via `10.0.2.2`.

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

Log in there with the **username** you set (not an email).

## 2. Flutter app

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
`--dart-define=API_BASE_URL=http://<lan-ip>:8000` for a physical device on
the same Wi-Fi (run the server as `runserver 0.0.0.0:8000` in that case).

## Troubleshooting

- **"Token used too early"** on the Android emulator: clock drift — cold-boot
  the emulator (the backend already tolerates 10 s of skew).
- **Connection errors from the emulator**: confirm the server runs on
  `0.0.0.0:8000` and the manifest has `android:usesCleartextTraffic="true"`
  (dev-only; production uses HTTPS).
- **`seed_users` fails / Firebase errors**: the service-account JSON is
  missing or in the wrong place — re-check step 0.
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
