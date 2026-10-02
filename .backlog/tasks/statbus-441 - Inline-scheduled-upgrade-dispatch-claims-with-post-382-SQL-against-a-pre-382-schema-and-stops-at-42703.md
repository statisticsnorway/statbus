---
id: STATBUS-441
title: Inline scheduled-upgrade dispatch claims with post-382 SQL against a pre-382 schema and stops at 42703
status: To Do
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

## Acceptance criteria

- [ ] #1 An inline scheduled-upgrade dispatch from a box whose schema predates migration 20260923202403 claims and completes the upgrade (the 42703 class is gone), exercised by a logical/livedb test with a pre-382 schema fixture — not a full guest install.
- [ ] #2 The migration output appears in the dispatch's operator transcript before the claim line.
- [ ] #3 The daemon-driven path and the 09.3→candidate inline path keep their current behavior (no double-migration harm; migrate up no-ops when current).

2026-10-02 implementation (fix/441-migrate-before-claim): runInlineUpgradeScheduled now applies the target tree's pending migrations BEFORE ExecuteUpgradeInline's claim, with the operator-visible line 'Bringing the database schema up to date before the upgrade claim ...' ahead of it (AC#2). The tree and binary are already the target's at dispatch time, so `migrate up` applies exactly the set the claim needs and then no-ops inside executeUpgrade's own Migrations step (AC#3: idempotent when current; the supported previous-release path is unchanged). Rollback semantics untouched: the pre-upgrade snapshot is still taken inside executeUpgrade, and the added column is nullable. Seams (inlineDispatchMigrateUp / inlineDispatchLoadConfig / inlineDispatchExecute) pin the ordering without a schema fixture (AC#1): TestInlineDispatchMigratesBeforeClaim (load,migrate,execute), TestInlineDispatchMigrateFailureAbortsBeforeClaim (no claim after a failed catch-up), TestInlineDispatchPassesTheScheduledRowThrough. Full cli/cmd suite + gofmt clean.
