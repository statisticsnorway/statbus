---
id: STATBUS-354
title: >-
  rollback finishing as a column: land wip/347-column-protocol behind Sol's S3 rollback reorder, proven by two VM arcs
status: In Progress
assignee: []
created_date: '2026-09-04 10:26'
updated_date: '2026-09-07 19:41'
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
## Current state (coordinator, 2026-09-07 17:10)

| piece | commit(s) | verified by | status |
|---|---|---|---|
| Column restore as forward rewrite (no revert of `8e021550e`) | `9686ef578` | Sol ACCEPT | landed |
| Phase 1: durable `StepRollback` stamp before any destructive work; pre-lock routing | `d904a3b6b`, fix `12daf5971` | Sol REJECT then ACCEPT | landed |
| Phase 2: rollback order A-E, floor via ordinary `sb migrate up --to 20260907120000`; fail-closed hold on marker mutation failure | `66c9d61b6`, `4d90db90c`, fix `f2862bd47` | Sol P0 (fail-open) then fixed; whole-ticket review pending | landed |
| Phase 3: source restore strictly after the floor | `c6cd02402` | Sol ACCEPT | landed |
| Phase 4: finalizer order (pending commit, cleanup routing, final row before unlink, binary last); enum `ROLLBACK_SCHEMA_FLOOR_FAILED` | `6eb217b23`, `c61ae413e`, `20260907154645` | Sol ACCEPT impl; string-proxy oracle replaced by released-SQL PREPARE test in `f2862bd47` (72 rc.14 statements prepare) | landed |
| Ordering repair: re-timestamp to `20260907120000`, floor bump, full-replay artifacts, sort guard | `f6d249b62`, `11835579a` | Sol ACCEPT | landed |
| Harness seams (`killed-after-rollback-floor-before-pending`, `rollback-floor-reapply`) | `c3b62288c` | Sol: correctly placed, inert | landed |
| Two VM arcs (discovery 33 to 35) | `943ac1448` | `bash -n` only; NOT RUN (paid) | awaiting batch RC ladder |
| Eight live twins incl. released-SQL PREPARE | `6e421c2f0` | builder: all pass, `tmp/statbus354-live-full.log`; independent rerun by spider in progress | landed, review pending |
| Blast radius of the old timestamp | `tmp/STATBUS-354-blast-radius.md` | ten fleet boxes read-only: 0 orphan rows; no tag contains it | local-only, rebuild, no workaround (owner ruling) |
| CI at HEAD `c6329610d` | runner Fast Tests, Images green; Go Test, app build green at code SHA `6e421c2f0` | `tmp/batch-ci-evidence.md` | green |

Remaining before Done: (1) spider's whole-ticket verdict at `tmp/STATBUS-354-review/FINAL-REVIEW.md`; (2) the ONE batch RC (owner-gated) with both arcs green; (3) Norway install by the owner.

Not a gate: niue `pg_regress.yaml` fallback is red at every commit since `f6d249b62` because its checkout-local `.db-seed` cache was built under the old timestamp (42701 duplicate column). Runner Fast Tests is the oracle (STATBUS-360). Repair of that cache is a separate, owner-approved action.

## Ground-truth correction (coordinator, 2026-09-06)

The description below says the column version lives on branch
`wip/347-column-protocol` (= `dceca3666`, "9 insertions"). Git says otherwise,
and an implementer must not lose time on it:

- `dceca3666` is a 9-line BACKLOG edit and is already an ancestor of master.
  The branch head adds nothing; it is now also pushed to origin so nothing
  dangles.
