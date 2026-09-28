---
id: STATBUS-424
title: Fast Tests run as weight-balanced parallel shards with one verdict
status: To Do
assignee: []
created_date: '2026-09-28 08:18'
labels:
  - ci
  - tests
dependencies: []
priority: medium
ordinal: 373200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Purpose: cut the Fast Tests CI gate from ~15 min to ~7 min.

Measured (Fast Tests run on 2026-09-28): the pg_regress fast suite runs its 101 shared tests serially in one pg_regress process against one BEGIN/ROLLBACK-isolated clone (dev.sh SHARED_TEST_DB=test_shared_$$), 614 s total. By hundred: 0xx 22 tests 6 s, 1xx 30 tests 69 s, 2xx 5 tests 35 s, 3xx 44 tests 502 s (82%). Slowest: 310_idempotent_import_source_dates 171 s, 314 56 s, 344 40 s, 312 24 s, 309 23 s, 110 20 s. Splitting by hundreds alone leaves the 3xx block at ~8.5 min.

Proposal: a GitHub Actions matrix of ~4 shards balanced by recorded per-test time (310 alone in one shard), each on its own runner and Postgres, then one aggregate job that publishes the single Fast Tests verdict and exercised-sha marker that ./sb release check and the pass stamp read. Also investigate why 310 takes 171 s (full import twice?).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sharded run on a commit yields per-test results identical to a single-runner run on the same commit
- [ ] #2 ./sb release check and the fast-test pass stamp still read exactly one Fast Tests verdict
- [ ] #3 Fast Tests wall time measured and recorded before and after, target under 8 minutes
<!-- AC:END -->
