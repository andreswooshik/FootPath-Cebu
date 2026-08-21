# Defense Demo Script

## Demo goal

Prove one integrated, live, role-controlled data path—not merely a sequence of attractive screens. The ideal demonstration shows a coach write reaching Django, another role reading the result, and one rejected unauthorized action or privacy gate.

Target duration: 10–12 minutes, plus a 3-minute fallback version.

## Pre-demo checklist

Complete this before the panel enters:

- Launch Flutter with live repositories: `--dart-define=USE_MOCK=false`.
- Confirm `API_BASE_URL` points to the demo Django backend and uses the correct device-reachable host.
- Confirm Firebase initialization and the backend service account are valid.
- Confirm the backend database is seeded with one club, coach, player, linked guardian, school staff, today’s training session, and known demo PIN.
- Use non-sensitive disposable demo credentials; do not show `.env`, Firebase Admin JSON, tokens, or Supabase service keys.
- Confirm all demo users are active and club-assigned.
- Keep coordinator/staff portal and Django admin already open in separate private/demo browser sessions.
- Turn off debug banners/log overlays that may reveal tokens.
- Verify Flutter is not showing mock-only fixture names.
- Test the network path from the actual phone/emulator.
- If demonstrating photo upload, confirm Supabase Storage credentials/bucket and use a disposable non-child image.
- If demonstrating remote push, confirm Firebase/APNs device configuration and send one rehearsed event; otherwise demonstrate the persistent inbox/API without claiming physical push delivery.
- Take a recoverable pre-demo database snapshot and write down the reset steps.
- Have terminal commands and backup screenshots/video available, but label any backup media as prerecorded evidence.

## Evidence to keep visible

Use a split view if possible:

- mobile app for user action;
- portal/admin or a safe database/admin list for persisted result;
- backend request log with method/path/status only (avoid headers/tokens).

## Full 10–12 minute script

### 0:00–0:45 — Opening

Say:

> FootPath Cebu centralizes youth academy operations. Flutter serves coaches, players, and guardians. Django is the data and authorization authority; Firebase establishes mobile identity and sends push notifications. I will demonstrate live mode, a coach workflow, cross-role visibility, and the guardian privacy boundary.

Point to the live configuration without exposing secrets. State that debug normally supports mocks but this run uses `USE_MOCK=false`.

### 0:45–1:45 — Login and role routing

1. Open the mobile app at login.
2. Sign in as the coach using a disposable account.
3. Show the coach portal/dashboard.
4. Briefly explain that Firebase sign-in is followed by Django `/api/auth/me/` and server role/club lookup.

Proof statement:

> A Firebase account alone cannot enter the academy system. Django requires a matching active user and club, and returns the authoritative role used for this routing.

### 1:45–3:15 — Roster and assessment

1. Open the squad/roster.
2. Demonstrate local search/tier/position filtering; state that filtering occurs after the club-scoped roster is fetched.
3. Open the prepared player.
4. Edit one rating and a distinctive non-sensitive note such as `Defense demo assessment 10:02`.
5. Save and show the success/refreshed value.
6. In Django admin or a player read view, show the persisted value.

Proof statement:

> The screen called a controller, use case, and repository. Django reverified the coach, checked same-club player access, validated ratings as 0–99, saved the profile, audited the event, and returned the serialized player.

Honesty note: state that this overwrites the current assessment; historical assessment snapshots are not yet implemented.

### 3:15–5:15 — Attendance, including resilience explanation

1. Open today’s prepared session.
2. Mark the prepared player present, set an effort value/note, and mark other prepared rows appropriately.
3. Finalize attendance.
4. Show the persisted attendance in a read screen/admin.
5. Explain the offline branch; do not intentionally disable the network unless it has been rehearsed and cleanup is deterministic.

Say:

> The server receives the complete session batch and updates it atomically. If the write fails specifically because of network connectivity, the mobile decorator stores the entire batch in a Firebase-user-scoped sqflite outbox. It replays oldest first. We use a simple last-write-wins policy for later complete batches.

