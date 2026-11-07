---
id: STATBUS-591
title: >-
  A full register import uses the machine's cores, and the power-group analysis
  scales with the relationships it reads
status: In Progress
assignee: []
created_date: '2026-11-07T12:31:00Z'
updated_date: '2026-11-07T17:14:00Z'
labels:
  - import
  - performance
dependencies: []
type: enhancement
ordinal: 499204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A full register imports using the machine's cores, so country-sized loads finish well under an hour without changing their resulting business data.

### Zoom out
Import jobs remain serial because one job can depend on another. Analysis identifies the row dependencies that determine which processing batches of one job can run concurrently.

### Zoom in
Rune run A (November 7, 2026, rc.18, full BRREG, 62 GB RAM): legal-unit analysis 816 s and processing 2,184 s, establishment analysis 745 s and processing 1,670 s. Relationship analysis 1,147 s includes a 1,024 s holistic power_group_link call. Import queue span 6,625 s, task time 6,539 s, full load to idle 10,240 s. Evidence: tmp/rune-measure/A/summary.md.

Scope:
1. Concurrent dependency-closed processing batches within one import job. Whole founding units and establishments sharing a legal-unit parent stay together. Two-level import hash slots remain fixed for the job lifetime, independently of derive unit slots. First scope is new insert-only legal units and formal establishments. Mixed/existing/informal jobs retain serial behavior pending safe temporal-check deferral and dependency proof.
2. Faster power-group analysis and holistic processing while preserving reference mappings, memberships, root classification and levels. Measure both stale first-load statistics and reload behavior.
3. A declared import valid_from date, chosen with the owner as start of year or file date, rather than execution day.

Implementation design and measured local evidence: doc/import-concurrent-batches-design.md and the notes below. Local import-speed work stays on statbus-591-import-speed until owner review. Rune validation is separate from rabbit's history-release upgrade U and clean run B.

### Closing review
- Documentation: dependency/concurrency design, doc/import-system.md, measured performance evidence.
- Verification: exact serial-domain parity, failure/replay/barrier behavior, full fast suite, real worker measurements and rune acceptance.
- Cleanup: retain diagnostic scripts and logs in tmp/. Do not delete benchmark databases or production data automatically.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One import job processes its batched steps concurrently, respecting the row dependencies the analysis finds; the full BRREG downloads import on rune completes with the same rows as a serial run (row-for-row comparison of the resulting units) in measured shorter wall time
- [ ] #2 Power-group analysis produces the exact reference relationship/root/group mappings on graph-size scaling fixtures and on rune's 33,710-row BRREG file, with scaling measurements and a rune runtime faster than the recorded 1,024-second rc.18 baseline
- [ ] #3 The import's valid_from comes from a declared date (start of year or file date, decided with the owner), not the day the import runs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 hibiscus, AC2 locally (rune check comes with run B): import.analyse_power_group_link joined rows and legal_relationship to the hierarchy on (influencing = id OR influenced = id), a nested loop over the hierarchy per row. Rewritten as two equality joins (e3acc80fd, test 79992db0c). Same local file as rune (29,503 'use' rows): fresh load 264 s -> 0.7 s; reload 171 s -> 2.0 s. Same 69,089 (row, root, power group) pairs; on reload every row's power group equals the one process_power_group_link linked. Test 372 (12,000 rows): 25.0 s f -> 0.27 s t. Evidence tmp/591/, journal 2026-11-07 13:35. Rune run A's ~40 min for this step includes the process step and waits; run B will show the new number.

Rune run A (rc.18, 2026-11-07): relationship job analysis 12:06:40-12:25:47 (1,147 s); of it one import_job_process task of 1,024 s is the holistic power_group_link analysis on the fresh load. Whole load: import queue 6,625 s span (6,539 s task time); load wall to idle 10,240 s. tmp/rune-measure/A/summary.md.

Part 1 design notes (hibiscus 2026-11-07, not started, needs owner decisions). Run A import task time: LU analysis 811 s + processing 2,139 s; ES 739 + 1,643; processing = 142 + 103 batches of 8,000 rows at 12-35 s each, strictly serial (import queue concurrency 1; the job reschedules one task per unit of work). The worker already runs concurrent children with N fibers (analytics). Proposal: in processing_data, one import_job_process task spawns one child per batch under a concurrent parent; import queue concurrency N; holistic process steps and 'finished' run after the children, as the next serial sibling. Batches must not share a unit: assign processing batches by a hash of the unit the analysis resolved (legal_unit_id for LU and ES rows, so establishments of one legal unit stay in one batch and primary demotion never races; founding_row_id groups stay together), not by row_id ranges. Shared counters (import_job.imported_rows) become one update after the children. Decisions needed: (a) hash on resolved unit id vs row ranges for new units (new units have no id: use founding_row_id); (b) N; (b) whether analysis batches also go concurrent (smaller gain: ~1-3 s per task). Evidence tmp/rune-measure/A/import-tasks.out, journal 13:57.

