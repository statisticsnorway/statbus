---
id: STATBUS-555
title: >-
  Test 401: history derive children take ~50 s each (200-700x dev) and the run
  is OOM-killed in statistical_history_facet_reduce
status: Done
assignee:
  - hibiscus
created_date: '2026-10-31T03:54:00Z'
updated_date: '2026-10-31T16:29:00Z'
labels:
  - derive
  - performance
  - worker
dependencies: []
priority: high
type: bug
ordinal: 478204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: test 401 (BRREG selection import) finishes its analytics in minutes, as it did in July (86.8 s for the whole test), within a 4 GiB database.

### Zoom out
Every partial derive of statistical_history goes through derive_statistical_history_period children and then the facet reduce. STATBUS-543 (2a915aac2, 20261030133114, 20261030135034) changed how children are spawned and how each child deletes and rebuilds; dev's real import improved 47 min -> 3 min, but 401's larger history now takes over an hour and dies in the reduce. A real import of that size on a small box would stop the worker the same way.

### Zoom in
Two runs by worker chipmunk in /Users/jhf/ssb/statbus_test (details and logs in Implementation Notes, statbus_test/tmp/test-480-401*.log, tmp/mon-401-8g.log):
- 4G run (387bf0c2b): backend killed by signal 9 after about 80 min.
- 8G run (5bc6017a9 tree): 68m12s, exit 2. All 76 derive_statistical_history_period children completed, avg 50.0 s, max 66.9 s (year 2026 [4096,8192)); dev's children took 69-235 ms. Then OOM-killed (signal 9) in statistical_history_facet_reduce at 03:56:06Z. Peak sampled memory 2.30 GiB at 30 s intervals; the spike fell between samples. The Docker VM has 7.75 GiB in total, shared with the other stack, so this run does not show whether the reduce would fit within 8 GiB on its own.
- Correction: the earlier reading of a single 17-78 min child came from worker.tasks.created_at, not the process start; per-child time is ~50 s.

### Closing review
Record the cause in tmp/journal.md; doc/db regenerated if a function changes; no memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The slow child is reproduced on its own (EXPLAIN ANALYZE of the child's statements on 401's data) and the cause recorded in tmp/journal.md
- [x] #2 After the fix test 401 completes under DB_MEM_LIMIT 4G, its derive children each finish in seconds, and the run's wall time is recorded
- [x] #3 401's expected output is then re-blessed with every hunk explained, under the same two-review process as STATBUS-480
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
8G rerun evidence (2026-10-31, statbus_test, working tree 5bc6017a9, DB_MEM_LIMIT=8G, db container recreated, docker inspect Memory=8589934592):

- Wall time 4,092,262 ms (68m12s), test process exit code 2. db log: client backend (PID 94) terminated by signal 9: Killed; database system in recovery. docker inspect: State.OOMKilled=true.
- Environment limit: docker info MemTotal=8,319,504,384 (~7.75 GiB). The 8 GiB container limit exceeds the Docker VM total, so this kill is VM-level memory exhaustion shared with the other stacks; the 8G run does NOT establish that the crash is independent of the memory cap.
- Sampled container memory (30s interval, 122 samples): max 2.30 GiB at 03:53:53Z (MemUsage 2.246GiB). The fatal spike fell between samples.
- Crash point: all 76 derive_statistical_history_period children completed. The only processing task at the kill was statistical_history_facet_reduce (started 03:54:05Z, killed 03:56:06Z). The OOM is in the reduce phase, not in a period child.
- Per-child durations, derive_statistical_history_period (76 completed): avg 49,972 ms, max 66,865.6 ms. Slowest five (process_duration_ms, period, hash_partition):
  1. 66,865.6 ms, year 2026 (year resolution, month null), [4096,8192)
  2. 61,559.9 ms, 2026-02, [0,4096)
  3. 58,606.3 ms, year 2026 (month null), [8192,12288)
  4. 56,467.3 ms, year 2026 (month null), [12288,16384)
  5. 55,912.4 ms, 2026-05, [8192,12288)
- STATBUS-543 dev reported 69-235 ms per child; 401 children average ~50 s, roughly 200-700x slower. 76 x ~50 s is the ~63 min serial phase.
- Correction to this ticket title and Zoom in: the "17+ min / 78 min single child" readings came from worker.tasks.created_at, not process_start_at. No child ran that long. Both the 4G and 8G runs spend ~60-68 min serially in ~76 history-period children (~50 s each), then OOM at the reduce step. The 4G run's per-child rows are gone (DB dropped), but its log shows the analytics CALL terminated by signal 9 at 01:53:57 after 78 min, consistent with the same serial phase plus reduce.
- Facet period children are fast: derive_statistical_history_facet_period 76 completed, avg 182 ms, max 233 ms.
- Evidence: statbus_test/tmp/test-480-401-8g.log, tmp/mon-401-8g.log, tmp/test-480-401.log (4G). Leftover test DB dropped; no code or expected-file changes for 401.

