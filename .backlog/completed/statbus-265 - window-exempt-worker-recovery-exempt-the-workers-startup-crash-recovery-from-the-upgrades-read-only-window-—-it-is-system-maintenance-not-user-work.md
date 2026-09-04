---
id: STATBUS-265
title: >-
  window-exempt-worker-recovery: exempt the worker's startup crash recovery from
  the upgrade's read-only window — it is system maintenance, not user work
status: Done
assignee: []
created_date: '2026-08-27 12:48'
updated_date: '2026-08-27 13:51'
labels:
  - worker
  - upgrade
dependencies: []
priority: high
type: enhancement
ordinal: 258000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-262: every upgrade starts the worker INSIDE the read-only accident-guard window by designed order (healthCheck at service.go:6931 precedes terminalExec(windowOffSQL) at :7039), so the worker's startup recovery can be refused in that gap.

Architect's ruling, upgraded from "defensible" to ratified-in-principle: exempt the worker's startup recovery the way the upgrade's own writers self-exempt (SET default_transaction_read_only = off on its session). The argument that settles it: a rollback restores the volume WHOLESALE, so the reset's rows revert regardless of whether it ran — the window's purpose is that a USER must not lose work they believed done, and the worker's crash recovery is not user work. The exemption cannot cost the rollback guarantee anything.

Constraint from the same ruling: an exemption on an accident-guard must be ARGUED AT THE LINE, never slipped in — the code comment carries this justification. Note: with this + STATBUS-264 landed, the upgrade's window/health-check ordering change is ranked unnecessary (deliberately not ticketed — see 262 final ruling).

WHAT IS ACHIEVED: the worker's crash recovery cannot be refused by the upgrade's own guard, removing the wedge cause rather than surviving it.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-27 13:08
---
**BUILT AND FROZEN.** One file: `cli/src/worker.cr`. Type-checks clean through the entrypoint, zero warnings; Go side green.

## The acceptance condition, met EMPIRICALLY rather than argued

The ruling's condition for a guard-relaxing change is that acceptance must prove the guard STILL BITES in the direction it keeps. I proved both halves against the REAL guard shape — an inherited `ALTER DATABASE … SET default_transaction_read_only = on`, on a throwaway database created and dropped for the purpose:

1. inherited `on`; a write is REFUSED — `cannot execute CREATE TABLE in a read-only transaction`
2. `SET default_transaction_read_only = off` → shows `off`; the same write SUCCEEDS
3. `RESET default_transaction_read_only` → shows `on` again
4. **the very next write is REFUSED again** — the guard bites

**My first attempt at this test was inconclusive and I nearly believed it.** I simulated the guard with a session-level `SET`, so `RESET` returned to the session's own initial value (`off`) and appeared to prove the guard did NOT come back. That was an artefact of the simulation, not a fact about the mechanism — the real guard is inherited from the database, and `RESET` restores an inherited value. Only the throwaway-database test settles it, so that is the one reported.

## Why the exemption is SCOPED, which is the load-bearing part

`db` here is a single `DB.connect` connection shared with everything that follows, so an unscoped `SET` would leak into the queue processing that starts moments later. **Processing tasks IS user work** — precisely what the guard exists to block — and a worker running tasks inside the window would defeat the guard entirely while looking perfectly healthy. So the exemption is set immediately before the call and RESET in an `ensure` immediately after.

`RESET`, never `SET … = on`: RESET restores whatever the session inherited, so outside an upgrade it is a no-op, and inside one the guard returns. Writing `on` literally would strand a worker read-only forever on a box that was never in a window.

## The argument, at the line as required

