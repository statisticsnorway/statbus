---
id: STATBUS-597
title: >-
  Norway serial rc03 clean full-register load and post-load recalculation
  comparison
status: In Progress
assignee: []
created_date: '2026-11-08T21:35:00Z'
updated_date: '2026-11-08T21:46:00Z'
labels:
  - performance
  - norway
  - release-validation
dependencies: []
priority: high
type: task
ordinal: 513204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner authorized Norway reset on November 8, 2026 at 21:33 UTC, explicitly requiring the whole big BRREG dataset followed by a separately timed full recalculation after loading finishes, with old Norway measurements for morning comparison. Use the existing published serial-only v2026.11.3-rc.03, not experimental concurrency or a new release. Preserve verified backups, inputs, logs and controlled baseline date. Stable promotion remains held.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Norway target and exact published serial candidate are verified, a restorable backup and secure configuration archive are retained before database recreation, and the recreated installation is healthy with the serial migration definitions and import concurrency one
- [ ] #2 The complete matching three-file BRREG downloads dataset is loaded with baseline hashes and controlled validity date, all import jobs finish and analytics reaches idle, and row counts, rejected rows, graph/history totals and timings are recorded
- [ ] #3 After the full load completes, a separately initiated full recalculation finishes with no failed tasks and preserved stock/history totals, with its wall and per-command task times recorded
- [ ] #4 A durable report compares same-host old Norway import and recalculation timings to this run, records exact versions, inputs, configuration and comparability limits, and claims no stable approval or experimental concurrency acceptance
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Verify target and candidate; retain and verify backup/config/baseline; deploy existing named serial candidate through supported install lifecycle; recreate its database; load all three full files; await complete idle and collect outputs; trigger and measure full recalculation; preserve and publish evidence with exact CI checks.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-08 21:44 UTC: owner authorization at21:33 explicitly covers Norway reset, full big dataset and a separate post-load full recalculation, not a new release/stable promotion. Verified latest published candidate v2026.11.3-rc.03/fc1830fe410b19007056ef0853ad9e491d7f4ad9. Actual Norway/rune is stable929fe787, schema20261107200300, idle/0failed, DB32G. It never applied removed711/713, so reset is for the explicitly requested clean reference, not repair of observed obsolete Norway objects. All3files match oldB SHA256/byte sizes, controlled validity2026-11-07. Baseline actual root53750 completed3684/3684tasks today08:36:26.699674->08:57:29.641707:1262.942033wall_s/4158.636576task_s. Old graph108851business-key records retained, error rows LU1/ES1/LR4206 and warnings53592/26321 saved. Fresh backup dbdumps/no_20261108_223654.pg_dump2744843430bytes SHA25636d6575762d6d3d5c2c49442748a8616f1c5c0098cf2b5d2a752b9644400ec10, full pg_restore archive read and SHA checkPASS21:44:30,36logs retained. Secure config/users/binary/untracked archive11175118bytes SHA4f85f5be777d602c96524a0939d2b23533a945e3f012f56b06cfa859b3f3d322 under /home/statbus/statbus-retained/597-serial-rc03-20261108 (700/600). No restore into a database claimed. Registered/scheduled existingrc03 through actualdaemon21:44:54, upgrade progressing normally. Evidence tmp/rune-measure/C-serial-rc03/. No acceptance criteria checked yet.
<!-- SECTION:NOTES:END -->
