---
id: STATBUS-483
title: >-
  Get a grip on the very slow 4xx/5xx pg_regress tests: run them by hand first,
  measure, then decide
status: To Do
assignee: []
created_date: '2026-10-08 20:31'
updated_date: '2026-10-09 07:31'
labels: []
dependencies: []
ordinal: 409204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: we know how slow the 4xx and 5xx pg_regress suites really are on a real machine, with wall time and peak memory recorded per test, and we have a non-blocking way to run them that does not depend on anyone remembering. CONTEXT (owner, 2026-10-08): no CI workflow runs these suites at all - 'dev.sh test fast' excludes every 4xx and 5xx and nothing else includes them - which is why one of them has been failing since March unnoticed (STATBUS-480). They are extremely memory hungry and some 5xx tests may take a day or a week, so GATING IS IMPOSSIBLE and this ticket is explicitly NOT BLOCKING anything. The first step the owner wants is running them BY HAND on a machine that can run uninterrupted for a day or two or a week - a dedicated instance already exists for this at ../statbus_test - and measuring, before any automation is designed. NOT BLOCKING, LONG-STANDING: this has been so for a long time and is now recorded rather than discovered.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each 4xx and 5xx test runs to completion at least once on the dedicated instance, with wall time and peak memory recorded per test
- [ ] #2 The ticket states which tests are feasible to automate and which are not, with the measured reason
- [ ] #3 A non-gating automation design is proposed and approved by the owner: either a sharded non-blocking GitHub matrix (noting that GitHub-hosted jobs are capped at six hours) or an off-Actions schedule on a box, chosen explicitly
- [ ] #4 STATBUS-480's stale 404 expectation is repaired as part of the first run or alongside it
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Timings recorded from a real run on a real machine, not estimated
- [ ] #2 The automation design and its cost recorded with the owner's approval
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DEFERRED BY THE OWNER (2026-10-09): park this until every other in-progress ticket has been resolved and tried, then take it up when it is the only thing left. It is explicitly NOT a priority now. When it is picked up, the first step is unchanged: run these by hand, one at a time, in the dedicated instance at /Users/jhf/ssb/statbus_test (a full checkout at the current tip with its own environment), recording wall time and peak memory per test, starting with 404 as a short calibration and then 402 and 400 as the heavy ones, holding the 500 family for a genuinely quiet machine. The set is small: 400_import_benchmark, 401_import_jobs_for_brreg_selection, 402_import_jobs_for_norway_history, 403_cross_border_power_group, 404_regression_albania_import, 500_import_jobs_for_brreg_downloads - all six already have expected outputs. A start was deliberately NOT made on 2026-10-09 because several unrelated containers were running and free memory was about 120 MB; the owner stopped it before any run.
<!-- SECTION:NOTES:END -->
