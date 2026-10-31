---
id: STATBUS-198
title: >-
  One source of truth for running the BRREG import: the loader script, the
  measuring runner, no test 500
status: To Do
assignee: []
created_date: 2026-08-01 10:44
updated_date: '2026-10-31T13:29:00Z'
labels:
  - harness
  - testing
  - import
  - performance
  - not-install-upgrade
dependencies: []
priority: medium
type: bug
ordinal: 198000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
Running the BRREG import exists once. A loader script loads the data, the same way on a Norwegian installation and in a measurement run. test_concurrent_worker is the one tool that measures it, through the real worker.

## Zoom out
The original premise was wrong. Test 500 never ran the whole import in one transaction: it commits before CALL worker.process_tasks, which commits after every task. But test 500 is a weaker copy of what already exists. It processes inside the test session rather than through the worker, skips analytics, and is never run by CI.

## Zoom in
Today the 'create jobs and load the CSVs' step exists three times:
- samples/norway/brreg/brreg-import-downloads-from-tmp.sh (and brreg-import-selection.sh): the loaders, used by ./cloud.sh import <target> downloads|selection on a live installation.
- test/test_concurrent_worker.py: repeats the job creation and \copy in its own Python, with different job slugs. It shares only the definition SQL files. It then runs cli/bin/statbus worker --stop-when-idle in an isolated database from the test template and prints a timing table per command.
- test/sql/500_import_jobs_for_brreg_downloads.sql: a third copy.

## Order
After STATBUS-555 (the speed regression); its evidence comes from test_concurrent_worker as it is today.

## Closing review
rg shows no reference to test 500, and no second copy of the job-creation and load logic.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The BRREG loader scripts (downloads and selection) can target a given database, and remain the way ./cloud.sh import loads an installation
- [ ] #2 test_concurrent_worker calls those loader scripts instead of its own job creation and copy code, for both --dataset selection and --dataset downloads
- [ ] #3 Test 500 and its expected output are removed, and docs and conventions point to test_concurrent_worker for the full import
- [ ] #4 A selection run of test_concurrent_worker after the change completes and prints the timing table
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-31, rewritten with the owner: the original premise (one transaction) was wrong, so this ticket now carries the cleanup to one source of truth. Grounding: test_concurrent_worker selection run on 2026-04-29 took 494 s (tmp/test_concurrent_44233.log); downloads runs on 2026-02-08, one success and one crash (server closed the connection), with an older script.
<!-- SECTION:NOTES:END -->

## Status 2026-09-24

**To Do:** #1-4 not met: `test/sql/500_import_jobs_for_brreg_downloads.sql` still calls the whole import synchronously and pauses for one hour (`7a0facee9` ticket history only). **Remaining:** drive bounded multi-transaction worker batches, sustain pause, regenerate real expected output, and document the regression rule.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Reconciliation 2026-09-23

Classification: OPEN. Evidence: test 500 still carries the single-transaction redesign as unimplemented acceptance. No part of the item's own done-when is complete beyond any design already recorded above.
