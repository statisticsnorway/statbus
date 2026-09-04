---
id: STATBUS-354
title: >-
  rollback finishing as a column: land wip/347-column-protocol behind Sol's S3 rollback reorder, proven by two VM arcs
status: To Do
assignee: []
created_date: '2026-09-04 10:26'
updated_date: '2026-09-04 10:26'
labels:
  - upgrade
  - fail-fast
  - constraints
dependencies: []
priority: high
type: task
ordinal: 347000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Where this comes from

STATBUS-347 made rollback finishing cleanup-only: the row is marked "finish pending" BEFORE SQL read-only and HTTP maintenance are lifted, and the marker unlink plus `rolled_back` happen in one row-locked transaction afterwards. rc.14 ships that state as a **string prefix** on the `failed` row (`ROLLBACK_FINISH_PENDING:`), which the King ruled is not acceptable as the permanent form: the invalid must be impossible to express, so the state must be a **column with a CHECK constraint**, `rollback_finish_pending_at`.

That column version exists and is complete: branch `wip/347-column-protocol` (= `dceca3666`, 9 insertions on top of the rc.14 line: migration `20260903205636`, `DaemonSchemaFloor` bump, the write sites, docs). It was taken off master because Sol's review (`tmp/sol-review-347.md`, finding 3) showed it is unsafe on the FIRST release that carries it: that release's own adoption rollback restores a snapshot from BEFORE the column exists, and the pending write then fails with `42703 column does not exist`, leaving the old binary to resume with the old unsafe order.

## The ruling on the fix (do not relitigate)

No inline DDL outside `db.migration`. No idempotent-migration hacks. The only schema mechanism is the existing `DaemonSchemaFloor` plus the ordinary `./sb migrate up --to <floor>` recorded in `db.migration`. The King rejected an "inline DDL shim" explicitly.

## What to do

Sol's accepted design is `tmp/sol-s3-design.md`; the phased plan with function names, tests and commit sequence is `tmp/sol-s3-plan.md`. Copy both into `doc/upgrade-rollback-floor.md` as the first commit so they are versioned. Then, in this order:

1. **Rollback direction is durable before anything destructive.** Every rollback entry (including the in-process `newSbUpgradingFailure → rollback` route, which today never stamps) rolls the held marker to `StepRollback` exactly once. Recovery tests `StepRollback` before the ordinary post-swap at-target/behind routing, because after step 3 the restored DB will look migration-current and observed state can no longer decide direction.
2. **Reorder rollback so the target tree and target `./sb` survive the snapshot restore.** Today `restoreGitState` and `restoreBinary` run before `restoreDatabase`, destroying the migration file and the binary the floor needs. New order: stop and verify the data plane; restore the database with target assets still present; start DB only; run target `./sb migrate up --to DaemonSchemaFloor --verbose` from the project root (ordinary engine, ordinary ledger); only then restore the source tree, generate source-era config via `./sb.old config generate`, start and health-check source services.
3. **Write pending, reopen, finalize, publish last.** Write `rollback_finish_pending_at` with the still-running target process; lift SQL read-only and HTTP maintenance; finalize row and marker in one transaction; rename `./sb.old` over `./sb` as the LAST act. A cleanup-only marker phase covers the interval so there is no marker-free window in which the target binary can self-heal to the source binary while the pending row is uncommitted.
4. **Floor failure contract.** If the floor migrate fails on the restored volume: `ROLLBACK_SCHEMA_FLOOR_FAILED`, row stays `in_progress`, target tree and target `sb` stay, marker `StepRollback`/failure phase, app/worker/REST stay stopped, both maintenance barriers stay up, DB stays reachable for diagnosis, daemon restart count bounded and frozen. `./sb install` is the deliberate retry: restore the snapshot again, re-apply the ordinary migration, finish rollback, publish the source binary last. Never restore the old binary as an escape hatch.
5. **Merge `wip/347-column-protocol`** on top (rebase; it is 9 lines), replacing the prefix form. Delete the prefix constants and their tests.
6. **Live twins** for each crash boundary in the plan's Phase 5 (`STATBUS_LIVE_DB=1`, real DB, real marker files), run from the main checkout, never from a worktree sharing the compose project.
7. **Two mandatory VM arcs** (plan Phase 7), both must be green before any candidate carrying the column is offered to Norway:
   - `rollback-schema-floor-adoption-arc.sh`: A (schema max `20260901212308`, non-empty sentinel data) → B (first candidate with the column and S3); inject a deterministic post-migration failure; assert the restore erases the column, the target process starts DB only and re-applies the floor from B's tree with B's `sb`, final `rolled_back`, migration recorded with correct hash, pending NULL, marker absent, A healthy, A binary canonical, sentinel intact, and the log shows the exact order.
   - `rollback-schema-floor-failure-arc.sh`: same lineage; make only the rollback-time floor re-application fail; assert the closed-hold contract from step 4; remove the cause; `./sb install`; assert recovery to healthy A with data intact.

## Done when

- Both arcs green on a candidate cut from master with the column.
- `public.upgrade` has `rollback_finish_pending_at` with its CHECK, no row can express "pending" as text, and `grep ROLLBACK_FINISH_PENDING cli/` finds nothing.
- Migration `20260903205636` is the daemon floor and the adoption rollback re-applies it through `db.migration` (visible in the arc log as an ordinary `migrate up --to` line).
- That candidate has been installed on Norway by the King and its own rollback path, if exercised, showed the floor re-application.

## Scope guard

This is the ONE remaining piece of 347. 347 is Done for everything else (S1 `539ba12e0`, S2 `3afd379cd` + `c9e3c1a36`, S4 via STATBUS-348, prefix form shipped in rc.14). Do not reopen 347; work here.
<!-- SECTION:DESCRIPTION:END -->
