---
id: doc-021
title: Recovery escalation — the per-failure-class allowance table (STATBUS-046)
type: specification
created_date: '2026-07-01 13:11'
updated_date: '2026-07-02 18:24'
tags:
  - upgrade
  - recovery
  - escalation
  - STATBUS-046
  - architecture
---
# Recovery escalation — the per-failure-class allowance table (STATBUS-046)

**Status:** design for King ratification. Architect, 2026-07-01 (step-list walk added 2026-07-02). The "no loop-forever, no
rollback-by-exhaustion" mechanism for the **at-target forward path** — recovery-core unit 3
(after STATBUS-110 read-only window + STATBUS-109 backoff; before STATBUS-111 UX). Framework
already King-ratified (2026-06-13); this fills the **ratification-remaining** pieces: the allowance
TABLE, the attempt budget + same-step-twice rule, and the park-marker columns.

## The problem
- **rune: 10,229 restarts.** systemd `StartLimitBurst=5 / StartLimitIntervalSec=600` **cannot** bound a `RestartSec=30` + `WatchdogSec=120` loop: ~160 s/cycle ⇒ ~4 starts/600 s < 5, so the burst never trips. **The bound must be an UPGRADE-ATTEMPT budget owned by recovery, not a unit-restart budget.**
- **King's directive (2026-06-13):** each error class needs its own handling. Waiting for something that *gets* ready deserves leniency; something that will *never* get ready must fail fast + actionable; looping forever is not an option — it eventually exhausts disk *on top of* the original problem.
- **The at-target constraint (STATBUS-039):** an at-target box must not roll back — past the maintenance-off commit point, API integrators may have written data the snapshot predates (the read-only window is an accident-guard, not a hard lock, so a deliberate integrator write is possible). So when forward keeps failing *at-target*, the only choices are loop-forever (rejected) or **PARK** — this ticket's answer.

## The unified mechanism (King-ratified): one named allowance per (step, error, context)
Every failure carries a **named allowance** derived from `(step, error, context)`:
- **A — READINESS** (will become ready): a named, per-step **time allowance, waited IN PLACE** (not attempt-counted), **size-scaled** where the wait scales with data. *In place* = one attempt absorbs the whole legitimate wait; a crash-retry must never re-pay the pipeline to reach the same wait.
- **B — DETERMINISTIC** (never succeeds by retrying): allowance **= 0 → PARK** on first occurrence with the named actionable reason. "Never gets ready" ≡ allowance 0.
- **C — RESOURCE EXHAUSTION** (retrying amplifies it): allowance **= 0 → PARK**; the attempt budget itself is what stops the loop from *causing* this class.
- **D — CRASH/KILL mid-attempt** (watchdog SIGABRT / OOM / reboot — the loop driver): counts against the **attempt budget** (below).

**Context is load-bearing** (the registry-404 example): during CI publication (image still uploading) → a *publication-wait* allowance (minutes, class A); at an at-target *resume* (the image demonstrably existed — containers ran it) → allowance **0** (class B). Same error text, different `(step, context)` → different allowance. So classification is never by error text alone.

## The allowance table (the diagram rows — grounded in the current waits)
Values are **proposals, reconcilable at build/arc** (as with STATBUS-109); the **shape is fixed**.

