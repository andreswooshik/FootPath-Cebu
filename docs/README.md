# FootPath Cebu documentation

Project documentation is grouped by purpose so the repository root stays
focused on source code and deployment entry points.

## Start here

- [Setup](SETUP.md) — local Django, Flutter, Firebase, and Supabase setup.
- [Requirements](REQUIREMENTS.md) — product roles and feature requirements.
- [Production operations](PRODUCTION-OPERATIONS.md) — deployment and recovery.
- [System architecture](capstone-defense/02-system-architecture.md) — client,
  API, authentication, and persistence boundaries.

## Documentation areas

- `audit/` — dated code-quality, feature, and security assessments.
- `capstone-defense/` — defense notes, diagrams, tracing, and generated artifacts.
- `consultation/` — consultation records.
- `decisions/` — architecture decision records (ADRs).
- `tools/` — utilities used to build or inspect documentation artifacts.
- `updates/` — dated project status updates.

Generated working files belong in the ignored root `tmp/` or `output/`
directories. Only reviewed deliverables should be placed under `docs/`.
