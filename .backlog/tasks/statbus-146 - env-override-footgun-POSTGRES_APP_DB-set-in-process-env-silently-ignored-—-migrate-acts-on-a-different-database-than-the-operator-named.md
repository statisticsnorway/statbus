---
id: STATBUS-146
title: >-
  env-override-footgun: POSTGRES_APP_DB set in process env silently ignored —
  migrate acts on a different database than the operator named
status: To Do
assignee: []
created_date: '2026-07-08 14:16'
labels:
  - product
  - migrate
  - operator-ux
  - fail-fast
  - investigation
dependencies: []
references:
  - STATBUS-145
  - cli/internal/migrate/migrate.go
  - cli/internal/config/config.go
priority: medium
ordinal: 147000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a knob the operator sets either works or refuses loudly — `./sb` never quietly acts on a different database than the one the operator named.
> BENEFIT: kills a wrong-place-write footgun class before it bites a real box: in the Albania frame, an operator who sets an env override and gets "all migrations up to date" against a DIFFERENT database has been actively misled by the tool.
> STAGE: Stage 1 (operator-facing correctness).
> COMPLEXITY: mechanic-investigable, then a small fix — but the investigation must come first (see below: the observed behavior contradicts the naive read of the code, which suggests split-brain, not simple precedence).
> DEPENDS ON: nothing.

OBSERVED (tester, 2026-07-08, during the STATBUS-145 floor-harness for-the-record run): `POSTGRES_APP_DB=statbus_floor_test ./sb migrate up --to 20260703210000` SILENTLY targeted the dev database and reported "all migrations up to date" — against the WRONG database. No harm that run (dev was at HEAD, nothing applied), but the shape is the wrong-place-write class: an env-looking knob accepted without effect.

WHY THIS NEEDS INVESTIGATION BEFORE A FIX (architect code-read, 2026-07-08): the naive explanation "config file wins over process env" does NOT match the code. migrate.go's `getOr` (:90-96) checks `os.Getenv(key)` FIRST, then the .env file — so on that path the env override SHOULD have won. Candidate real mechanisms, to be pinned by the mechanic: (a) SPLIT-BRAIN — the migrate bookkeeping/HasPending reads resolve the database via a different path (config-loaded .env, or the PGDATABASE-shadowing noted at migrate.go:216-223 "the appended PGDATABASE=<POSTGRES_APP_DB> shadows any pre-existing") while the psql exec path resolves via env-first getOr — meaning parts of one migrate run could target DIFFERENT databases, which is strictly worse than the reported symptom; (b) the docker-exec path connects inside the db container where host process env may be irrelevant to some legs; (c) something else. MAP EVERY RESOLUTION SITE FIRST (PsqlCommand :90-107, the :216-223 site, psqlEnv, config.go:316/679, any pgx dial paths), then fix.

FIX DIRECTION (architect, for ratification after the map): ONE precedence, applied identically at every site, plus REFUSE-LOUDLY on set-but-ignored — if a target-selection env var (POSTGRES_APP_DB, PGDATABASE) is present in the process env but the resolution deliberately does not honor it on some path, the command must fail fast with an actionable message ("POSTGRES_APP_DB is set but ./sb migrate targets the configured database <X>; unset it or use <the supported affordance>"), never proceed quietly. The fail-fast doctrine: a set-but-ignored knob must either work or refuse. Note the STATBUS-145 empirical floor test no longer needs this affordance (it self-provisions in-process per 145 comment #4), so this ticket is pure operator-protection, not a harness dependency.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Resolution map: every site that resolves the target database for ./sb migrate/psql commands, with file:line and its precedence (env vs .env vs default), including whether one command can resolve DIFFERENTLY at different internal sites (the split-brain question)
- [ ] #2 One precedence ruled and applied identically at every site; set-but-ignored target-selection env vars REFUSE loudly with an actionable message — no silent divergence between named target and acted-on target
- [ ] #3 A test pins the refuse-loudly behavior (env set + config divergence → loud failure, correct exit code, message names both databases)
<!-- AC:END -->
