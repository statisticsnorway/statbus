---
id: STATBUS-146
title: >-
  env-override-footgun: POSTGRES_APP_DB set in process env silently ignored —
  migrate acts on a different database than the operator named
status: To Do
assignee: []
created_date: '2026-07-08 14:16'
updated_date: '2026-07-08 14:24'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-07-08 14:21
---
RESOLUTION MAP + VERDICT (mechanic, 2026-07-08).

**ROOT CAUSE — single upstream clobber, not split-brain.**

`cli/cmd/migrate.go:61-107` `runMigrateUp` (the `RunE` for `./sb migrate up`) runs on EVERY invocation, `--target` passed or not (cobra sets `migrateUpTarget` default `"dev"` at `cli/cmd/migrate.go:164`, so the `if migrateUpTarget == ""` guard at line 63 never actually fires — dead code, always resolves 'dev'):
```
dbName, err := migrate.ResolveTargetDB(projDir, migrateUpTarget)   // :66
os.Setenv("POSTGRES_APP_DB", dbName)                               // :73
os.Setenv("PGDATABASE", dbName)                                    // :74
```
`migrate.ResolveTargetDB` (`cli/internal/migrate/migrate.go:1304-1332`) reads `POSTGRES_APP_DB` **exclusively from the `.env` FILE** via `dotenv.Load` — process env is never consulted here at all. So `runMigrateUp` unconditionally overwrites the operator's exported `POSTGRES_APP_DB`/`PGDATABASE` with the `.env` file's value, in the CURRENT PROCESS, BEFORE `migrate.Up()` is ever called. `migrate.Redo` (`migrate.go:1800-1832`, via `migrateRedoCmd` at `cli/cmd/migrate.go:133-160`) does the identical clobber for `./sb migrate redo`.

**Every downstream resolution site is individually correct (env-first) but all read the SAME already-clobbered value — hence no split-brain:**
- `PsqlCommand` (`migrate.go:82-119`, docker branch :83-107 / host branch :110-118) — `PGDATABASE` (raw process env) > `getOr(POSTGRES_APP_DB)` (env > .env > default). Correct precedence, wrong input.
- `psqlEnv` (`migrate.go:183-236`, host-psql env builder) — same precedence, same caveat.
- `advisoryLockConnStr` (`migrate.go:692-733`, pgx conn string for the migrate advisory lock) — only checks `POSTGRES_APP_DB` (env-first, no PGDATABASE) — same caveat.
- `listAppliedVersions` (`migrate.go:589-616`) — delegates to `runPsql`→`PsqlCommand`, inherits its (clobbered) resolution.
- `maybeRebuildTestTemplate` (`migrate.go:1073-1082`) and `currentMigrationTarget` (`migrate.go:1715-1731`) both read `POSTGRES_APP_DB`/`PGDATABASE` straight from process env post-clobber; `currentMigrationTarget`'s own comment (:1710-1711) says outright: 'PGDATABASE is set by the caller (the cobra migrate up/redo command) after ResolveTargetDB' — the clobber is documented/intentional for the `--target` feature, just not gated on `--target` actually being requested.

**Not implicated (internal orchestration, correctly scoped):** `cli/cmd/seed_verify.go:385-402` `migrateNamedDb` does the same clobber SHAPE but takes an explicit `dbName` param for the seed-verify pipeline — it never reads the operator's env, so it's not part of this bug. `cli/internal/config/config.go:309-329` (`loadOrGenerateConfig`, `POSTGRES_APP_DB` default `statbus_<slotCode>`) + `:679` (example .env.config writer) only explain WHY `.env`'s `POSTGRES_APP_DB=statbus_local` — they run at `config generate` time, not migrate time, and aren't part of the live resolution chain.

**READ-ONLY REPRODUCTION** (`.env`'s `POSTGRES_APP_DB=statbus_local`; confirmed `statbus_floor_test` does not exist as a database — `\l` returns zero matches):
```
POSTGRES_APP_DB=statbus_floor_test ./sb migrate up --to 20260703210000 --verbose
  → All migrations are up to date
  → Running post-restore fixups...
```
No 'database "statbus_floor_test" does not exist' error anywhere in output. If the operator's override had reached ANY connection attempt (advisory lock, psql bookkeeping query, or the actual migration psql calls), it would have failed loudly since that database provably doesn't exist. The clean, silent success proves the override never reached a single connection — consistent with one upstream clobber erasing it before any resolution site saw it, not with different sites disagreeing on where to connect.

**VERDICT: SET-BUT-IGNORED (single wrong source), NOT split-brain.** There is exactly one divergence point (`runMigrateUp`/`Redo`'s unconditional `ResolveTargetDB` + `Setenv`, always reading `.env` regardless of prior process env). Every downstream site then agrees with every other downstream site (all correctly implement env-first) — they just all agree on the wrong database, because the true operator value was already erased one level up. The architect's split-brain hypothesis (different internal sites resolving to different DBs within one run) is NOT what's happening — it's simpler and arguably worse in a different way: the override is silently discarded even for callers who never asked for `--target` at all.

**Implication for the fix ruling:** the fail-fast check belongs in `runMigrateUp`/`Redo`, comparing the operator's pre-existing `os.LookupEnv("POSTGRES_APP_DB")`/`PGDATABASE` (captured at lines 71-72 / 1817-1818, BEFORE the Setenv) against the `ResolveTargetDB` result — if they differ and `--target` wasn't explicitly passed (or even if it was, per the ticket's 'REFUSE-LOUDLY' doctrine), refuse with a message naming both databases, rather than silently overwriting.
---

author: architect
created: 2026-07-08 14:24
---
FIX RULED (architect, 2026-07-08; the mechanic's map comment #1 verified first-hand — single upstream clobber CONFIRMED, the description's split-brain hypothesis is DEAD: downstream sites agree because they all read the already-clobbered env).

(a) REFUSE-ON-DIVERGENCE, not honor: pre-existing env value == resolved target → proceed silently (keeps the documented `eval $(./sb config show --postgres)` workflow friction-free); differs → fail fast naming BOTH databases and BOTH remedies (unset the var, or select a config database with --target). Refuse over honor because migrate is destructive-class, config+--target is the single supported selector, honoring would bless an undocumented side-door bypassing ResolveTargetDB's validation, and the harness need is gone (145 #4 self-provisioning). SAFETY-CHECKED: the daemon's systemd unit sets only PATH (ops/statbus-upgrade.service:50) and no product path exports these vars before shelling `sb migrate up` — refuse-on-divergence cannot trip boot-migrate; a production box that DID carry a diverging export in the daemon env should stop loudly.

(b) The dead --target guard (cmd/migrate.go:63-65) is cleaned in the same diff (clean-break; builder verifies the cobra flag default genuinely makes it dead first).

(c) BUILDER: mechanic, with one refinement — there are FOUR clobber sites, not two: cmd/migrate.go:73-74, internal/migrate/migrate.go:282-283, :1828-1829 (Redo), cmd/seed_verify.go:392-393 (apparently WITHOUT a restore defer — confirm in context). Consolidate into ONE shared helper (capture pre-existing → divergence-refuse → Setenv → return restore closure); all four callers use it so the copies can never drift and the refuse covers Up/Redo/seed-verify uniformly. Pinning test per AC#3: divergence → loud failure + correct exit code + message names both databases; set-and-equal → proceeds. Architect reviews the diff before commit.
---
<!-- COMMENTS:END -->
