---
id: STATBUS-589
title: >-
  Crash recovery with a lost change log and a pending collector leaves changed
  units underived
status: In Progress
assignee: []
created_date: '2026-11-07T18:00:00Z'
updated_date: '2026-11-07T20:04:00Z'
labels:
  - bug
  - worker
  - recovery
dependencies: []
priority: high
type: bug
ordinal: 501204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After a crash that loses the UNLOGGED worker.base_change_log, crash recovery can leave committed domain rows underived. worker.reset_abandoned_processing_tasks sees has_pending=TRUE with an empty log; when a collect_changes task is already pending it enqueues nothing and clears has_pending. That pending collector is an ordinary one (no range), so it reads the empty log and completes without deriving anything. The rows changed before the crash stay out of statistical_unit and the reports until the next full rebuild.

Reproduced by hibiscus 2026-11-07 in a rolled-back transaction (table state after a crash simulated, not an observed server crash): 400 legal units, 0 statistical units, log emptied, has_pending=TRUE, collector 57 pending; after recovery and process_tasks: collector completed, 0 statistical units. Evidence: /Users/jhf/ssb/statbus/tmp/591/recovery-empty-log-pending-probe.{sql,out,err}.

Present since the post-upgrade rebuild redesign (rc.48, migration 20260422080000), unchanged through 20261030085731 (STATBUS-538), so in v2026.11.1 and v2026.11.2-rc.*. Requires an unclean PostgreSQL stop (UNLOGGED tables are truncated on crash recovery) while changes were waiting to be collected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A SQL regression test reproduces the crash state (empty base_change_log, has_pending TRUE, an ordinary collect_changes pending) and fails before the fix: statistical_unit stays empty after recovery and processing
- [x] #2 After the fix, recovery in that state leads to every committed unit being derived (statistical_unit count equals the units), in the same test
- [x] #3 Recovery with has_pending TRUE and no pending collector still enqueues one full rebuild (existing behaviour kept, asserted)
- [ ] #4 Fix shipped in an RC whose gate is green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 20:03 UTC: Recovery ownership and release impact assessed. The guard was present before v2026.11.1 and remains in v2026.11.2-rc.02: an empty UNLOGGED log plus durable pending=true plus an ordinary pending/interrupted collector could clear the durable flag without scheduling a full derive. No occurrence has been observed in Norway U or B. RED a4d8ca9ff/test390 and tmp/390-actual-red.out reproduce 23 imported legal units and zero derived rows under the original definition. GREEN 42d7414b6 adds a forward migration that always enqueues/upgrades a full derive in this unknown-change state. Test390 passes with 23 derived legal units and their enterprises and covers the no-collector full-request fallback. Full ./dev.sh test fast exited 0 at 20:03:10 UTC: 126 shared tests plus isolated094 and143, including390. Log tmp/test-589-fast-final.log. Regenerated doc/db and types verified. These are SQL state-loss tests, not an observed host crash. Next RC, exact-SHA CI and release-gate acceptance remain pending; ticket stays In Progress.
<!-- SECTION:NOTES:END -->
