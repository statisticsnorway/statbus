---
id: STATBUS-441
title: >-
  Inline scheduled-upgrade dispatch claims with post-382 SQL against a pre-382
  schema and stops at 42703
status: In Progress
assignee: []
created_date: '2026-10-02 12:10'
updated_date: '2026-10-02 16:16'
labels: []
dependencies: []
priority: high
---

## Issue

`./sb install`'s StateScheduledUpgrade dispatch (cli/cmd/install_upgrade.go's
runInlineUpgradeScheduled → ExecuteUpgradeInline) claims the scheduled row with
the NEW binary's claim SQL, which sets `claim_token` (STATBUS-382's
actor-guarded claim, migration 20260923202403). On a box whose schema predates
that migration (v2026.09.2 and earlier — v2026.09.3 carries it), the claim dies
deterministically:

    Dispatching scheduled upgrade id=2 to bcb1d568... (commit bcb1d568)
    Installation stopped: claim scheduled upgrade row 2: ERROR: column "claim_token" of relation "upgrade" does not exist (SQLSTATE 42703)

The dispatch runs BEFORE the pipeline's own Migrations step, so the column can
never appear no matter how many times the operator re-runs — the documented
canonical workflow ("./sb upgrade schedule <version>, then ./sb install to
dispatch immediately", AGENTS.md) is broken for every box older than v2026.09.3
that has a pending scheduled row. The daemon path is immune by ordering: the
old binary claims with its own older SQL, migrations run inside executeUpgrade,
the new binary takes over afterward.

## Evidence

Found live by the STATBUS-436 guest proof's seventh run (2026-10-02): a
v2026.09.2-era box (demo's exact era — the ticket's whole subject) with a
registered+scheduled row for v2026.10.0-rc.11; the official installer detected
"A scheduled upgrade is ready and will run now.", dispatched, and stopped at
the claim with SQLSTATE 42703. install-last-run-output.txt quoted above.
v2026.09.3's tree contains migrations/20260923202403_* (git ls-tree), so the
supported previous-release inline path (09.3 → rc.11) is unaffected; the broken
class is any box on ≤ v2026.09.2's schema with a pending scheduled row — the
era the entire 436 investigation exists to repair.

## Principled fix

runInlineUpgradeScheduled must make the schema current BEFORE ExecuteUpgradeInline
claims: apply the target tree's pending migrations (the same `migrate up` the
step table runs for every other state) ahead of the dispatch, operator-visible.
The target tree and binary are already in place when the dispatch runs (the
checkout precedes it), so the migration set is exactly the one the claim needs;
the pipeline's own Migrations step then no-ops. Rollback semantics are
unaffected: the pre-upgrade snapshot is taken after the claim, the added
column is nullable, and the old binary tolerates it. A migrate-first failure
leaves the upgrade unclaimed — forward-only migration semantics, same as the
step table's own failure mode.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An inline scheduled-upgrade dispatch from a box whose schema predates migration 20260923202403 claims and completes the upgrade (the 42703 class is gone), exercised by a logical/livedb test with a pre-382 schema fixture — not a full guest install.
- [ ] #2 The migration output appears in the dispatch's operator transcript before the claim line.
- [x] #3 The daemon-driven path and the 09.3→candidate inline path keep their current behavior (no double-migration harm; migrate up no-ops when current).
<!-- AC:END -->

## Implementation Notes

2026-10-02 rework after independent-review BLOCK (fix/441-floor-claim): the first implementation incorrectly ran the entire target migration set before ExecuteUpgradeInline acquired the upgrade serialization flag and before the pipeline snapshot. That widened rollback and old-serving-binary compatibility beyond what the fix needed. runInlineUpgradeScheduled now uses the codebase's existing bounded compatibility mechanism, `migrate up --to migrate.DaemonSchemaFloor --verbose`, with the operator-visible line `Bringing the database schema up to the daemon floor before the upgrade claim ...` ahead of the claim (AC#2). The daemon floor is the declared schema on which this binary's upgrade SQL may operate; its current value 20261001163000 includes migration 20260923202403, so claim_token exists for the claim while every migration above the floor remains inside executeUpgrade's serialized, snapshotted Migrations step (AC#3). The seams were renamed to reflect the floor scope and still pin load → floor bump → execute, abort-before-claim, and scheduled-row identity forwarding.