2026-11-07 16:16 design draft: doc/import-concurrent-batches-design.md (grouping by founding_row_id / legal_unit_id, two-level slots, why batch numbers need only be fixed per job, trigger-toggling batches stay serial).

2026-11-07 16:27 mixed imports: batches with updates call sql_saga.disable_temporal_triggers (ALTER TABLE, table lock + global state), so they stay serial this round. A transaction-local 'delay checks to commit' in sql_saga would let them run concurrently: task written to ../sql_saga/todo.md (Backlog, 'Delay temporal FK checks to commit'), for a separate agent. Grouping fix 31b842d4c (test 373) done.

2026-11-07 16:54 hibiscus: release handover is accepted by rabbit. origin/master contains7b171ac1c unchanged plus72f1d7fd1, stable v2026.11.1 published separately. All591 implementation remains local-only on statbus-591-import-speed, owner review before push. Whole-slot packing regression260a95d6d exposed numeric rounding (20 singleton rows,size4 gave2/4/4/4/4/2) and split hash slots. ef810daba fixes explicit floor division and indivisible import slots. Test373 passes and full fast suite passes127 shared+2 isolated, tmp/591/test-fast-grouping.log. Generated explain/performance artifacts reverted. Import group hash keys do not equal derive unit hash keys, so no derive-locality speedup is claimed. Trigger DDL is transactional, the demonstrated mixed-job blocker is table-lock serialization, not a proved enable/disable visibility race. Updated SQL Saga handoff accordingly. Draft concurrent scheduler preserves atomic imported_rows increments at each batch transaction tail for live progress, instead of an unmeasured final-only counter. Existing worker fan-out/fan-in barrier proved by rollback trace: wrapper,dispatch,leaf_a,leaf_b,finalize,next_job. Real multi-connection row-parity prototype now running. No rune validation yet, AC1/AC2 remain open.

2026-11-07 16:55: Real simultaneous PostgreSQL connections passed exact normalized domain-row parity for400new legal units and800new formal establishments. Original serial processing20.437s, N=2 8.415s, N=4 7.791s, N=8 7.847s. Concurrent leaf counts60 and observed active leaves2/4/8. Nine domain tables and exact imported counters agree. Evidence tmp/591/parity-results.json and concurrent-acceptance-v2.log. This is a small acceptance fixture, not a full-register or rune speed claim. SQL375 also detected a real failure propagation defect (failed job, completed wrapper), preserved failing evidence and root is repairing it before promoting the scheduler prototype.

2026-11-07 17:09: Regression-before-implementation375 committed12b531485. Scheduler5fcf8c4b2 adds clean new-LU/formal-ES fan-out with whole dependency batches, serial job/holistic barriers, replay-safe atomic counters, and failure after-hook outside worker savepoint. Default import concurrency remains1. Original failed-job/completed-wrapper case now yields failed leaf+job+wrapper with zero partial domain writes. Both directions of20261107164600 verified privately, down restores exact live original function and up/down/up matches. Local seed/dev integrated, paired doc/db regenerated without deletions. Named373/374/375 passed the real dev.sh harness. Full fast suite and real Crystal BRREG selection N1/2/4/8 still pending/running. No import-speed branch push or rune mutation.
Power-group processing1caea283a: remove redundant merge-candidate nonnull filter and use equivalent EXCEPT BFS seeds. Synthetic6kgroup first-load31.535s->4.463s for predicate fix. A29,503-edge BRREG graph replay after predicate fix51.576s->13.863s with EXCEPT seeds, all canonical relationship and444power_root rows identical. This replay uses synthetic LU metadata, not a full production import.374detects old runtime regression, final374+117/118/119/120/366 all6pass. Diagnostics tmp/591/pg-process-journal.md and pg-process-regress-suite/. AC1/AC2 remain unverified on rune, AC3 date choice remains open.
<!-- SECTION:NOTES:END -->
