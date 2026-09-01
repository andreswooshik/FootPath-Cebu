# FootPath Cebu — Simple Setup Guide

FootPath Cebu has two parts:

- `backend/` — Django API and web portal
- `footpath_cebu/` — Flutter mobile app

These commands are for Windows PowerShell. Open the project folder in VS Code,
then use **Terminal → New Terminal** so PowerShell starts in the correct folder.

## 1. First-time setup

### Firebase credentials

Get `firebase-service-account.json` from the project owner and place it here:

```text
backend/secrets/firebase-service-account.json
```

Never commit or share this private file.

From the project folder, create the backend environment file:

```powershell
Copy-Item backend\.env.example backend\.env
```

Open `backend\.env`, set a private `DJANGO_SECRET_KEY`, and keep this line:

```text
FIREBASE_CREDENTIALS=secrets/firebase-service-account.json
```

The Flutter Android Firebase configuration is already included.

### Install the backend

```powershell
cd backend
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe manage.py migrate
```

### Install Flutter packages

```powershell
cd ..\footpath_cebu
flutter pub get
```

## 2. Run the backend

Open PowerShell terminal 1:

```powershell
cd backend
.\.venv\Scripts\python.exe manage.py migrate
.\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
```

Keep this terminal open. Available sites:

- Portal: <http://127.0.0.1:8000/portal/>
- Django Admin: <http://127.0.0.1:8000/admin/>
- API health check: <http://127.0.0.1:8000/api/health/>

Create a Django Admin login if needed:

```powershell
.\.venv\Scripts\python.exe manage.py createsuperuser
```

## 3. Run on the SM-X200 tablet using USB

Enable **Developer options** and **USB debugging**, connect the tablet, and
approve the debugging prompt.

Open PowerShell terminal 2:

```powershell
adb devices
adb reverse tcp:8000 tcp:8000

cd footpath_cebu
flutter run -d R9YTB0B22JM --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

If that device ID does not match your tablet, run:

```powershell
flutter devices
flutter run -d <device-id> --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Keep both terminals open while testing.

## 4. Run on an Android emulator

Start Django first, then run:

```powershell
cd footpath_cebu
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## 5. Run with mock data

Mock mode does not require Django or Firebase:

```powershell
cd footpath_cebu
flutter run --dart-define=USE_MOCK=true
```

## Common fixes

### Tablet cannot connect to Django

Run this again before starting Flutter:

```powershell
adb reverse tcp:8000 tcp:8000
```

Also confirm Django is still running on port `8000`.

### Firebase login fails

Check that:

1. `backend/secrets/firebase-service-account.json` exists.
2. `backend/.env` points to that file.
3. The user exists in Firebase Authentication.
4. The same user exists in Django with the correct role and club.

There is no public registration. An authorized Admin or Coordinator must
provision accounts.

### Flutter or VS Code shows old errors

```powershell
cd footpath_cebu
flutter clean
flutter pub get
flutter analyze
```

In VS Code, press `Ctrl+Shift+P` and run **Dart: Restart Analysis Server**.

## Run tests

Backend:

```powershell
cd backend
.\.venv\Scripts\python.exe manage.py test
```

Flutter:

```powershell
cd footpath_cebu
flutter test
flutter analyze
```
