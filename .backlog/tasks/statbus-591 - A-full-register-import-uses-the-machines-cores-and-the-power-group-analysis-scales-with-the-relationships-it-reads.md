---
id: STATBUS-591
title: >-
  A full register import uses the machine's cores, and the power-group analysis
  scales with the relationships it reads
status: In Progress
assignee: []
created_date: '2026-11-07T12:31:00Z'
updated_date: '2026-11-07T16:27:00Z'
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
A full register imports in time proportional to its rows, using the machine's cores, so a country-sized load finishes in well under an hour.

### Zoom out
Work that can be split must be split, and the dependencies that prevent splitting must be found by the analysis, not assumed for every row.

### Zoom in
Run A on rune (2026-11-07, rc.18, full BRREG downloads, 62 GB RAM): legal units analysis 13m 36s and processing 36m 24s (519 rows/s); establishments 12m 25s + 27m 50s (493 rows/s); relationships analysis (power_group_link step) about 40 min for 33,710 rows, processing at 491 rows/s. The import queue runs one job and one batch at a time (concurrency 1), so it is the longest path of the whole load: on the local BRREG benchmark, import_job_process was 6,090 s of the 6,737 s worker wall (doc/performance/2026-11-history-delta-measurements.md section 7).

Two parts:
1. **Import speed in general.** Owner's ideas (2026-11-06): import jobs stay serial (one job can depend on another), but one job can run its batched steps concurrently. Each step has an analyse and a process phase, run either as one holistic pass (external_idents, link_establishment_to_legal_unit, power_group_link) or in batches (all others). Batched steps are the natural candidates. The analysis already learns which rows go together; reuse the derive pipeline's two-level hashing for import batches while respecting those dependencies. Open question: hash on unit identity (as statistical_unit's hash_slot type:id) or independent of it; new units have no id yet. Also: import valid_from should come from the start of the year or the file's date, not the day the import runs (samples/norway/brreg/brreg-import-downloads-from-tmp.sh, TODAY).
2. **power_group_link analysis.** import.analyse_power_group_link builds the whole relationship graph in one recursive query (all legal_relationship rows plus the job's rows, walked from every root legal unit), even when legal_relationship is empty, as on a fresh load. On rune it ran about 40 minutes for 33,710 rows.

Evidence: tmp/rune-measure/A/ (watch.log, pg-now-*.txt, pg-wait-*.txt).

### Closing review
- **Memory:** none expected.
- **Documentation:** doc/import-system.md (step concurrency), doc/performance.
- **Cleanup:** none expected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One import job processes its batched steps concurrently, respecting the row dependencies the analysis finds; the full BRREG downloads import on rune completes with the same rows as a serial run (row-for-row comparison of the resulting units) in measured shorter wall time
- [ ] #2 import.analyse_power_group_link takes time proportional to the relationships it reads: on rune's full relationships file (33,710 rows) it gives the same derived power groups as today in a measured time recorded in this ticket
- [ ] #3 The import's valid_from comes from a declared date (start of year or file date, decided with the owner), not the day the import runs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 hibiscus, AC2 locally (rune check comes with run B): import.analyse_power_group_link joined rows and legal_relationship to the hierarchy on (influencing = id OR influenced = id), a nested loop over the hierarchy per row. Rewritten as two equality joins (e3acc80fd, test 79992db0c). Same local file as rune (29,503 'use' rows): fresh load 264 s -> 0.7 s; reload 171 s -> 2.0 s. Same 69,089 (row, root, power group) pairs; on reload every row's power group equals the one process_power_group_link linked. Test 372 (12,000 rows): 25.0 s f -> 0.27 s t. Evidence tmp/591/, journal 2026-11-07 13:35. Rune run A's ~40 min for this step includes the process step and waits; run B will show the new number.

Rune run A (rc.18, 2026-11-07): relationship job analysis 12:06:40-12:25:47 (1,147 s); of it one import_job_process task of 1,024 s is the holistic power_group_link analysis on the fresh load. Whole load: import queue 6,625 s span (6,539 s task time); load wall to idle 10,240 s. tmp/rune-measure/A/summary.md.

Part 1 design notes (hibiscus 2026-11-07, not started, needs owner decisions). Run A import task time: LU analysis 811 s + processing 2,139 s; ES 739 + 1,643; processing = 142 + 103 batches of 8,000 rows at 12-35 s each, strictly serial (import queue concurrency 1; the job reschedules one task per unit of work). The worker already runs concurrent children with N fibers (analytics). Proposal: in processing_data, one import_job_process task spawns one child per batch under a concurrent parent; import queue concurrency N; holistic process steps and 'finished' run after the children, as the next serial sibling. Batches must not share a unit: assign processing batches by a hash of the unit the analysis resolved (legal_unit_id for LU and ES rows, so establishments of one legal unit stay in one batch and primary demotion never races; founding_row_id groups stay together), not by row_id ranges. Shared counters (import_job.imported_rows) become one update after the children. Decisions needed: (a) hash on resolved unit id vs row ranges for new units (new units have no id: use founding_row_id); (b) N; (b) whether analysis batches also go concurrent (smaller gain: ~1-3 s per task). Evidence tmp/rune-measure/A/import-tasks.out, journal 13:57.

2026-11-07 16:16 design draft: doc/import-concurrent-batches-design.md (grouping by founding_row_id / legal_unit_id, two-level slots, why batch numbers need only be fixed per job, trigger-toggling batches stay serial).

2026-11-07 16:27 mixed imports: batches with updates call sql_saga.disable_temporal_triggers (ALTER TABLE, table lock + global state), so they stay serial this round. A transaction-local 'delay checks to commit' in sql_saga would let them run concurrently: task written to ../sql_saga/todo.md (Backlog, 'Delay temporal FK checks to commit'), for a separate agent. Grouping fix 31b842d4c (test 373) done.
<!-- SECTION:NOTES:END -->