- The column protocol itself is commit **`012ca22da`** ("rollback_finish_pending_at
  is a constrained column, not an error prefix"), which IS on master, and was
  then surgically REMOVED again by **`8e021550e`** ("ship prefix rollback
  finishing for this RC") for the rc.14 line: migration
  `20260903205636_statbus_347_rollback_finish_pending_column.{up,down}.sql`,
  pg_regress `..._repair.sql`, and the column readers were deleted; execObserved
  and its tests were kept.
- Master today therefore carries the PREFIX form (`RollbackFinishPendingPrefix`
  in `service.go` ~8403, five sites) and NO column migration.

So step 5 ("merge `wip/347-column-protocol`") means: **re-apply the column
portions of `012ca22da` on top of S3** (a `git revert 8e021550e` is the
mechanical starting point, then resolve against the S3 reorder), not a branch
merge. The daemon-floor bump and the four column readers come back with it.
Sol's review finding 3 (`tmp/sol-review-347.md`) is still the reason it was
pulled and S3 is still the fix; nothing else changes.

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
- Migration `20260907120000` (re-timestamped from `20260903205636` by `f6d249b62` so it sorts after 349's `20260906173739`; guard `TestNewMigrationsSortAfterPreviousRelease`) is the daemon floor and the adoption rollback re-applies it through `db.migration` (visible in the arc log as an ordinary `migrate up --to` line).
- That candidate has been installed on Norway by the King and its own rollback path, if exercised, showed the floor re-application.

## Scope guard

This is the ONE remaining piece of 347. 347 is Done for everything else (S1 `539ba12e0`, S2 `3afd379cd` + `c9e3c1a36`, S4 via STATBUS-348, prefix form shipped in rc.14). Do not reopen 347; work here.
<!-- SECTION:DESCRIPTION:END -->

## Coordination checkpoint: 2026-09-07 16:31

Live twins committed by snake at `6e421c2f0`. Independent whole-ticket Sol review delegated to spider, report pending at `tmp/STATBUS-354-review/FINAL-REVIEW.md`. Snake assigned publication and exact-HEAD CI monitoring. Read-only blast-radius report: all ten fleet boxes returned zero orphan rows. Only named candidates reach installations. No final acceptance yet: review, exact-HEAD CI and owner-approved batch RC paid ladder remain.

## Whole-ticket review (spider, Sol, 2026-09-07 17:17): ACCEPT for the RC ladder

Report: `tmp/STATBUS-354-review/FINAL-REVIEW.md`. No P0/P1 left at `6e421c2f0`. Prior P0s confirmed fixed by behavioral oracles (`TestRollbackSchemaFloorFailureMarkerWriteFailureKeepsFlockAndOriginalRoute`, `TestRollbackSchemaFloorFailureDurablyRoutesDaemonAliveIdle`, `TestReleasedOldBinarySQLPreparesAgainstRollbackSchemaFloor` preparing 72 rc.14 statements). Full Go suite green; both arcs `bash -n`, discovery 35; full seed replay from zero green (397 migrations incl. `20260907120000` and `20260907154645`).

Caveat, stated plainly: the reviewer's OWN full live rerun did not complete. It was blocked by Docker Desktop wedging on `statbus-local-db` start (twice, incl. after a backend restart). The green live run on record is the builder's (`tmp/statbus354-live-full.log`). Root cause of the reviewer's earlier 42703 fixture is now exact and is not the old timestamp: `./sb` on disk was IDENTITY-LESS (built by a raw `go build` with `vcs.modified=true` and no `cmd.commit` ldflag, verified with `go version -m sb`), so the guard refused every mutating command with exit 69 after twin 1's real down migration, leaving `statbus_local` below the floor. The backlog-only pushes were a red herring: the freshness probe is scoped to `cli/` (`TestIsStale_NonCliChangeIgnored`). Two lessons: build `./sb` only via `./dev.sh` (ldflags), and the live twins should pin the binary they start with instead of the mutable on-disk `./sb` (filed as STATBUS-362).

Still required for Done: named RC, both paid arcs green with logs inspected, owner installs on Norway.

## Status (2026-09-07 19:41): In Progress

Code landed and Sol-accepted for the RC ladder (`6e421c2f0`, review `3a68093c7`). Waiting on: batch RC with both rollback-floor arcs green, then Norway install by the owner.
