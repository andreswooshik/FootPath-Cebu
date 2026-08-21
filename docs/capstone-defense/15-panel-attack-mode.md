# Panel Attack Mode

These 30 hostile questions are designed to expose overclaiming. Answer directly, give the mechanism, cite evidence, and concede the exact limitation.

### A1. “Your README says Firestore. Did you even build what you proposed?”

The current code uses Django ORM, not Firestore. The root README has now been reconciled to that delivered architecture; ADR 0001 preserves historical decision context, and executable repositories make Django the source of truth. The remaining documented specification mismatch is the rating scale, which requires stakeholder approval rather than silent rewriting.

### A2. “Where exactly is your AI?”

There is no AI in the current executable source. Human-entered ratings and ORM averages are deterministic. We treat AI as absent/future scope instead of misrepresenting analytics as machine learning.

### A3. “Then what is technically impressive about this?”

The strongest engineering is layered authorization and resilience: Firebase identity mapped to Django role/club/object rules, a hashed and throttled guardian PIN with signed temporary unlocks, transactional audit/history, a user-scoped ordered attendance outbox/safe-read cache, and durable notification history independent of best-effort push transport.

### A4. “You claim six roles, but I only see three mobile screens.”

Six roles exist server-side. Coach, player, and guardian have dedicated Flutter portals; coordinator and school staff use the Django portal, and admin uses Django admin/admin APIs. Mobile has only a generic placeholder for those non-mobile roles.

### A5. “Can I create an account from the app?”

No. There is no public registration. Super Admin creates Clubs and their single Coordinators; Coordinators then provision normal accounts only in their own Club.

### A6. “Firebase already has authentication. Why do you need Django users?”

Firebase proves identity, but it does not hold the implemented academy relationships: roles, clubs, guardian links, profiles, and object ownership. Django maps UID to those domain records and makes every access decision.

### A7. “If I modify Flutter and send another club’s player ID, what stops me?”

Flutter checks do not stop a modified client; Django does. Endpoints retrieve players/sessions through same-club querysets and derive actors/club from the authenticated local user, returning forbidden/not found for cross-club IDs.

### A8. “Your guardian PIN is only four digits. Isn’t that insecure?”

It is not the primary login. The guardian must already have a valid Firebase identity and active GuardianLink. PIN guessing is hashed, counted transactionally, locked after five failures for 15 minutes, and success grants only a ten-minute user/player-bound token. A longer PIN option or device biometrics could further improve it.

### A9. “Why invent a PIN if the guardian is already authenticated?”

It adds household-level privacy when a signed-in device may be shared and requires knowledge associated with the selected child before sensitive details are revealed. It is defense in depth, not a replacement for authentication.

### A10. “Can a guardian reuse the token for another child?”

No by design. The signed payload binds both user and player, and the endpoint rechecks the requested player plus current GuardianLink. A different ID fails the binding/link checks.

### A11. “You say Supabase. Where are your RLS policies?”

RLS is not used because Flutter never queries Supabase. Django is the sole data gateway and enforces authorization before ORM access. Supabase is optional PostgreSQL/private storage infrastructure only.

### A12. “Is your data encrypted?”

Passwords/PINs are hashed, production transport is configured for HTTPS, and storage/database infrastructure can encrypt at rest, but the repository alone does not prove every production provider setting. We should not claim application-level encryption of every model field.

### A13. “Are real children’s health records safe in this capstone?”

The code restricts injury reads/writes and minimizes guardian selector data, but production use also requires consent, retention/deletion policy, incident response, access audits, and legal/privacy review. Those governance controls are not complete repository evidence, so demo data should be synthetic.

### A14. “You advertise notifications. Show me the inbox.”

Open the role dashboard bell and `NotificationInboxScreen`. Django stores current-user `NotificationRecord` rows and exposes list/unread/read APIs; Flutter renders unread state and handles foreground pushes. A row tap, foreground **View**, or opened/initial push routes known trusted events to the authorized Schedule, Player/linked-child Profile, or Eligibility destination behind existing privacy gates; unknown events or profile failures safely focus the inbox. Actual physical-device delivery still depends on configured Firebase/APNs and is evidence separate from inbox persistence.

### A15. “Your demo works because it is all fake data, correct?”

Debug does default to mock repositories unless explicitly disabled. A valid integration demo must run with `USE_MOCK=false`, show the configured Django endpoint, and prove a mutation through a second role or server record. We will state the mode visibly.

### A16. “What happens without internet?”

