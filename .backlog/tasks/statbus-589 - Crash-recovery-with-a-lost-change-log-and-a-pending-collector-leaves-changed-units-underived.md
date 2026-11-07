---
id: STATBUS-589
title: >-
  Crash recovery with a lost change log and a pending collector leaves changed
  units underived
status: In Progress
assignee: []
created_date: '2026-11-07T18:00:00Z'
updated_date: '2026-11-07T19:52:00Z'
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
- [ ] #1 A SQL regression test reproduces the crash state (empty base_change_log, has_pending TRUE, an ordinary collect_changes pending) and fails before the fix: statistical_unit stays empty after recovery and processing
- [ ] #2 After the fix, recovery in that state leads to every committed unit being derived (statistical_unit count equals the units), in the same test
- [ ] #3 Recovery with has_pending TRUE and no pending collector still enqueues one full rebuild (existing behaviour kept, asserted)
- [ ] #4 Fix shipped in an RC whose gate is green
<!-- AC:END -->
