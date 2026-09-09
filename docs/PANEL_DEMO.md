# FootPath Cebu Panel Demo

## Start the system

Backend:

```powershell
cd backend
python manage.py runserver 0.0.0.0:8000
```

Flutter on an Android emulator:

```powershell
cd footpath_cebu
flutter run --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Rebuild the deterministic demo at any time:

```powershell
cd backend
python manage.py seed_users --password "FootPath!2026"
python manage.py seed_academy
```

## Demo credentials

All accounts use the password `FootPath!2026`.

| Role | Email | Interface |
|---|---|---|
| Super Admin | `admin@footpathcebu.test` | `http://127.0.0.1:8000/admin/` |
| Club Coordinator | `coordinator@footpathcebu.test` | Flutter app and `/portal/login/` |
| Coach | `coach@footpathcebu.test` | Flutter app |
| Player | `player@footpathcebu.test` | Flutter app |
| Guardian | `guardian@footpathcebu.test` | Flutter app |
| School Staff | `staff@footpathcebu.test` | `http://127.0.0.1:8000/portal/login/` |

The demo Player privacy PIN is `2468`.

## Recommended panel flow

1. Sign in as the Coordinator and open **Rising Star Cup — Boys U14**.
   Explain that the Coordinator creates and publishes the tournament programme.
2. Show the published U14 squad and the completed **Group A · Match 1** result
   against Danao City FC. Group matches 2 and 3 are ready for result entry.
3. Open the **Semifinal** fixture, which intentionally has opponent `TBD`.
   After explaining that the club qualified, update it to the real knockout
   opponent. The **Championship** row remains ready for the same progression.
4. Sign in as the Coach. Open the completed Danao City FC match and rate the
   unrated player performances. Objective match statistics remain Coordinator
   owned; the subjective rating and notes remain Coach owned.
5. Show the Coach roster, development assessment, training schedule,
   attendance, progress, and the open attendance dispute.
6. Sign in as the Player to show the profile card, five-domain assessment,
   match history, attendance, training confirmation, tournament schedule,
   notifications, eligibility, and injury history.
7. Sign in as the Guardian and use PIN `2468` to show the linked Player's
   protected records and pending injury review.
8. Sign in as School Staff to demonstrate academic eligibility and responding
   to the open dispute.
9. Finish in Super Admin to show club/account management, role separation,
   audit records, and Firebase-backed password management.

## Seeded scenario

- Active school-affiliated demo club with all six roles
- Seven-player roster across Foundation, Development, and Pathway tiers
- Published Rising Star Cup U14 schedule, bracket, squad, and five fixtures
- One completed group fixture with objective statistics awaiting Coach ratings
- Two playable group fixtures plus TBD semifinal and championship fixtures
- Upcoming and past training sessions, attendance, and player confirmation
- Five-domain development assessment and historical match performance
- Guardian link and known privacy PIN
- Pending injury report, open dispute, eligibility states, and inbox records

Push delivery still depends on an FCM-capable physical device and its registered
device token. The persistent in-app notification inbox is seeded and can be
demonstrated without relying on live push delivery.
