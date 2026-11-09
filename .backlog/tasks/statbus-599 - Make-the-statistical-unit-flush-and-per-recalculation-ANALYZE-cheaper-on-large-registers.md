---
id: STATBUS-599
title: >-
  Make the statistical-unit flush and per-recalculation ANALYZE cheaper on large
  registers
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-09T12:19:00Z'
updated_date: '2026-11-09T20:43:00Z'
labels:
  - performance
  - worker
dependencies: []
references:
  - STATBUS-598
priority: medium
type: spike
ordinal: 515204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star

After a large import, the full-register recalculation reaches idle sooner, with identical statistical_unit, history and report rows.

### Zoom out

STATBUS-598 removed three derive overheads: oversized refresh payloads, the change-set temp table, and full scans in the used-code views. The largest remaining step that runs one batch at a time is statistical_unit_flush_staging: 607-659 s on the biggest recalculation of a full BRREG import, when about 1.2M rows merge into the 9 GB statistical_unit table with 40 indexes. Every recalculation also runs a fixed ~7 s ANALYZE of that table, and a full import triggers 28-40 recalculations.

### Zoom in

Measure before changing. On a retained full register (import_benchmark_64469), replay the 1,855-batch cycle in a rolled-back transaction and time the flush phases separately: DELETE, MERGE, TRUNCATE and ANALYZE. Measure how much of the MERGE is index maintenance, using a private clone with groups of indexes removed. Check whether ANALYZE can be limited (sampled columns, skipped when few rows changed, or once per import) without worse plans in later cycles. Prepared script: tmp/598/flush-profile-plan.sql in the Hibiscus checkout.

Scope: no import concurrency, no release or host operation. Timing only on a quiet machine or dev (owner, 2026-11-09 12:09).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A statement-level profile of the largest flush cycle names where the time goes (DELETE, MERGE, index maintenance, ANALYZE), with source, data and machine context.
- [ ] #2 Any adopted change has a regression test that fails before and passes after, exact statistical_unit and history parity on a real-worker run, a paired migration with schema docs, and hosted CI.
- [ ] #3 If no change is worthwhile, the ticket records a measured rejection and no runtime change.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-09 15:10UTC Hibiscus: started on owner request. Step 1 is a rolled-back statement-level profile of the largest flush cycle on retained import_benchmark_64469 (local, machine idle, no import or test suite running).

2026-11-09 20:44UTC Hibiscus: profile done, first change implemented, not yet landed.

Profile of the largest flush (cycle 37368 of retained import_benchmark_64469, 1,812,369 staged rows, rolled back, idle machine; journal tmp/591/journal.md):
- Replay of the cycle's 1,855 refresh batches into staging: 52 min in one session. Flush 201 s: DELETE 135 s, MERGE 63 s, ANALYZE of statistical_unit ~3 s. The replayed content was already final, so this was pure matching cost (no rows deleted or updated).
- Cause: staging is truncated after each flush and never analyzed before the next, so the planner estimated about 157,000 units instead of 1,812,369 and matched them one at a time through statistical_unit_temporal_pk. With staging analyzed first, the same statement uses hash joins.
- Same staged rows, unchanged content: today 220.9 s (DELETE 149.5 + MERGE 68.4); staging analyzed first 24.5 s (DELETE 9.4 + MERGE 12.2), analyze 2.4 s.
- Correction to the description: the current flush (migration 20260507131230, DELETE + MERGE with skip-unchanged) keeps the indexes. Index drop/recreate existed only in the February 2026 flush; admin.drop/create_statistical_unit_ui_indices have no callers now.

Drop/recreate indexes around the flush (39 droppable indexes, staging analyzed first, rolled back):
- 181,355 rows really changed (6% of 3.1M): keep indexes 170 s; drop + flush + recreate 0.1 + 49 + 264 = 314 s.
- 1,812,365 rows changed (58% of the table): keep 891 s; drop + flush + recreate 1 + 302 + 407 = 710 s.
- Rebuilding the indexes costs 264-407 s whatever the change size, so dropping wins only when a large share of the table changes. Owner 20:18: not an obvious win; not pursued now.

Change 1 (adopt): migration 20261109201951 analyzes public.statistical_unit_staging at the start of statistical_unit_flush_staging, before DELETE and MERGE. Not size-dependent: a small staging gets a small estimate and keeps index lookups.
- Test 394_statbus_599_flush_analyzes_staging: RED on the original flush (staging never analyzed, no column statistics) -> GREEN (analyzed, statistics name the flushed unit types).
- Full-register proof with the real old and new procedures, same 1,812,369 staged rows of which 181,356 really changed: old 484.8 s, new 276.0 s (-43%); resulting statistical_unit rows identical (1,812,369 rows, same fingerprint).
- Remaining: fast suite, schema docs, commit on statbus-599-flush-staging-statistics (based on master cb5381f82), hand to Rabbit for the release after rc.04.
<!-- SECTION:NOTES:END -->
