---
id: STATBUS-599
title: >-
  Make the statistical-unit flush and per-recalculation ANALYZE cheaper on large
  registers
status: Done
assignee:
  - hibiscus
created_date: '2026-11-09T12:19:00Z'
updated_date: '2026-11-09T21:17:00Z'
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

STATBUS-598 removed three derive overheads: oversized refresh payloads, the change-set temp table, and full scans in the used-code views. The largest remaining step that runs one batch at a time was statistical_unit_flush_staging. On the biggest recalculation of a full BRREG import it matches about 1.8M staged rows against the 9 GB statistical_unit table with 40 indexes. In the live runs that cycle took 607 s and 659 s, with four refresh workers and autovacuum running alongside. Replayed alone it took 201 s, of which matching (DELETE 135 s, MERGE 63 s) was nearly all.

### Zoom in

The matching was slow because staging is truncated after every flush and was never analyzed before the next one. The planner estimated about 157,000 staged units instead of 1,812,369 and matched them one at a time through statistical_unit_temporal_pk. The flush now analyzes staging first, so it uses hash joins for large loads and index lookups for small ones. The current flush keeps its indexes; dropping and recreating them around large flushes was measured and not pursued (rebuilding all 39 costs 264-407 s, more than the maintenance it saves unless about half the table changes).

Scope: no import concurrency, no release or host operation. Timing only on a quiet machine or dev (owner, 2026-11-09 12:09).

### Closing review

Memory: none needed; the behavior is defined in the flush procedure's own comment. Documentation: the paired schema doc for statistical_unit_flush_staging was regenerated; the measurements stay in this ticket. Cleanup: preserve import_benchmark_64469 and the measurement scripts and logs while related work is open; any database removal needs separate named approval.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A statement-level profile of the largest flush cycle names where the time goes (DELETE, MERGE, index maintenance, ANALYZE), with source, data and machine context.
- [x] #2 [Owner] The adopt-or-reject decision for each measured change is recorded in Implementation Notes. Adopt requires a regression test that fails before and passes after, identical statistical_unit rows on the full register, a paired migration with schema docs, and hosted CI on master; reject requires the measured reason and no runtime change.
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

2026-11-09 21:16UTC Hibiscus: change 1 landed on master. Rabbit cherry-picked c93b30c95 unchanged as da4402a41 (patch-id equal), pushed 20:55. Test renumbered to 396_statbus_599_flush_analyzes_staging (394 was taken by 394_recalculate_all). Local clean-tree fast at c93b30c95: 136/136 + 094 + 143, stamp c93b30c95. Hosted Fast 42698105933 at exact da4402a41: checkout and stamp da4402a41 (source 20261109201951), 136/136 + 094 + 143 passed, including 396; all seven da4402a41 workflows completed/success. Owner decision (AC2): adopt change 1 (owner 20:18); index drop/recreate rejected for now with the measured reason above (rebuild 264-407 s outweighs maintenance below ~half the table changing). Ships in the release after v2026.11.3-rc.04.
<!-- SECTION:NOTES:END -->
