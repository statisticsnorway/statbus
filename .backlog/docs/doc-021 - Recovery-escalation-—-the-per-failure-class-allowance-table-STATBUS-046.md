---
id: doc-021
title: Recovery escalation — the per-failure-class allowance table (STATBUS-046)
type: specification
created_date: '2026-07-01 13:11'
tags:
  - upgrade
  - recovery
  - escalation
  - STATBUS-046
  - architecture
---
# Recovery escalation — the per-failure-class allowance table (STATBUS-046)

**Status:** design for King ratification. Architect, 2026-07-01. The "no loop-forever, no
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

Then: engineer builds (call-site classification + budget + park marker + the two row columns; class-A allowances co-located with the existing waits); diagrams updated in the same commit; STATBUS-044's held scenario rewritten green.
