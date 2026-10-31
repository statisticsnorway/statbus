---
id: STATBUS-555
title: >-
  Test 401: derive_statistical_history_period children run 17-78 min each and
  the 4 GiB run is OOM-killed
status: To Do
assignee: []
created_date: '2026-10-31T03:54:00Z'
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
Every partial derive of statistical_history goes through derive_statistical_history_period children. STATBUS-543 (2a915aac2, 20261030133114, 20261030135034) changed how they are spawned and how each child deletes and rebuilds; dev's real import improved 47 min -> 3 min, but 401's larger history now stalls. If one child can run for an hour and grow past the container limit, a real import on a 4 GiB box would stop the worker the same way.

### Zoom in
STATBUS-480 run (worker chipmunk, /Users/jhf/ssb/statbus_test at 387bf0c2b, DB_MEM_LIMIT 4G): one child {year 2026, month 4, year-month, hash_partition [4096,8192)} at 100% CPU from 00:36:14 until the backend was killed by signal 9 at 01:53:57 (about 78 min); 69 siblings had finished; the test lost its connection. Rerun at 8G (5bc6017a9 tree): a different child {year 2025, month 4, [12288,16384)} at 100% CPU for 17+ min at ~1.7 GiB; 168 tasks done, 59 pending at 03:07. Logs and the monitor are in statbus_test/tmp/ (480-review.md, test-480-401*.log).

### Closing review
Record the cause in tmp/journal.md; doc/db regenerated if a function changes; no memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The slow child is reproduced on its own (EXPLAIN ANALYZE of the child's statements on 401's data) and the cause recorded in tmp/journal.md
- [ ] #2 After the fix test 401 completes under DB_MEM_LIMIT 4G, its derive children each finish in seconds, and the run's wall time is recorded
- [ ] #3 401's expected output is then re-blessed with every hunk explained, under the same two-review process as STATBUS-480
<!-- AC:END -->
