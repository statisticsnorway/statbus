---
id: STATBUS-480
title: >-
  Test 404 and the other 4xx tests had stale expected output; re-blessed with
  every hunk explained
status: Done
assignee: []
created_date: 2026-10-08 16:57
updated_date: '2026-10-31T16:39:00Z'
labels:
  - test
dependencies: []
priority: medium
type: bug
ordinal: 406204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: every pg_regress test in test/sql is both correct and run somewhere, so a red test is a signal rather than noise.

### Zoom out
A test that no suite runs can go stale unnoticed: 404 failed against its expected file for seven months because nothing ran the 4xx tests.

### Zoom in
FOUND during STATBUS-477 family A (2026-10-08). test/sql/404_regression_albania_import.sql failed against its test/expected file with 232 diff lines, identically with and without 477, so not a 477 regression. The expected file was last changed 2026-02-24 (3865fd3ba); the test SQL changed later (cc4b43670, 1052fcd10) without re-blessing, and test/setup.sql's person_ident adds index notices. dev.sh 'fast' excludes every 4xx and 5xx test, and no CI workflow runs 'test all' or 'test benchmarks'.

### Closing review
No memory or documentation update needed. Which CI runs the 4xx tests is now STATBUS-483; test 401's slow derive is STATBUS-555.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 404's expected output is re-blessed after reviewing that every diff line is the notices and settings-column drift described, not a behaviour change
- [x] #2 The other 4xx tests (400-403) are checked for the same staleness
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-31 worker chipmunk ran 400-404 one at a time in /Users/jhf/ssb/statbus_test at 387bf0c2b (DB_MEM_LIMIT 4G); classification in statbus_test/tmp/480-review.md. 400 fail (6 sql_saga 1.3 notices, a4fa1e04f), 402 fail (same notices + import task counts +24, 610c42995 '+1 import task per analysis batch'), 403 PASS, 404 fail (17 hunks, all explained: person_ident notices 5e64a0dc8, test SQL drift 1052fcd10/cc4b43670, region rejections 562706aba, +tasks 610c42995, analytics counts 2a915aac2, sum_sq d506471b4). Coordinator review 1: all cited commits exist, are newer than the expected file, and state the claimed effect. Accepted for re-blessing: 400, 402, 404. 401: crashed (backend OOM-killed after ~78 min in derive_statistical_history_period 2026-04 [4096,8192) at 4G) and has a performance hunk (analysis_status GOOD->OK); not blessed, rerun at 8G pending. Re-bless diff to get a second review before commit.

AC1 + AC2 (was AC3) done in c776548b9 (chipmunk, two coordinator reviews). 404 re-blessed: 17 hunks, each traced to a commit newer than the expected file (person_ident notices 5e64a0dc8; test SQL 1052fcd10/cc4b43670; region rejections 562706aba; +tasks 610c42995; analytics counts 2a915aac2; sum_sq d506471b4). 400 and 402 re-blessed (sql_saga 1.3 notices a4fa1e04f; +1 import task per analysis batch 610c42995). 403 already passed. Review 2: each expected-file diff equals the reviewed regression diff line for line; reruns pass (400 7.2 s, 402 666 s, 404 39 s); performance drift discarded. CI on c776548b9 green. The former AC2 (which CI runs the 4xx tests) moved to STATBUS-483, the owner's spike to run and measure the slow suites by hand first. 401 is not blessed: OOM-killed at 4G after a 78-min derive child; an 8G rerun shows several 17+ min children at ~1.7 GiB, so it is a runtime problem, filed separately.

2026-10-31 follow-up: STATBUS-555 (hibiscus, 4ab621894) fixed 401. At DB_MEM_LIMIT=4G it now completes in 145 s, peak ~3.35 GiB, no OOM, and is re-blessed: the +6 import tasks come from 610c42995, which adds 3 tasks per import job (discovery, batch, completion) x 2 jobs. That corrects the '+1 import task per analysis batch' wording used for 402 above, which is the same mechanism counted per job. All of 400-404 now pass.

2026-10-31 correction (hibiscus 16:39): 401 does not yet pass at 4G. The earlier 4G run exited 1, and a recheck was OOM-killed in the history facet phase: one derive_statistical_history_facet_period child (2026-05 [4096,8192)) ran ~4.7 min against siblings averaging 182 ms. STATBUS-555 is reopened for that second, intermittent memory problem. The 'All of 400-404 now pass' line above is withdrawn for 401.
<!-- SECTION:NOTES:END -->
