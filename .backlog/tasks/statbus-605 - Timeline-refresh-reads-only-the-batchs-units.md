---
id: STATBUS-605
title: Timeline refresh reads only the batch's units
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-10T11:32:00Z'
labels:
  - performance
  - worker
  - statistical-unit
dependencies: []
priority: high
ordinal: 519204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On the full register one establishment refresh batch of 333 units takes about 41 s, 28.3 s of it in timeline_establishment_refresh. The establishment_stats CTE in timeline_establishment_def aggregates all 115,428 establishments before the batch filter applies. STATBUS-581 fixed the same shape for legal units with timeline_legal_unit_def_for(ids). Give each timeline refresh (establishment, legal unit, enterprise, power group) a definition that reads only the batch's rows, with identical output.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each of the four timeline refreshes is measured on a real full-register batch (import_benchmark_64469), with time and plan recorded
- [ ] #2 Establishment refresh reads only the batch's establishments: a regression test fails before and passes after
- [ ] #3 Per-batch definitions give identical rows to the full view on real batches
- [ ] #4 Enterprise and power group refreshes are fixed the same way, or measured and shown not to scan the whole register
- [ ] #5 Fast suite passes, doc/db regenerated, change on master with hosted CI green
<!-- AC:END -->
