# FootPath-Cebu — Development Setup

Two parts: the Django backend (`backend/`) and the Flutter app
(`footpath_cebu/`). Firebase Authentication holds the credentials; the
backend verifies ID tokens with the Firebase Admin SDK.

## 1. Firebase project (one-time, manual — do this first)

1. Go to <https://console.firebase.google.com> → **Add project** → name it
   `footpath-cebu` (Google Analytics can stay disabled).
2. In the project: **Build → Authentication → Get started → Sign-in method →
   Email/Password → Enable** (leave "Email link" off).
3. **Project settings (gear icon) → Service accounts → Firebase Admin SDK →
   Generate new private key**. Save the downloaded JSON as:

   ```
   backend/secrets/firebase-service-account.json
   ```

   This file is gitignored. **Never commit it.**
4. Install the CLI chain (PowerShell):

   ```powershell
   npm install -g firebase-tools
   firebase login          # opens a browser — sign in with the same Google account
   dart pub global activate flutterfire_cli
   ```

   If `flutterfire` is "not recognized" afterwards, add
   `%LOCALAPPDATA%\Pub\Cache\bin` to your PATH.
5. Wire the Flutter app to the project (from `footpath_cebu/`):

   ```powershell
   flutterfire configure --project=footpath-cebu
   ```

   Select at least **android** and **web**. This overwrites the placeholder
   `lib/firebase_options.dart` with real config. If it offers to apply the
   google-services gradle plugin, decline — Dart-only initialization is
   sufficient here.
6. Note the **Web API Key** (Project settings → General, or inside the
   generated `firebase_options.dart`) — needed for the token test below.

## 2. Backend

```powershell
cd backend
py -m venv .venv                                  # first time only
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
copy .env.example .env                            # first time only; set a real DJANGO_SECRET_KEY
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py seed_users   # needs the service-account JSON in place
.\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
```

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

## 3. Flutter app

```powershell
cd footpath_cebu
flutter pub get
flutter run -d chrome    # fastest loop; or an Android emulator
```

The app picks the backend URL automatically: `http://localhost:8000` on
web/desktop, `http://10.0.2.2:8000` on the Android emulator
(`lib/config/api_config.dart`).

## 4. Verify end-to-end (no app needed)

```powershell
# health + auth gate
Invoke-RestMethod http://localhost:8000/api/health/            # -> status: ok
Invoke-WebRequest http://localhost:8000/api/auth/me/           # -> 401

# mint a real ID token via the Firebase Auth REST API and call /me
$apiKey = "<Web API Key>"
$body = @{ email = "coach@footpathcebu.test"; password = "FootPath!2026"; returnSecureToken = $true } | ConvertTo-Json
$r = Invoke-RestMethod -Method Post -ContentType "application/json" -Body $body `
     -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey"
Invoke-RestMethod http://localhost:8000/api/auth/me/ -Headers @{ Authorization = "Bearer $($r.idToken)" }
# -> role: COACH; repeat with the other four accounts
```

A Firebase user with no provisioned backend account gets **401 "No account
for this login."** — that is the no-self-registration guarantee.

## Troubleshooting

- **"Token used too early"** on the Android emulator: clock drift — cold-boot
  the emulator (the backend already tolerates 10 s of skew).
- **Connection errors from the emulator**: confirm the server runs on
  `0.0.0.0:8000` and the manifest has `android:usesCleartextTraffic="true"`
  (dev-only; production uses HTTPS).
- **Pylance/IDE import warnings in `backend/`**: point VS Code's Python
  interpreter at `backend\.venv\Scripts\python.exe`
  (Ctrl+Shift+P → "Python: Select Interpreter").