AC#1 is no longer claimed from seam tests. `TestInlineScheduledClaimPre382UndefinedColumnClosedByDaemonFloor` is a `//go:build livedb` fixture in cli/internal/upgrade. It creates and robustly drops a throwaway database on the local dev cluster, full-replays migrations only through the largest version below 20260923202403, inserts a scheduled public.upgrade row, proves the exact predecessor-schema production claim statement from service.go fails with SQLSTATE 42703, raises that same database only to DaemonSchemaFloor, then proves the identical claim succeeds and leaves the row in_progress with the expected claim_token. The shared development database's schema is never changed.

2026-10-02 16:15 UTC, second review round and merge. The 6862e26d7 fixture was BLOCKed again (tmp/441-floor-review.md): it ran a copied legacy claim statement, while production selects the tree-convergence branch on this schema, and it stopped at the claim instead of completing. Rework bd266b10b: the fixture now calls the real `(*Service).claimScheduledUpgrade` before the floor bump (SQLSTATE 42703 from the production branch) and after it (claim succeeds, stored token equals the claim snapshot). It then runs the real full-delta entry point `runMigrateUpToLog(... "migrate", "up")` and completes through the real `terminalUpdate` with `completedUpgradeSQL`, a byte-identical hoist of the two former inline completion strings (behavior-preserving; rewind-audit count 3→2 re-describes the same sites). Docker/git/health steps of executeUpgrade are not faked and not run. Mutation: dropping the floor bump makes the post-floor claim fail 42703. Independent re-review: MERGE (tmp/441-floor-rereview.md, reviewer reran the livedb test). Merged to master as 4a4590d12 + fd97ebf8f (patch-ids equal the reviewed commits), pushed in 7ec86ac2b; merged-tree `go test ./cmd ./internal/upgrade ./internal/install` passed.

AC#1 met by the livedb fixture. AC#3 met by the seam tests (load → floor migrate → execute; abort before claim on floor failure) plus the floor contract (above-floor migrations stay inside executeUpgrade). AC#2 is only pinned by call order, not by a captured operator transcript; it stays unchecked until the rc.12 guest proof (436 scheduled path, which drives exactly this dispatch on a v2026.09.2 schema) shows the floor line before the claim.

Known tooling gap found here: `./dev.sh test-livedb` refuses in a fresh worktree whose `.env.config` still carries SLACK_TOKEN (config validation wants it in `.env.credentials`); the targeted run used the direct livedb tier instead.

2026-10-03 09:00 UTC, regression found by the rc.12 upgrade arcs (run 37036597900, 38/40 green). `postswap-mid-migration-kill` ("B reached 'scheduled', expected 'completed'") and `postswap-mid-tx-kill` ("expected flag file present after kill") failed. Logs: `tmp/rc12-arc-midmig.log`, `tmp/rc12-arc-midtx.log`.

Mechanism:
- The pre-claim floor step always runs `migrate up --to floor`.
- With 0 pending, `migrate up` still runs `post_restore.sql` through `runPsqlFile`. That function hosts both harness kill sites.
- The subprocess inherits `STATBUS_INJECT_AT` and the one-shot arming file. So the kill fired before the claim: no flag, row still `scheduled`. It should have fired inside the upgrade's guarded Migrations step.

Production impact: none. Injection is harness-only, and a real crash at that point leaves the box untouched. The test impact is real, though: the arcs lost their intended crash placement.

Fix (rc.13, branch `fix/441-floor-skip-when-current`): run the pre-claim floor step only when a migration at or below the floor is unapplied. That restores the exact pre-441 behavior on every 09.3+ box.
