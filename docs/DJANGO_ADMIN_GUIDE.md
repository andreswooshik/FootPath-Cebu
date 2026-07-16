# Django Admin Console & Management Commands

This guide covers running the Django admin interface and management commands for FootPath Cebu.

## Prerequisites

1. Backend environment set up:
```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

2. Environment variables configured (`.env` file):
```bash
# Copy and fill .env.example
cp .env.example .env
# Edit .env with your settings (DB credentials, secrets, etc.)
```

3. Database migrations applied:
```bash
python manage.py migrate
```

## Running the Django Admin Console

### Start the development server:

```bash
cd backend
python manage.py runserver
```

The server will start on `http://localhost:8000/`.

### Access the admin interface:

Navigate to `http://localhost:8000/admin/`

### Login credentials:

Use the superuser account you created during setup:
```bash
python manage.py createsuperuser
# Follow the prompts for email and password
```

## Management Commands

### Seed Initial Users

Populate the database with test users (coaches, players, guardians):

```bash
cd backend
python manage.py seed_users
```

**What it does:**
- Creates Firebase auth accounts (via Admin SDK)
- Creates corresponding Django User objects
- Sets up roles (COACH, PLAYER, GUARDIAN, ADMIN)
- Returns credentials for testing

**Requirements:**
- Firebase service account JSON in `backend/secrets/serviceAccountKey.json`
- Firebase project configured in settings

### Seed Academy Data

Populate the database with player profiles, training sessions, and attendance:

```bash
cd backend
python manage.py seed_academy
```

**What it does:**
- Creates 10 player profiles with ratings and eligibility status
- Creates 3 training sessions with age-tier targeting
- Creates attendance records linking players to sessions
- Creates guardian links (guardian → players)

**Prerequisite:** Run `seed_users` first (creates the players and coaches)

### Full Seed Workflow

```bash
cd backend

# 1. Create superuser for admin access
python manage.py createsuperuser

# 2. Populate users
python manage.py seed_users

# 3. Populate academy data
python manage.py seed_academy

# 4. Start the server
python manage.py runserver
```

Then access:
- Admin console: `http://localhost:8000/admin/`
- API: `http://localhost:8000/api/`
- Console (file uploads, user management): `http://localhost:8000/console/`

## Admin Console Features

### Users Tab
- View all users (coaches, players, guardians, admins)
- Edit user roles and permissions
- Create new users manually

### Players Tab (Academy app)
- View player profiles with ratings
- Edit eligibility status (ELIGIBLE / NOT_ELIGIBLE / PENDING / ACADEMIC_WARNING)
- Upload player photos

### Training Sessions Tab
- View all scheduled sessions
- Create new sessions
- Specify age tiers and session focus
- Edit dates and times

### Attendance Tab
- Record player attendance (PRESENT / ABSENT / EXCUSED)
- Filter by player or session
- Update attendance status

### Guardian Links Tab
- View guardian-player relationships
- Link guardians to their children
- Unlink relationships

## Common Tasks

### View all players:
```
Admin > Academy > Players
```

### Check a player's ratings:
```
Admin > Academy > Players > [Select player]
```

### See training schedule:
```
Admin > Academy > Training Sessions
```

### Record attendance:
```
Admin > Academy > Attendance > Add attendance
```

### Upload player photo:
```
Admin > Academy > Players > [Select player] > Photo field
```

Or use the console web interface: `http://localhost:8000/console/`

## Troubleshooting

**"No module named 'academy'"**
- Run `python manage.py migrate`
- Ensure `'academy'` is in `INSTALLED_APPS` in settings.py

**Firebase authentication fails**
- Check that `serviceAccountKey.json` exists in `backend/secrets/`
- Verify Firebase credentials are valid
- Ensure Firebase project is set up in settings

**Database connection error**
- Verify `.env` has correct database credentials
- If using SQLite (dev), check that `db.sqlite3` exists
- If using Postgres/Supabase, verify the host and port are correct

**"User matching query does not exist"**
- Run `seed_users` to populate initial test users

## Environment Variables

Key variables in `.env`:

```bash
# Database
DB_HOST=localhost  # or Supabase host for production
DB_NAME=footpath_cebu
DB_USER=postgres
DB_PASSWORD=your_password
DB_PORT=5432

# Django
DJANGO_SECRET_KEY=your_secret_key
DJANGO_DEBUG=True  # False in production
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1

# Firebase
FIREBASE_CREDENTIALS=path/to/serviceAccountKey.json

# CORS
CORS_ALLOWED_ORIGINS=http://localhost:8000
```

See `.env.example` for the complete template.

## Next Steps

- Create test data via seed commands
- Access admin at `http://localhost:8000/admin/`
- Test API endpoints: `http://localhost:8000/api/players/`
- Upload photos via `/console/`
- Run tests: `python manage.py test`
