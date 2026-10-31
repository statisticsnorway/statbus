---
id: STATBUS-480
title: >-
  Test 404_regression_albania_import is red and no CI runs it (expected file
  stale since 2026-03)
status: In Progress
assignee: []
created_date: 2026-10-08 16:57
updated_date: '2026-10-31T02:32:00Z'
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

FOUND during STATBUS-477 family A (2026-10-08). test/sql/404_regression_albania_import.sql fails against its test/expected file with 232 diff lines. The failure is IDENTICAL on a clone of master without 477 (statbus_477a_prefix, master at 20261008161441) and with 477 family A applied, so it is not a 477 regression. The expected file was last changed 2026-02-24 (3865fd3ba). The test SQL changed later (cc4b43670 2026-03-13, 1052fcd10 2026-03-18: the settings INSERT now names region_version_id) without re-blessing, and the run also now prints the person_ident index notices (Dropped/Created index su_ei_person_ident_idx), because test/setup.sql enables person_ident.

WHICH SUITE: dev.sh 'fast' excludes every 4xx and 5xx test (dev.sh test selector, 'Run all tests except 4xx/5xx (large imports)'). 404 runs only under './dev.sh test all' or './dev.sh test benchmarks' (4xx only), or by name.
WHICH CI: none. The only CI workflow that runs pg_regress is .github/workflows/fast-tests.yaml ('./dev.sh migrate-and-test fast'), which excludes 4xx. No workflow in .github/workflows runs 'test all' or 'test benchmarks', and .claude/team/tester.md says never to run 'test all'. So 404, and every other 4xx test, is run by nothing automatically. That is the worse half of this ticket: a test that nothing runs cannot protect anything, and its staleness went unnoticed for seven months.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 404's expected output is re-blessed after reviewing that every diff line is the notices and settings-column drift described, not a behaviour change
- [ ] #2 Decide and record which CI workflow runs the 4xx tests (or that they are deliberately manual), and make that true
- [ ] #3 The other 4xx tests (400-403) are checked for the same staleness
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-31 worker chipmunk ran 400-404 one at a time in /Users/jhf/ssb/statbus_test at 387bf0c2b (DB_MEM_LIMIT 4G); classification in statbus_test/tmp/480-review.md. 400 fail (6 sql_saga 1.3 notices, a4fa1e04f), 402 fail (same notices + import task counts +24, 610c42995 '+1 import task per analysis batch'), 403 PASS, 404 fail (17 hunks, all explained: person_ident notices 5e64a0dc8, test SQL drift 1052fcd10/cc4b43670, region rejections 562706aba, +tasks 610c42995, analytics counts 2a915aac2, sum_sq d506471b4). Coordinator review 1: all cited commits exist, are newer than the expected file, and state the claimed effect. Accepted for re-blessing: 400, 402, 404. 401: crashed (backend OOM-killed after ~78 min in derive_statistical_history_period 2026-04 [4096,8192) at 4G) and has a performance hunk (analysis_status GOOD->OK); not blessed, rerun at 8G pending. Re-bless diff to get a second review before commit.
<!-- SECTION:NOTES:END -->