If demonstrating offline:

1. Disable connectivity only after the online proof.
2. change one mark and submit;
3. show queued feedback without claiming server persistence yet;
4. restore network;
5. trigger/wait for the known sync path;
6. show the server record changed;
7. ensure the queue is empty for the demo owner.

### 5:15–6:30 — Schedule/session confirmation

1. As coach, open the training schedule and show a club session.
2. Optionally create a future session with a recognizable title if live push is configured.
3. Open the notification bell and show the authenticated inbox/unread state; if an actual push arrives, show foreground feedback and the trusted route to Schedule/Profile/Eligibility for a known event, or the focused-inbox fallback for an unknown event/profile failure.
4. Explain that Django validates start/end together and requires start before end through both serializer and model paths.
5. Sign in as the player and show today’s session confirmation control.
6. Submit the player response and show it on the coach’s confirmation view if available.

Say:

> The backend derives the confirming player from the token and only accepts today’s same-club session. Failed submission now produces visible retryable feedback rather than implying it was saved.

### Optional 1-minute insert — Coach player photo

1. As Coach, open a player from the same Club.
2. Choose **Update player photo** and select a prepared JPEG/PNG/WebP.
3. Show upload feedback and the refreshed roster/profile image.
4. In the backend log, show only the multipart endpoint/path and success status.

Say:

> Flutter performs early type/size validation, but Django repeats role, same-Club, size, MIME, and signature checks before private storage. The service credential never enters Flutter. This demo requires configured Supabase Storage credentials.

### 6:30–8:30 — Guardian privacy boundary

1. Sign in as the linked guardian.
2. Show the linked-player selector’s limited data.
3. Select the player and intentionally enter one wrong PIN once.
4. Show rejection, then enter the correct demo PIN.
5. Open permitted profile/attendance/eligibility data.
6. If time permits, sign out and show the unlock must be repeated because it is held only in memory.

Say:

> Django stores a one-way PIN hash, counts failures transactionally, locks after five failures, and issues a ten-minute signed token bound to this guardian and player. Protected calls still recheck the guardian link.

Do not intentionally reach five failures during the main demo unless a separate reset account exists.

### 8:30–9:45 — School staff eligibility and history

1. Switch to the school-staff portal.
2. Select the same club player.
3. Change eligibility using a prepared reversible demo status.
4. Return to the player/guardian eligibility history and refresh.
5. Show old/new status, actor/time as available.

Say:

> The current status lives on the player profile. Signals capture each change in an eligibility-history row and audit record, then schedule notification after commit. We store eligibility, not grades.

### 9:45–10:15 — Logout and session boundary

1. Use the guardian/player sign-out action.
2. Show that the app returns to login and back navigation does not reopen private child data.
3. Explain that the device token is best-effort unregistered, that owner’s safe-read cache and in-memory unlock store are cleared, and Firebase signs out; academy rows are not deleted.

Say:

> Logout removes the mobile identity session and temporary guardian unlocks, then replaces the authenticated route. A future login must be authorized by Django again.

### 10:15–11:00 — Boundaries and close

Say:

> The implemented core includes development profiles, schedules, attendance, eligibility, injuries, disputes, privacy PINs, invariant-safe account provisioning, private Coach photo upload, and a durable notification inbox with foreground/open handling. AI, scouting, match statistics, and chat are not implemented. The final local suites are green; remaining defense work is to reconcile the 0–99 rating specification and attach real device, deployment, monitoring, backup, and restore evidence.

Close with the architecture in one sentence:

> Flutter handles interaction, Firebase proves identity, Django decides authorization and persists relational data, and local SQLite queues attendance network failures while safely caching eligible reads by owner.

## Possible panel interruptions by demo step

