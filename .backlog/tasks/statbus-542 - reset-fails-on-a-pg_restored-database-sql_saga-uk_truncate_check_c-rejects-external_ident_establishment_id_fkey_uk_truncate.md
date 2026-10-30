---
id: STATBUS-542
title: ./sb db restore runs the extension step (EnsureTrackedExtensions)
status: In Progress
assignee: []
created_date: '2026-10-30T11:57:00Z'
updated_date: '2026-10-30T12:21:00Z'
labels:
  - sql_saga
  - reset
  - restore
dependencies: []
priority: medium
type: bug
ordinal: 468204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: ./sb db restore restores a dump from any released sql_saga version and leaves every tracked extension at the image default, the same state ./sb migrate produces.

pg_dump does not record extension versions, so an older dump restored into the image default sql_saga is rejected (era check 'restore old sql_saga dumps per doc/upgrade.md'). sql_saga's documented procedure: create sql_saga at the dump's version first, restore including ACLs, then ALTER EXTENSION UPDATE + check_integrity(), which is the extension lifecycle step (migrate.EnsureTrackedExtensions).

### Closing review
No doc change beyond code comments; journal in tmp/journal.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Restoring dbdumps/dev_20261018_134220.pg_dump (sql_saga 1.1) with ./sb db restore succeeds; before the change it failed in phase 3 on the era check
- [x] #2 After restore every tracked extension equals its image default and db.extension_upgrade records the update
- [x] #3 reset(true,'data') succeeds after restoring 1.0, 1.1 and 1.4 dumps
- [x] #4 go test TestDumpSqlSagaVersion fails before and passes after
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
12:15 Investigation: reset() on a restored database works through every official path on statbus_local: ./sb db restore of demo dump; then ./sb migrate up (extension step + 538 migration); worker drained; process_tasks in same session; FK check fired first in same tx (logs tmp/542-*.log). Stopped worker's plain pg_restore also passed. The original failure came only from a hand-built scratch DB (CREATE DATABASE + single pg_restore + early 538 draft applied with psql -f), dropped before diagnosis; not a product defect. Real gap found: restoreLocal never runs the extension lifecycle step, so a dump from an older sql_saga would run against a newer library without ALTER EXTENSION UPDATE + check_integrity(). Scope changed to closing that gap.

12:21 Fix: restoreLocal Phase 0 creates sql_saga at the dump's version (newest sql_saga receipt in db.extension_upgrade, else retired update-migration rows in db.migration, else 1.0); Phase 5 runs migrate.EnsureTrackedExtensions after data+ACLs. Red: tmp/542-restore-dev.log (era check), tmp/542-unit-red.log. Green: tmp/542-restore-dev-green.log (Phase 0 1.1, sql_saga 1.1->1.4), tmp/542-ext-after-dev.log, tmp/542-restore-demo_20261007_140004.log (1.0->1.4), tmp/542-restore-demo_20261030_093705.log (1.4 no-op); reset() t after each; tmp/542-unit-green.log.
<!-- SECTION:NOTES:END -->
