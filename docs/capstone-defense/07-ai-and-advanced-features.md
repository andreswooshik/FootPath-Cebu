# AI and Advanced Features

## AI/ML finding

No artificial intelligence or machine-learning implementation was found in the executable Flutter or Django source. There are no model files, inference calls, recommendation engines, training pipelines, computer-vision dependencies, predictive endpoints, or AI SDK integrations.

Therefore the defensible answer is:

> FootPath Cebu does not currently use AI. Its player ratings and summaries are deterministic records and arithmetic aggregates entered by authorized humans. We will not mislabel filtering, averages, or rule-based access as artificial intelligence.

If an earlier proposal claimed AI, describe it as future scope unless the team separately implements and validates it.

## What is advanced but not AI

### 1. Offline-first attendance writes

The mobile app decorates the live attendance repository. On a network-specific failure, it queues the complete batch in user-scoped sqflite storage and later replays batches sequentially. This is distributed-state/resilience engineering, not AI.

### 2. Dual-system identity provisioning

The backend provisions Firebase identities and Django domain records with compensation. If database persistence fails after a new Firebase identity is created, it attempts to remove that identity. This reduces cross-system orphans.

### 3. Defense-in-depth guardian privacy

Guardian access combines Firebase identity, local role, a current guardian-player link, a hashed/throttled household PIN, and a time-limited signed user/player token.

### 4. Event-driven side effects

Eligibility signals create history and audit records. Notifications are scheduled with `transaction.on_commit` so users are not notified about rolled-back writes.

### 5. Role-aware dependency composition

Flutter’s domain interfaces allow mock and live adapters, while the attendance adapter adds local resilience through composition.

### 6. Relational aggregation

The progress endpoint calculates deterministic attendance counts/averages and returns player progress summaries. An aggregate is analytics, not machine learning.

## Scouting finding

No `SCOUT` role, scouting report, recruitment view, talent recommendation, or external scout-access flow was found. The dispute/flag flow records concerns raised by a coach; it must not be renamed “scouting.”

## Sensible future AI extension

A future, separately approved feature could identify development trends from historical assessments, but the present schema first needs timestamped assessment history. A responsible extension would require:

1. a defined decision-support problem and baseline;
2. sufficient lawful, representative historical data;
3. consent and child-data safeguards;
4. explainable outputs and human review;
5. fairness/error evaluation across age tiers and clubs;
6. explicit separation from eligibility or punitive decisions;
7. monitoring, rollback, and a non-AI fallback.

Do not promise this as current capability.

## Likely panel trap

**Question:** “Where is the AI in your system?”

**Answer:** “There is none in the current executable repository. Our advanced features are offline synchronization, layered authorization, event-driven notification/history, and deterministic progress aggregation. We prefer an accurate boundary over calling averages or filters AI.”

## Required AI defense answers

**Why does the project need AI?** It does not need AI to satisfy the currently implemented operational objective. Any future trend-support feature would need a validated problem and historical data before selecting a model.

**Can the system work without AI?** Yes. Every current workflow—authentication, profile, schedule, attendance, eligibility, injuries, disputes, privacy, and provisioning—is deterministic and independent of AI.

**How would you prevent blind trust in future recommendations?** Label outputs as decision support, show the supporting observations/confidence/limitations, retain a human coach decision, prohibit automated eligibility/punitive decisions, evaluate errors/fairness, log model/version inputs, and provide a non-AI fallback.