2026-10-31 hibiscus: likely a regression from STATBUS-543. History period children took ~221 ms each on the same selection data in April (tmp/test_concurrent_44233.log), against ~50 s now. Suggests comparing one child's plan before/after 543 before any memory work.

2026-10-31 hibiscus, cause found. Not 543's logic: PL/pgSQL switches statistical_history_def to a generic plan from the 6th execution in a session. The worker runs many history children per session. Without the partition range and period values the generic plan estimates ~5-11 units (actual 2388), and chooses a seq scan and nested-loop joins that discard 7.8M rows. Same child in one session (tmp/555-repeat-same-session.log): calls 1-5 = 67-106 ms, calls 6-10 = 4.2-4.9 s. Before 543 children were tiny, so the bad plan cost little; 543 made each child cover a partition range, which exposed it. Prototype removing the optional OR (tmp/555/B-generic.log): index used but still nested loops, 4.4 s, so the date parameters keep the generic estimate wrong. Fix: migration 20261031135820, ALTER FUNCTION statistical_history_def SET plan_cache_mode = force_custom_plan, with COMMENT ON. Survey of all child commands, 8 calls per session (tmp/555/repeat-all.txt): only derive_statistical_history_period flips. Test: test_concurrent_worker now replays every child command 8 times in one session and records first vs last into test/expected/performance/test_concurrent_worker_repeated_calls.perf, exiting 1 on a ratio above 3x. RED on the pre-fix db: 81.4 -> 3606.6 ms (44.31x). GREEN on the same db after the migration: 58.2 -> 62.8 ms (1.08x). End to end, selection (tmp/555-fixed-selection.log): worker 35.8 s (was 105.7 s), history children avg 55.9 ms (was 2091 ms). Fast suite 117/117 locally (tmp/test-555-fast.log). Waiting for rc.07 cut, then commit; then 401 under 4G.

Pushed c3ed0beff; Fast Tests 41209646223 success. Going into v2026.10.6-rc.07 (rabbit cutting). Remaining: AC#2 401 under 4G after the fix; AC#3 401 expected re-bless if it changes.

AC#2: test 401 at DB_MEM_LIMIT=4G (statbus_test, master 02b801d4d = rc.07 + backlog, container Memory=4294967296) completed in 144.6 s (wall 159 s with migrate), peak ~3.35 GiB, OOMKilled=false (tmp/test-555-401-4g.log, tmp/mon-555-401-4g.log). Before the fix: OOM at 4G after ~80 min, and 68 min then OOM at 8G. 401 fails only on 3 explained hunks (tmp/555-401-4g.diff): import_job_process tasks 97->103 and the import completed count 99->105 (x3), +6 = 610c42995 (STATBUS-461, +1 task per analysis batch, 6 batches), as classified in statbus_test/tmp/480-review.md. No analysis_status drift and no history or facet changes. Expected re-blessed from that run; the read-only reviewer is checking.

AC#3: 401 expected re-blessed from the 4G run. Read-only reviewer cow APPROVED: all 4 hunks come from 610c42995 (STATBUS-461 date_consistency step, +3 tasks per job: discovery, one batch and completion, x 2 single-batch jobs = +6). No analysis_status drift, and the crash-truncated analytics tail is byte-identical. Correction to the 480 review rationale: '+1 task x 6 batches' was wrong; 2 jobs x 3 tasks is right, and the attribution stands.

Fast Tests 41218280651 success on 4ab621894 (401 re-bless). The cause was reproduced on its own and recorded in tmp/journal.md (AC#1: same child, calls 1-5 vs 6-10 in one session; generic plan via auto_explain). statbus_test restored to DB_MEM_LIMIT=8G and clean; 401's perf recording from the 4G run is kept in statbus_test/tmp/555-401-4g.perf, not committed.

Final loop over the whole result at 69c802fda (tmp/555-final-selection.log): selection through the real worker 40.0 s, history children avg 66.6 ms; the repeated-call check runs at the end and reports every command between 0.14x and 1.69x, none flagged, exit 0. Migration down and up on seed (./sb migrate redo 20261031135820) leaves plan_cache_mode set and the comment present. CI on 4ab621894: Fast Tests, Go Test, app build & lint and Images all success. The 401 re-bless is in the next RC (after the rc.07 tag); the fix itself is in rc.07. Scratch test_concurrent_* databases dropped.

Independent check of reviewer cow's verdict: (1) the committed diff 4ab621894 equals the reviewed diff line for line (14 changed lines: 97->103 rows plus 6 task rows, and 99->105 x3). (2) 401 loads the 2024 BRREG definitions (test/sql/401 lines 39-40), and 610c42995 added date_consistency to both, so the attribution holds. (3) 610's own 303 change 376->400 (+24 for 8 jobs) confirms +3 per single-batch job. (4) No GOOD/OK/SLOW line changed; expected status stays ES OK/GOOD, LU OK/GOOD (lines 359-360). (5) The tail after the analytics section has the same length.
<!-- SECTION:NOTES:END -->
