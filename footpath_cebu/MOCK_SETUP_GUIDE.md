# Mock Repository Setup Guide

This project now supports running with **mock data** instead of Firebase, allowing you to develop and test the UI without needing Firebase credentials or a backend server.

## Quick Start

### Using Mock Data (Default)

The app is currently set to use mock data. To use it:

1. Run the app normally:
```bash
flutter run
```

2. Login with any of these test accounts:

| Email | Password | Role |
|-------|----------|------|
| `player@example.com` | `demo123` | player |
| `coach@example.com` | `demo123` | coach |
| `admin@example.com` | `demo123` | admin |
| `john.doe@example.com` | `demo123` | player |
| `maria.santos@example.com` | `demo123` | player |

3. **Or use any email** with password `demo123` — the mock accepts any email as long as the password is correct!

### Switching to Firebase

To use real Firebase authentication:

1. Open `lib/main.dart`
2. Change this line:
```dart
ServiceLocator.initMock();
```
to:
```dart
ServiceLocator.initFirebase();
```

3. Run the app:
```bash
flutter run
```

## How It Works

### Architecture

- **`lib/repositories/auth_repository.dart`** — Abstract interface that both implementations follow
- **`lib/repositories/mock_auth_repository.dart`** — Mock implementation with fake data
- **`lib/repositories/firebase_auth_repository.dart`** — Real Firebase implementation
- **`lib/repositories/service_locator.dart`** — Simple DI container to switch between them

### Mock Behavior

The mock repository:
- ✅ Accepts any email address
- ✅ Accepts password: `demo123` (anything else returns "Incorrect email or password")
- ✅ Simulates 500ms network delay
- ✅ Returns a fake user profile with:
  - `id`, `email`, `name`, `role`, `avatar`, `created_at`
  - Role is automatically set to `coach` if email contains "coach", otherwise `player`

### Testing Different Scenarios

**Test as a Player:**
```
Email: player@example.com
Password: demo123
```

**Test as a Coach:**
```
Email: coach@example.com
Password: demo123
```

**Test as an Admin:**
```
Email: admin@example.com
Password: demo123
```

**Test Error Cases:**
- Use `demo123` with wrong password (e.g., `wrong123`) → Error: "Incorrect email or password"
- Or use any email with wrong password

## Why This Matters

This setup lets you:
1. ✅ Develop UI features without Firebase running
2. ✅ Test error states (wrong password, etc.)
3. ✅ Switch to Firebase when backend is ready
4. ✅ Keep code clean with dependency injection
5. ✅ Test both paths in CI/CD if needed

## Notes

- Firebase is still initialized in `main()` but not used when in mock mode
- Both implementations throw `AuthException` for consistent error handling
- The old `AuthService` class can be deleted once confirmed this setup works
