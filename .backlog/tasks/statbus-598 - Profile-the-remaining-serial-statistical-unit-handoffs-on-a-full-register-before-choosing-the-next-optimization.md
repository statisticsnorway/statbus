---
id: STATBUS-598
title: >-
  Profile the remaining serial statistical-unit handoffs on a full register
  before choosing the next optimization
status: To Do
assignee: []
created_date: '2026-11-08T23:38:00Z'
updated_date: '2026-11-08T23:41:00Z'
labels:
  - performance
  - worker
dependencies: []
references:
  - doc/performance/2026-11-concurrent-import-validation.md
  - tmp/591/concurrency-v2/full-register/benchmark.log
priority: medium
type: spike
ordinal: 514204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star

Make a full-register recalculation faster without changing its business rows, temporal relationships or reports. Choose the next change from reproducible statement-level measurements.

### Zoom out

Choose the next optimization from statement-level evidence, not from summed task totals. Find the next measured statistical-unit bottleneck after the shipped STATBUS-581 partial-legal-unit, bounded-propagation and power-group aggregation changes. Recommend a change only after a representative statement-level profile and a nondestructive prototype establish exact outputs and a same-environment benefit.

This is a separate follow-up, not an unfinished part of STATBUS-581 or an additional STATBUS-591 performance claim.

### Zoom in

The November 8 local full-register real-worker run, measured at d25fef3d805db50918a133d0ead1eb8bf57ed840 with runtime f95da97d7f61450dc12a097cb7221cdee9ab0f81, completed in 6,967.459 seconds with history checks A/B/C all zero divergences. Its 28 analytics cycles recorded:

| Command | Tasks | Summed task seconds | Longest task seconds |
|---|---:|---:|---:|
| statistical_unit_refresh_batch | 4,680 | 5,631.572 | 8.546 |
| statistical_unit_flush_staging | 28 | 1,948.634 | 607.449 |
| derive_statistical_unit | 28 | 678.883 | 509.319 |
| derive_used_tables | 28 | 422.361 | 227.565 |

Summed concurrent task time is not elapsed wall time. The long serial handoffs warrant a statement-level profile before choosing another concurrency mechanism. Raw evidence: tmp/591/concurrency-v2/full-register/benchmark.log, lines 1770-1790. The full source database import_benchmark_64469 and measurement artifacts are retained.

Separately, post-worker rollback-only derive_statistical_unit diagnostics took 500.678 seconds first and 511.349 seconds last. They are diagnostics, not additional import time. Integrated source a1ba6063de60059728cb32be90e28e994705b613 preserves the measured runtime.

Rabbit owns the separately authorized Norway serial rc.03 import and subsequent full recalculation. Use his final saved evidence when available. Do not repeat a full serial import or infer causal speedup from the local 8 GiB database limit versus Norway's 32 GiB.

The investigation must stay within the following scope.

Inspect the actual SQL definitions and representative retained inputs. Identify the dominant statements inside flush_staging and derive_statistical_unit, including data shape, query plans, resource settings and worker overlap. State positive output and temporal-coverage invariants before prototyping.

Use rollback-only or private-clone experiments. Retain source/function/input/settings fingerprints and exact row comparisons. Preserve parent links, date semantics, power-group membership, worker barriers and history A/B/C. A measured no-change conclusion is valid if the proposed optimization is not worthwhile.

No release, host deployment, database deletion, business-date policy or adoption of the SQL Saga prototype is authorized by this ticket.

### Closing review

Memory: none needed. Keep mandatory definitions and behavior in version-controlled schema comments and guides, not memory.

Documentation: retain the profile, exact comparison and owner decision with the ticket. If a change is adopted, regenerate its paired schema documentation and update the affected guide at its definition.

Cleanup: preserve import_benchmark_64469 and all raw baseline/prototype evidence while the decision is open. Any later database removal requires a separate named inventory and explicit approval. This ticket authorizes no deletion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A representative statement-level profile names the dominant operations in flush_staging and derive_statistical_unit, distinguishes serial wall from summed concurrent work, and records source, data and resource context.
- [ ] #2 [Owner] An adopt-or-reject decision for the measured prototype is recorded in Implementation Notes, with exact row, state and temporal parity plus same-environment baseline/prototype timing evidence.
- [ ] #3 [Owner] Implementation Notes record the chosen next step: adopt requires an implemented change with a positive original-failing regression, PostgreSQL and real-worker acceptance, paired schema documentation and reviewed commit/CI evidence; reject requires a linked measured rejection report and no runtime change.
<!-- AC:END -->
