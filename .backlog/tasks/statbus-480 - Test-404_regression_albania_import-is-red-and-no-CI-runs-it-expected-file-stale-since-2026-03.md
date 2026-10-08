---
id: STATBUS-480
title: >-
  Test 404_regression_albania_import is red and no CI runs it (expected file
  stale since 2026-03)
status: To Do
assignee: []
created_date: '2026-10-08 16:57'
labels:
  - test
dependencies: []
priority: medium
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