| Step | Likely interruption | Best immediate answer |
|---|---|---|
| Opening/live mode | “How do we know this is not mocked?” | Show `USE_MOCK=false`, backend path/status-only log, and a cross-role/server-visible mutation |
| Login | “Why authenticate twice?” | Firebase proves identity; `/api/auth/me/` supplies active local role/club authorization |
| Role routing | “Can Flutter role checks be bypassed?” | UI can be modified, so Django rechecks role/club/object on every endpoint |
| Roster | “Is search hitting the database?” | Initial roster is club-scoped server-side; visible filters are local over `List<Player>` |
| Assessment | “Where is historical improvement?” | Current values overwrite; assessment-version history is not implemented |
| Scouting | “Show the scout report.” | No scout/report flow exists; do not substitute disputes. It is explicitly out of current scope |
| Attendance | “What if two coaches edit offline?” | Ordered full-batch replay yields last-write-wins; version/conflict review is future hardening |
| Session/RSVP | “Can a player RSVP for someone else?” | Backend ignores client player identity and derives player from `request.user` |
| Guardian PIN | “Is four digits secure?” | It is secondary to login/link, hashed, five-attempt locked, and grants only a ten-minute bound token |
| Eligibility | “Where are the grades?” | No grades are stored—only status and append-only change history |
| Notifications | “Open the notification inbox.” | Open the bell/inbox, show unread/read actions, and explain that known trusted events route to authorized Schedule/Profile/Eligibility destinations while unknown events/profile failures safely focus the inbox; keep physical push delivery evidence separate |
| AI | “Where is the AI recommendation?” | No AI exists; aggregates are deterministic and are not misrepresented |
| Logout | “Does logout revoke the token globally?” | Ordinary logout clears local Firebase state; backend revocation checking supports revoked tokens, but local logout is not an admin global revoke |
| Closing | “Is it production-ready?” | Repository hardening exists—container, probes, runbook, monitoring hooks, backup/restore scripts—but live deployment, alert, scheduled-backup, restore-drill, and governance evidence remain |

## Three-minute fallback demo

1. State live mode and sign in as coach.
2. Edit one player assessment and show it persisted/refetched.
3. Sign in as guardian, show redacted selector, PIN rejection, successful unlock, and updated player data.
4. State offline attendance and eligibility history with code/database evidence rather than performing them.
5. Finish with implemented/external-evidence/not-found scope.

## Failure recovery matrix

| Failure | What to do | What to say |
|---|---|---|
| Firebase login unavailable | Show prerecorded login proof + backend tests/code | “The external identity dependency is unavailable; here is the exact verified boundary and prior evidence.” |
| Backend unreachable | Check safe status/log; switch to code trace | “The client cannot persist without Django; I will trace the request and show automated evidence.” |
| Wrong API host on physical phone | Use emulator or reachable LAN host configured in advance | Do not change secrets live or imply mock data is live |
| Supabase photo upload unavailable | Show validated endpoint/code/tests and continue | “The workflow is implemented, but object upload requires configured Supabase credentials; core relational data remains Django-owned.” |
| Push not visible | Open the persisted inbox and show backend notification evidence | “Inbox persistence and receive handlers are implemented; this device’s remote transport still requires valid Firebase/APNs configuration.” |
| Offline batch does not replay quickly | Restore network, invoke documented sync path, inspect queue safely | Do not resubmit repeatedly and create ambiguous last-write state |
| PIN locked | Switch to a prepared second player/account | Explain five failures/15-minute lock as designed behavior |
| Demo mutation already exists | Use a timestamped note/title or restore snapshot | Keep actions deterministic and reversible |

## Questions to invite through the demo

- “Would you like me to trace the assessment request from button to model?”
- “Would you like to see where the backend rejects a cross-club ID?”
- “Would you like to see the outbox schema and replay order?”
- “Would you like to see the guardian unlock token binding?”

## What not to do

- Do not open local `.env` or service-account files.
- Do not claim a push reached a physical device unless it is visibly demonstrated; the persistent inbox is separate evidence.
- Do not show mock mode while claiming database integration.
- Do not call deterministic averages AI.
- Do not claim grades, scouting, or match statistics.
- Do not use a real child’s personal or health data.
- Do not quote a stale test count; use the final verified command output.
- Do not hide known limitations if the panel asks.