The comment carries the full justification rather than a pointer: what the guard is for (a USER must not lose work they believed done), why this call is not that (it reclaims rows a killed worker abandoned — bookkeeping about the worker's own crash, not work anyone awaits), and why it costs the rollback guarantee nothing (a rollback restores the volume wholesale, so these rows revert regardless of whether the reset ran — there is no state here a rollback could fail to undo). Plus the scoping reason and the empirical verification.

## ONE THING FOR THE FOREMAN TO DECIDE

**264 and 265 are both in `cli/src/worker.cr`, and 265's code sits INSIDE the retry loop 264 created.** Staging by filename cannot separate them. 264 alone is coherent and compiles (retry without exemption), so a hunk split is possible — but the value looks low given the two are the release-blocking pair riding rc.10 together, and a bad split carries real risk. I have not assumed either way. Say which and I will produce it.

Also: `.github/workflows/deploy-to-dev.yaml` and `ops/niue/sshdoers` are dirty and are NOT mine — they are the 259 endgame (the block swap to the named-target verb, now that Stage 8 is live).
---

author: engineer
created: 2026-08-27 13:48
---
**THE PROPERTY IS NOW IN THE SUITE THAT GATES EVERY RELEASE.** The King's correction was right and the fix is done: my throwaway-database proof evaporated with the session that ran it, so nothing stopped a future edit from quietly removing the exemption or the RESET. Two new files, frozen for review, nothing else touched:

- `test/sql/094_read_only_window_worker_recovery_exemption.sql`
- `test/expected/094_read_only_window_worker_recovery_exemption.out`

Fast tier (094 → shared, not 4xx/5xx), no registration needed — the runner globs `test/sql/*.sql`. GREEN: `ok 1 - 094_read_only_window_worker_recovery_exemption 143 ms`.

## What it pins, against real objects

The guard is established the way an upgrade establishes it — `ALTER DATABASE … SET default_transaction_read_only = on` — then INHERITED by reconnecting. That shape is the whole point: the artefact that fooled my first attempt was simulating the guard with a session-level `SET`, where `RESET` returns to the session's own start value and appears to prove the guard never comes back. Four arms:

1. under the guard, an ordinary write is REFUSED (`cannot execute CREATE TABLE in a read-only transaction`)
2. under the exemption, the REAL `worker.reset_abandoned_processing_tasks()` runs against a seeded `processing` row and flips it to `interrupted`
3. `RESET` restores the inherited guard
4. the very next write is REFUSED again — the no-leak arm

## RED-verified, and red for the REASON claimed

Four mutations, each asserting its own site first (a mutation that silently misses its target is the failure mode that makes a RED pass worthless — it cost me a wasted proof earlier this session). Verdict AND divergence recorded for each; harness at `tmp/red_verify_094.sh`, log at `tmp/red_verify_094.log`:

- **M1** guard set `off` instead of `on` → both `on` values become `off`, BOTH refusals vanish
- **M2** exemption removed → `ERROR: cannot execute INSERT in a read-only transaction`, `interrupted` never appears — arm 2's success is CAUSED by the exemption
- **M3 (the money mutation)** arm 3 'restores' with `SET … = off` instead of `RESET` — the exact regression this test exists to catch → `guard_restored` flips to `off` and **only ARM 4's refusal disappears while ARM 1's remains**. That asymmetry is the proof arm 4 is independently load-bearing, not a restatement of arm 3.
- **M4** seed `pending` instead of `processing` → `interrupted` becomes `pending`; the state flip is really read, not assumed

File restored byte-identical afterwards, re-run green.

## Two shape decisions the review should look at, both deliberate

**ON_ERROR_STOP stays OFF for the whole file — NOT the usual off/on sandwich.** This test runs against the SHARED cloned database, and between ARM 0 and CLEANUP that database is read-only for everything that connects. psql has no `finally`. With ON_ERROR_STOP on, one unexpected error anywhere in the guarded region aborts before cleanup, the ALTER DATABASE survives, and every later test in the run fails on writes it has every right to make — one real failure reported as a dozen fake ones with the true cause several tests upstream. Off costs nothing in rigour: pg_regress judges by DIFF, not psql exit status, so an unexpected error still prints, still diverges, still fails — and cleanup still runs. Both intentional refusals carry `-- expected to fail with read_only_sql_transaction (25006)` markers so `safe_update_expected`'s errors-into-expected guard recognises the intent; I regenerated THROUGH that guard rather than cp-ing around it.

**Isolated tier was considered and rejected on evidence, not preference.** A database-per-test would remove the shared-DB hazard entirely, but isolation is keyed purely to the 4xx/5xx prefix (`dev.sh:1031`) — which is also the benchmark tier excluded from `fast`. The two cannot both be had; fast tier was the requirement, so the hazard is handled in the file instead. Worth a ticket if we ever want isolation decoupled from the numeric prefix.

## Boundary, stated in the file header so no one reads more into a green than it carries

This pins the DATABASE-side semantics only. That the Crystal worker places its SET and RESET correctly AROUND the call is still covered by type-check and review alone, until STATBUS-270 revives the worker's own test suite. The header says so in those words.

No git operations performed. Two untracked files are the entire diff.
---

author: engineer
created: 2026-08-27 13:51
---
**Architect's addition applied; still green; ready to land as the first commit after the tag.**

Added to `test/sql/094_read_only_window_worker_recovery_exemption.sql`, placed beside the `\set ON_ERROR_STOP off` decision because that is the mechanism whose one uncovered cost it names:

> THE ONE COST, AND IT FALLS ON A HUMAN, NOT ON THE MECHANISM: if this file's expected output ever changes, READ THE DIFF — an unexpected error appears here as ordinary output, so regenerating the expected file without reading it would baseline a real failure as the new truth.

The comment is echoed into the output, so the expected file was regenerated through `safe_update_expected` (not blocked — the added lines are comments, no new ERROR lines). Verification run after regeneration: `ok 1 - 094_read_only_window_worker_recovery_exemption 145 ms`.

**The change is comment-only against the exact bytes that were RED-verified** — `diff` vs the pristine copy the mutation harness restored shows five added lines, every one starting `--`, no assertion added, moved or altered. The four RED results therefore still hold for this file as it stands; I did not need to re-run them and did not claim them without checking.

Still two untracked files, no git operations. STATBUS-274 noted for the isolation-decoupling follow-up.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Landed at ca6b7082d together with STATBUS-264. The recovery's session self-exempts from the read-only accident-guard: SET immediately before, RESET in an ensure immediately after — scoped tight because db is one shared connection and a leaked exemption would let queue processing (user work) write inside the window, a guard that stopped guarding while still appearing in the code. RESET, never a literal, so a non-window box is never stranded. Acceptance proven on a throwaway database with the real inherited-ALTER-DATABASE shape, including the half most people skip: after RESET, the very next write is refused again (no leak). Latent coupling recorded (→ STATBUS-272): the scoping is safe BECAUSE startup is sequential — concurrent startup work on the shared connection would leak the exemption; the note belongs at the line.
<!-- SECTION:FINAL_SUMMARY:END -->