Only attendance writes have queued/replayed offline mutation support. A network-failed complete batch is queued and later replayed. Eligible successful authenticated GETs also have a 24-hour owner-scoped cache used only for connectivity failures; protected unlock reads and HTTP errors are excluded. Other writes need connectivity, so the app is not fully offline.

### A17. “How do you resolve two offline coaches editing the same attendance?”

There is no sophisticated merge. Complete batches replay in order and later server writes win. That simple policy is explainable but can overwrite concurrent work; production improvement would add server versions, conflict detection, and a review screen.

### A18. “Could queued data from Coach A be sent by Coach B?”

The outbox stores the Firebase owner UID and sync loads records only for the current owner. Shared-device account changes therefore do not automatically replay another owner’s items.

### A19. “Your requirements say ratings are 1–10, but the app shows 0–99. Which is correct?”

The executable contract is 0–99 across Flutter and DRF. The requirements document is inconsistent and must be reconciled with stakeholder approval. We will not claim both scales are correct.

### A20. “Where is the assessment history that proves improvement over time?”

It is not implemented. The profile stores current ratings/notes and progress aggregates attendance; a proper trend feature needs an append-only timestamped assessment model.

### A21. “You call it school eligibility. Where are the grades?”

No grades are stored. The system stores only eligibility status and a status-change history. UI labels implying grades should be corrected to avoid a false privacy/feature claim.

### A22. “Can training end before it starts?”

No through supported write paths. `TrainingSession.validate_time_window` accepts/normalizes the supported 12-hour strings, requires start and end together, and rejects start greater than or equal to end. The serializer maps this validation for API input, and model `clean`/`save` cover ORM/admin paths. Native database time fields could still strengthen engine-level typing.

### A23. “Can database writes bypass your 0–99 serializer?”

Yes, admin/direct ORM paths can bypass serializer-only range checks because comprehensive DB check constraints were not found. Defense in depth requires model validators and database constraints.

### A24. “Show me a real integrity bug you found and fixed.”

Earlier admin/seed paths could leave a Player without the required Club/profile aggregate. Every executable Player path now uses one transactional `provision_player` service or a safe idempotent seed equivalent. It requires an active Club, creates exactly one profile, validates optional same-Club Guardian linkage, and compensates a newly created Firebase identity on failure. Generic user creation excludes Player.

### A25. “Does your administrator really see all progress?”

Yes. `SquadProgressView` begins with all profiles/attendance and applies the Club filter only for Coach. Super Admin keeps the all-Club query; other roles are rejected. Regression coverage verifies both branches.

### A26. “How many tests passed?”

On 2026-08-21, Flutter analysis was clean, the full Flutter suite passed 240/240, and the full Django suite passed 241/241. Retain the command output and do not reuse these numbers after tests are added or removed.

### A27. “Can the Coach really upload photos from Flutter?”

Yes for a same-Club Player. Flutter uses `image_picker`, a photo use case/controller, and authenticated multipart upload; Django repeats role, Club, size, MIME, and signature checks. The object upload requires configured Supabase credentials, and the service-role key stays server-side. Without valid storage configuration the UI reports the failure and retains its avatar fallback.

### A28. “Is this production-ready?”

Not yet as an evidenced live service. It now has Docker/Compose, Gunicorn/WhiteNoise, health/readiness checks, structured logs, optional Sentry, CI container validation, backup/restore scripts, and an operations runbook. The repository does not prove an active deployment, alert exercise, scheduled backup, completed restore drill, or privacy-governance approval.

### A29. “Why should we trust an `AuditLog` inside the same database?”

It improves accountability and debugging but is not immutable or independently tamper-evident. Higher assurance would restrict deletion/admin access, export to append-only storage, sign events, and monitor anomalies.

### A30. “If you had one week, what would you fix rather than add?”

First retain the completed suite outputs and obtain live-device/external-service evidence, reconcile the remaining rating requirements, add versioned assessment history and remaining database constraints, then execute deployment monitoring, scheduled-backup, restore-drill, and privacy-governance checklists. Reliability and truthful scope are more valuable than another feature.

## Attack response discipline

1. Do not start with “I think.” State the verified result.
2. Do not blame a teammate or framework.
3. Never rename a missing feature.
4. Distinguish risk, exploitability, and remediation.
5. Cite the server path that enforces security.
6. Distinguish a test file, a defined CI job, a completed run, and production evidence.
7. When a defect is real, say so and give the smallest correct fix.
