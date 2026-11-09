---
id: STATBUS-597
title: >-
  Norway serial rc03 clean full-register load and post-load recalculation
  comparison
status: Done
assignee: []
created_date: '2026-11-08T21:35:00Z'
updated_date: '2026-11-09T00:32:00Z'
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
- [x] #1 Norway target and exact published serial candidate are verified, a restorable backup and secure configuration archive are retained before database recreation, and the recreated installation is healthy with the serial migration definitions and import concurrency one
- [x] #2 The complete matching three-file BRREG downloads dataset is loaded with baseline hashes and controlled validity date, all import jobs finish and analytics reaches idle, and row counts, rejected rows, graph/history totals and timings are recorded
- [x] #3 After the full load completes, a separately initiated full recalculation finishes with no failed tasks and preserved stock/history totals, with its wall and per-command task times recorded
- [x] #4 A durable report compares same-host old Norway import and recalculation timings to this run, records exact versions, inputs, configuration and comparability limits, and claims no stable approval or experimental concurrency acceptance
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Verify target and candidate; retain and verify backup/config/baseline; deploy existing named serial candidate through supported install lifecycle; recreate its database; load all three full files; await complete idle and collect outputs; trigger and measure full recalculation; preserve and publish evidence with exact CI checks.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-08 21:44 UTC: owner authorization at21:33 explicitly covers Norway reset, full big dataset and a separate post-load full recalculation, not a new release/stable promotion. Verified latest published candidate v2026.11.3-rc.03/fc1830fe410b19007056ef0853ad9e491d7f4ad9. Actual Norway/rune is stable929fe787, schema20261107200300, idle/0failed, DB32G. It never applied removed711/713, so reset is for the explicitly requested clean reference, not repair of observed obsolete Norway objects. All3files match oldB SHA256/byte sizes, controlled validity2026-11-07. Baseline actual root53750 completed3684/3684tasks today08:36:26.699674->08:57:29.641707:1262.942033wall_s/4158.636576task_s. Old graph108851business-key records retained, error rows LU1/ES1/LR4206 and warnings53592/26321 saved. Fresh backup dbdumps/no_20261108_223654.pg_dump2744843430bytes SHA25636d6575762d6d3d5c2c49442748a8616f1c5c0098cf2b5d2a752b9644400ec10, full pg_restore archive read and SHA checkPASS21:44:30,36logs retained. Secure config/users/binary/untracked archive11175118bytes SHA4f85f5be777d602c96524a0939d2b23533a945e3f012f56b06cfa859b3f3d322 under /home/statbus/statbus-retained/597-serial-rc03-20261108 (700/600). No restore into a database claimed. Registered/scheduled existingrc03 through actualdaemon21:44:54, upgrade progressing normally. Evidence tmp/rune-measure/C-serial-rc03/. No acceptance criteria checked yet.

2026-11-08 21:53UTC: completed existing named rc03 normal daemon upgrade at21:49:06.990803, then verified backup/config/binary/volume/idle and reset ONLY statbus-no-db-data. Supported ./sb install --non-interactive completed21:53:19 exit0, exact publishedfc183seed restored. Positive accepted reference comparison matched all10routine hashes, migration710/712/714 and default serial importqueue1. Freshjobs0/units0/users15, DB34359738368bytes, monitorallok5/5services/API/site/worker/upgrader, no marker. Durable whole-three-file wrapper launched on remote Norway with controlleddate2026-11-07, followed by separately guarded fullrecalculation only after verified complete load+analytics. Full completion/timings/parity not yet claimed. Evidence tmp/rune-measure/C-serial-rc03/{recreate.log,recreated-readiness.log,recreated-definitions.out,recreated-state.json,full-run.sh}.

2026-11-08 23:57UTC: all three whole-file imports finished23:32:07.781952UTC and initial analytics reached idle23:48:49.236386UTC. Exact output checks PASS: LU1134475/ES823767/LR29504, rejected1/1/4206 and warning53592/26321/0 rows identical to old baseline, eight history rows/stocks exact, 108851 canonical graph records exact with zero added or removed (29504edges,25635groups,53268memberships,444roots). Load-to-idle6872.802017s, importspan5871.347583s, analytics tail1001.454434s. Separate full recalculation actually dispatched23:48:54.091552UTC, root45578, running. AC2 verified, AC3/4 remain pending. Evidence tmp/rune-measure/C-serial-rc03/{after-load-parity.json,baseline-vs-rc03-graph-summary.json,import-timings.json,recalculation-request.json}. No new release or concurrency deployment.

2026-11-09 00:12UTC: genuine remote runner exit0; separate full recalculation root45578 started2026-11-08T23:48:54.122466Z and completed2026-11-09T00:09:39.286247Z,1245.163781wall_s,3684/3684completed/0failed. Independent saved-artifact checks recomputed wall time and exact command counts, stock/history/job parity, canonical graph bytes and input posthashes. Readonly00:10:56 host stillfc183, three finishedjobs/zeroactive/failed/changelog/pendingflag, monitorhealthy. Old1262.942033s =>1.4077%shorter only, no major recalculation gain. Report doc/performance/2026-11-norway-serial-rc03-comparison.md records all six import phases and thirteen recalculation command totals, baselines/versions/files/config/digests/backups/comparability. Importspan12.59%shorter,load-to-idle6.17%shorter,LRanalysis69.03%shorter,analyticstail64.71%longer. All AC observed. Report/ticket commit and exact-SHA CI pending before Done. No release or experimental Norway deployment.

2026-11-09 00:32UTC: report1aa4164e14a389c223ab20ea8860fcd96b7946ae pushed, all seven exact-SHA workflows status=completed/conclusion=success: CodeQL42538905634,Go42538906128,App42538905973,Images42538905989,Harness42538906097,Notify42538906154,Fast42539218089. Fast displayTitle exercised-sha=1aa4164e14a389c223ab20ea8860fcd96b7946ae; retained terminalJSON/log tmp/rune-measure/C-serial-rc03/report-ci-final.json and report-fast-final.log. Hibiscus independently reviewed report/raw sixphases/thirteencommands/counts/timestamps/graph/errors/hash/terminalhost evidence PASS00:15, no host operations. All four AC verified, closing Done. Stable/personalapproval and experimental Norway deployment remain outside this ticket. Follow-up STATBUS598 stays ToDo, not claimed resolved.
<!-- SECTION:NOTES:END -->
