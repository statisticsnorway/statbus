---
id: STATBUS-555
title: >-
  Test 401: history derive children take ~50 s each (200-700x dev) and the run
  is OOM-killed in statistical_history_facet_reduce
status: To Do
assignee: []
created_date: '2026-10-31T03:54:00Z'
updated_date: '2026-10-31T04:00:00Z'
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
- [ ] #1 The slow child is reproduced on its own (EXPLAIN ANALYZE of the child's statements on 401's data) and the cause recorded in tmp/journal.md
- [ ] #2 After the fix test 401 completes under DB_MEM_LIMIT 4G, its derive children each finish in seconds, and the run's wall time is recorded
- [ ] #3 401's expected output is then re-blessed with every hunk explained, under the same two-review process as STATBUS-480
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
<!-- SECTION:NOTES:END -->