| Pipeline step | Failure mode | Class | Allowance (proposed) |
|---|---|---|---|
| config generate | template / config error | B | **0 → park** ("config generate failed: <err>") |
| docker pull | registry unreachable / timeout | A | in-place backoff (109-style), ~few min |
| docker pull | 404 manifest-unknown, **during publication** | A | publication-wait ≈ image-build worst case (min; precedent `markImagesFailed` grace) |
| docker pull | 404 manifest-unknown, **at at-target resume** (image existed) | B | **0 → park** ("target image not published — external re-publish required") |
| docker pull | disk full | C | **0 → park** ("disk full during image pull") |
| db up / `waitForDBHealth` | db starting / WAL replay | A | in-place, **size-scaled** (current 60 s baseline `exec.go:1022/1057`; scale to volume worst case — precedent `MigrateUpTimeout`=30 m; Norway 32 GB ⇒ many min) |
| reconnect | db mid-restart (conn racing) | A | in-place backoff (109 `db-unreachable`: 1s→30s cap, ~5 min budget) |
| `migrate up` (no-op at-target) | conn error | A | 109 `db-unreachable` backoff (~5 min) |
| `migrate up` | SQL / constraint / "relation already exists" | B | **0 → park** ("migration <v> failed deterministically: <err>") |
| start services (step 11) | daemon hiccup / compose transient | A | in-place short retry (~1–2 min) |
| start services | compose / config error | B | **0 → park** |
| start services | disk | C | **0 → park** |
| app health | warmup (still starting) | A | in-place (current `healthCheck` retries×interval + `waitForRestReady` `RestReadyTimeout`; sized to warmup worst case) |
| app health | persistent past warmup (can't serve) | B | **0 → park** ("app cannot serve at <version> past warmup") |
| maintenance-off / archive / completion write | conn error | A | 109 `db-unreachable` backoff |
| maintenance-off / archive / completion write | constraint / chk violation | B | **0 → park** (existing `markPgInvariantTerminal` fail-fast precedent) |
| **ANY step** | crash / kill (watchdog SIGABRT, OOM, reboot) | D | counts against the **attempt budget**; same-step-twice → park; else remaining budget |

## The attempt budget (class D + the loop bound)
- `recovery_attempts` counter, **incremented at attempt START** so a crash self-counts (no post-hoc bookkeeping needed on a dead process).
- **Budget = 3** (proposal).
- The **dying step is recorded on the flag** (extends the persisted-flag pattern already carrying `Phase`, `BackupPath`).
- **Two consecutive deaths at the SAME step → PARK immediately** (same-step-twice = deterministic-hang evidence = zero allowance per class B). Different steps / reboot = environmental → the **remaining budget** applies.
- Sits **in front of** systemd's StartLimit: the recovery budget is the real bound; StartLimit remains only a coarse daemon-start backstop.

## THE STEP LIST — the per-step walk (the concrete pipeline the table compresses)

*Added 2026-07-02 to answer the King's ratification gap: the table above names abstract "pipeline steps," but to judge whether each is transient or deterministic — and to see exactly where the attempt budget's coverage begins and ends — you need the ACTUAL ordered steps as they run in code. Grounded first-hand against master HEAD, `cli/internal/upgrade/service.go`. For each step: **(a)** what runs, **(b)** which failure classes can occur with a concrete example error, **(c)** what a crash/kill (class D) at that step means for recovery, **(d)** inside or outside the attempt-budget's coverage. The four phases are divided by two hard boundaries — the **flag write** (an upgrade takes ownership) and the **binary swap** (the point of no return).*

### The budget boundary in one sentence (read this first)
The attempt budget counts **crash-resumes of a flag-owned upgrade, and only those.** It **starts counting at the flag write** (`writeUpgradeFlag`, service.go:4140 — the first moment a crash leaves a resumable on-disk marker) and **stops counting at the completed-state write + flag removal** (service.go:4957 / 5001 — after which a crash is a no-op the next boot skips). Everything *before* the flag (pre-flight) and everything *after* the flag removal (post-completion cleanup) is **outside** the budget — the per-step reasons are below.

### Phase 0 — Pre-flight (OUTSIDE the budget: no flag yet)
Runs at the top of `executeUpgrade`, BEFORE `writeUpgradeFlag`. The row is already `in_progress` (the scheduler claimed it) but **nothing destructive has run and no flag exists.**

| # | step (file:line) | (a) what runs | (b) failure classes + example | (c) a crash here | (d) budget |
|---|---|---|---|---|---|
| 0.1 | log-pointer stamp (4014) | DB write of the log path | A conn-blip (retried 4× in place) · B never (trivial write) | no flag → next boot finds nothing to resume; ground-truth handles the row, nothing to undo | OUTSIDE |
| 0.2 | downgrade / manifest / platform / disk / signature checks (4074–4129) | read-only preconditions | B deterministic (older version, no binary for platform, bad signature → fail fast, actionable) · C disk < 5 GB (fail fast) | same — no flag, nothing destructive done | OUTSIDE |

These are the "reject cleanly before touching anything" gates. A failure here is **B/C → immediate actionable fail** (never a retry, never a park): the upgrade simply doesn't start. A crash here is invisible to recovery.

### Phase 1 — Pre-swap destructive (flag = PreSwap; a crash here ROLLS BACK, it does not park)
From `writeUpgradeFlag` to the binary swap. The flag now exists (Phase = PreSwap). **The DB is snapshotted while stopped, so a rollback restores a byte-consistent pre-upgrade state and loses nothing** (STATBUS-110's read-only window + the stopped-DB snapshot). A crash in this phase is recovered by `recoverFromFlag`'s PreSwap branch → **one-shot rollback**, never a forward loop.

| # | step (file:line) | (a) what runs | (b) failure classes + example | (c) a crash here | (d) budget |
|---|---|---|---|---|---|
| 1.1 | **flag write** (4140) | filesystem flag + flock | B can't write the flag → fail fast | — | **first step counted** |
| 1.2 | warm-up image pull (4193) | `docker … pull` target images | A registry slow/unreachable (retryable) · C disk-full · B 404 image-never-published (pre-destructive → fail fast, nothing to undo) | PreSwap flag → rollback (DB untouched) | counted (rollback-resume) |
| 1.3 | record backup_path (4241) | DB write | A conn-blip (ping + reconnect already wraps it) | PreSwap → rollback | counted |
| 1.4 | engage read-only window (4263) | `ALTER DATABASE … read_only=on` | A conn-blip (best-effort, logged) | PreSwap → rollback | counted |
| 1.5 | maintenance ON + stop app/worker/rest (4286 / 4292) | filesystem flag + `docker … stop` | A compose transient (aborts, restarts services, clears window) · B compose config error | PreSwap → rollback | counted |
| 1.6 | stop DB (4312) | `docker … stop db` | A daemon hiccup · B compose error | PreSwap → rollback | counted |
| 1.7 | **backup / snapshot** (4342 `backupDatabase`) | rsync of the STOPPED volume | A slow (size-scaled, in-place; watchdog-covered) · C disk-full → park · B rsync error | PreSwap → rollback with empty backup path (nothing finalised → identity-keyed restore is a safe no-op) | counted |
| 1.8 | git fetch target (4362) | `git fetch origin <sha>`, 5-min WALL-CLOCK today | A stall / slow transfer (→ STATBUS-109's stall-detected fetch; **the wall-clock deadline is exactly the bug 109 fixes**) · B ref absent at remote | PreSwap → rollback | counted |

**The whole of Phase 1 is data-safe to roll back.** So a detected Phase-1 crash-loop (same-step-twice, or exhausted budget) terminates in **roll back** (data-safe), NOT park. Park is a Phase-3-only concept.

### Phase 2 — The swap boundary (the point of no return)
| # | step (file:line) | (a) what runs | (c) a crash here | (d) budget |
|---|---|---|---|---|
| 2.1 | binary swap (4426 `replaceBinaryOnDisk`) | new `./sb` on disk, `./sb.old` kept for rollback | before the flag is re-stamped → recovery classifies binary/migration state and either rolls forward or restores the old binary | counted |
| 2.2 | **stamp flag PostSwap** (4452 `updateFlagPostSwap`) | flag Phase = PostSwap + finalised backup path | **the direction pivot**: past here, ground-truth reads "at-or-past target" and recovery goes FORWARD | counted |
| 2.3 | hand off — exit-42 / re-exec (4464 / 4470) | new process takes over on the new binary | next process sees the PostSwap flag → `resumePostSwap` → re-enters `applyPostSwap` | counted (this resume IS the attempt increment) |

### Phase 3 — Post-swap forward (flag = PostSwap/Resuming; INSIDE the budget; exhaust → PARK)
`applyPostSwap`, re-runnable from the top on every resume. **This is where the rune loop lived** (10,229 restarts). Ground truth here is at-target → **forward only, rollback forbidden** (integrators may have written past the maintenance-off point) → the ONLY loop-bounds are the class-A in-place allowances and, for crashes, **the attempt budget → PARK**.

| # | step (file:line) | (a) what runs | (b) failure classes + example | (c) a crash here (class D) |
|---|---|---|---|---|
| 3.1 | config generate (4651) | `./sb config generate` | B template / config error → park on first | resume re-runs from 3.1; same-step-twice → park |
| 3.2 | image pull (4665) | `docker … pull` | A registry slow (in-place) · C disk → park · B 404-at-resume (image existed, now gone → park) | resume from 3.1 |
| 3.3 | DB up + health (4677 / 4691 `waitForDBHealth`) | `docker … up db` + health wait | A starting / WAL-replay (in-place, SIZE-SCALED) · B image absent → park | resume from 3.1 |
| 3.4 | reconnect (4731) | pgx dial, 5-min bounded | A db mid-restart (109 `db-unreachable` backoff) | resume from 3.1 |
| 3.5 | **migrate up** (4842) | `./sb migrate up`, 30-min bounded | A conn-blip (backoff) · **B "relation already exists" / constraint → park on first (deterministic)** | resume from 3.1; a 2nd death at migrate = deterministic-hang → park early |
| 3.6 | start services (4876, step 11) | `docker … up app worker rest proxy` | A daemon hiccup (short in-place) · B compose / config error · C disk | resume from 3.1 |
| 3.7 | health check (4900) | REST / app health, retries × interval | A warmup (in-place) · B can't-serve-past-warmup → park | resume from 3.1 |

**Every crash in Phase 3 increments `recovery_attempts` and re-enters at 3.1.** Budget = 3; a second consecutive death at the SAME step (e.g. migrate twice) → park immediately (deterministic-hang evidence); different steps / reboot → the remaining budget. On exhaust: **PARK** (at-target → can't roll back).

### Phase 4 — Completion terminal (the LAST steps counted)
| # | step (file:line) | (a) what runs | (c) a crash here | (d) budget |
|---|---|---|---|---|
| 4.1 | maintenance OFF (4911) | clear maintenance flag | recovery still sees the PostSwap flag → resumes forward (idempotent) | counted |
| 4.2 | **state='completed' UPDATE** (4957) | DB terminal write, 4× conn-retry | before it lands → still PostSwap → resume | counted |
| 4.3 | read-only OFF (4998) + **remove flag** (5001) | clear the window + delete the flag | **after the flag is gone → next boot no-ops** | **last step counted** |

### Phase 5 — Post-completion cleanup (OUTSIDE the budget: row completed, flag gone)
prune backups (5019), supersede older releases (5025), retention purge (5032), callback (5033), `runInstallFixup` (5060). All idempotent best-effort. A crash here leaves a **completed** upgrade the next boot skips — nothing to retry, nothing to park. **OUTSIDE.**

### The rollback pipeline (`rollback()`, service.go:5650) — its own steps
Reached from a Phase-1 failure or a positively-Behind Phase-3 verdict. Steps: capture container logs (5690) → stop all (5693) → restore git state (5705) → restore binary (5796) → config generate (5798) → **restore database** (5806) → start old services (5841) → DB health + reconnect (5855 / 5860) → maintenance OFF (5865) → read-only OFF (5876) → mark `rolled_back` (5889+). A crash mid-rollback is recovered (the flag survives) and the rollback re-runs idempotently (the restore is identity-keyed + idempotent) — these resumes also count against the budget (same-step-twice → the `restore-broke` human stop). Its one genuinely-terminal failure is **git-restore-fail** (5705 → 5784) → state = `failed` / `restore-broke` — a class-B "our recovery action itself broke," a human stop regardless of budget (never park-and-retry).

### So, to judge the classification per step (the King's ask)
- **Transient (class A — retry in place, not attempt-counted):** every image pull, DB-up / health wait, reconnect, and conn-blip on a DB write — these *become* ready; sized in-place, size-scaled where the wait scales with data.
- **Deterministic (class B — park / fail on first):** config error, migration "already exists" / constraint, can't-serve-past-warmup, and the pre-flight downgrade / signature / manifest gates — retrying cannot change the outcome.
- **Resource (class C — park on first):** disk-full at any pull / backup / migrate — retrying amplifies it.
- **Crash (class D — the attempt budget):** the loop driver — counted ONLY inside the flag-owned window (Phase 1 flag-write → Phase 4 flag-removal); on exhaust: **park** when at-target (Phase 3), **roll back** when data-safe (Phase 1).

## PARK-DEGRADED (replaces loop-forever)
On budget-exhaust (A/D) or a B/C failure firing once:
- The row is **PARKED** — stays `in_progress` (forward-only preserved; **rollback reachable ONLY via a positively-Behind ground-truth verdict, NEVER via exhaustion**), and gains `recovery_attempts int` + `recovery_parked_at timestamptz` + the named reason (queryable columns, no enum churn; admin UI shows *why*).
- The service **SKIPS resume** for a parked row on every boot/tick — **one loud log line; the degraded callback/siren fires ONCE**. The unit stays **alive-idle** (serving its normal loop, reachable by `NOTIFY`). No crash-loop, no journal bleed, no disk creep.
- **UN-PARK = the product's two operator actions ONLY:** (1) re-trigger the upgrade (`NOTIFY`/apply — a fresh deliberate attempt with a fresh budget), or (2) `./sb install` (a deliberate inline attempt). **Each deliberate trigger = exactly one attempt, never a loop.** The machine never resumes hammering on its own.

## Composition with the recovery core
- **STATBUS-039 (ground truth) sets DIRECTION; 046 governs only HOW LONG / HOW LOUD forward is tried before parking — never the direction.** At-target → forward (park on exhaust); positively-Behind → roll back (data-safe via 110).
- **STATBUS-110 (read-only window)** makes the *pre-completion* rollback data-safe. **046's park is the *at-target/post-completion* regime** (users + integrators live on the box; can't safely roll back) — where forward-keeps-failing must PARK, not loop and not wrong-rollback.
- **STATBUS-109 (backoff)** *is* the class-A in-place wait for the transient probes (`db-unreachable`, `commit-not-fetched`); 046 generalizes the class-A allowance per pipeline step and adds the B/C/D handling + the park terminal. 109 and 046 share the "allowance, then escalate" spine.

## Diagrams + verification
- **Update `doc/diagrams/upgrade-timeline.plantuml` (per-class routing at the failure chokepoint) + `upgrade-lifecycle.plantuml` (the parked representation of `in_progress`) IN THE SAME COMMIT as the shipped handling** — docs describe the present, never ahead of code.
- **Verify via install-recovery arcs (STATBUS-071).** The load-bearing one is STATBUS-044's held `3-postswap-resume-died-rollback` scenario: budget consumed → **parked + named reason + unit alive-idle**, NOT `NRestarts` climbing forever, NOT `rolled_back`. Plus a per-class arc for each of A (readiness clears within allowance → completes), B (deterministic → park on first), C (disk → park), D (kill loop → budget → park; same-step-twice → early park).

## Ratification asks (King)
1. The allowance **VALUES** (proposed above; reconcilable at build/arc like 109's — the shape is fixed).
2. The **D budget = 3** + the **same-step-twice → park** rule.
3. The **park-marker columns** (`recovery_attempts int`, `recovery_parked_at timestamptz`).
4. **The budget boundary** now made concrete in THE STEP LIST: counted from the **flag write** (Phase 1.1, service.go:4140) through the **completed-write + flag removal** (Phase 4.2–4.3, service.go:4957/5001); pre-flight (Phase 0) and post-completion cleanup (Phase 5) are outside; a Phase-1 exhaust rolls back (data-safe), a Phase-3 exhaust parks (at-target). Confirm this boundary is the intended coverage.

Then: engineer builds (call-site classification + budget + park marker + the two row columns; class-A allowances co-located with the existing waits); diagrams updated in the same commit; STATBUS-044's held scenario rewritten green.
