---
id: STATBUS-198
title: >-
  test-500-one-transaction: whole BRREG import in ONE transaction — redesign to
  multiple transactions + fix the too-short worker.pause
status: To Do
assignee: []
created_date: '2026-08-01 10:44'
labels:
  - testing
  - import
  - performance
  - not-install-upgrade
dependencies: []
priority: medium
ordinal: 198000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: no test drives a million-row import inside a single transaction — tests exercise the import the way production runs it: batched, multi-transaction, worker-shaped.

FOUND (King diagnosis, 2026-07-31/08-01, during the STATBUS-188 acceptance): test 500_import_jobs_for_brreg_downloads processes its entire ~2M-row import (hovedenhet 1,134,476 + underenhet 823,768) via a single synchronous `CALL worker.process_tasks(p_queue => 'import')` in the test session — ONE transaction for the whole import. The King: "that's crisis level, and the reason we got test/test_concurrent_worker.sh to use multiple transactions."

OBSERVED CONSEQUENCES (both runs 2026-07-31): a "fast" run took 101 min; the verify re-run DEGRADED ~11x (~1,600 rows/min), its single CALL transaction reached 21 HOURS with the first import still unfinished and the test db at 17 GB — aborted server-side (pg_cancel_backend; clean exit, zero crash markers, test db dropped). A 21-hour transaction accumulates dead tuples no vacuum can reclaim mid-flight and starves the instance — the progressive slowdown is the single-transaction design, not just environment.

SECOND DEFECT, same test: `SELECT worker.pause('1 hour'::interval)` — the pause is shorter than the test's own runtime (101+ min even when healthy). King: "not sufficient." The pause must cover the real duration or be renewed/structured differently.

FIX SHAPE (King-offered direction): change test 500 to use multiple transactions — the test/test_concurrent_worker.sh pattern (each worker.process_tasks batch in its own transaction). Also right-size or restructure the worker.pause. The STATBUS-175 echo-suppression wrap for 500 (frozen in tree, uncommitted) rides this redesign: the expected file regenerates from the redesigned test's real run.

DISPOSITION: 500's conversion was the last piece of STATBUS-188's acceptance workload; 188 closes on 401+402 (landed 5b6e52f48) with 500's conversion re-carved to THIS ticket — the single-transaction design makes the current test unrunnable as an oracle in bounded time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Test 500 drives its imports through multiple transactions (test_concurrent_worker.sh pattern), never one CALL for the whole load
- [ ] #2 The worker.pause covers the test's real duration (sized or renewed), with the insufficiency class named in a comment
- [ ] #3 The redesigned test completes in bounded, predictable time on the dev harness and passes; the 175 echo-suppression wrap lands with it (expected regenerated from the real run)
- [ ] #4 A regression note prevents new tests from adopting the single-transaction whole-import pattern (comment in test 500 + reference in testing rules)
<!-- AC:END -->
