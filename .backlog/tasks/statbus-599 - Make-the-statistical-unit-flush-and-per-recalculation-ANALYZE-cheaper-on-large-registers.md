---
id: STATBUS-599
title: >-
  Make the statistical-unit flush and per-recalculation ANALYZE cheaper on large
  registers
status: To Do
assignee:
  - hibiscus
created_date: '2026-11-09T12:19:00Z'
updated_date: '2026-11-09T12:19:00Z'
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
- [ ] #1 A statement-level profile of the largest flush cycle names where the time goes (DELETE, MERGE, index maintenance, ANALYZE), with source, data and machine context.
- [ ] #2 Any adopted change has a regression test that fails before and passes after, exact statistical_unit and history parity on a real-worker run, a paired migration with schema docs, and hosted CI.
- [ ] #3 If no change is worthwhile, the ticket records a measured rejection and no runtime change.
<!-- AC:END -->
