---
id: STATBUS-598
title: >-
  Profile the remaining serial statistical-unit handoffs on a full register
  before choosing the next optimization
status: Done
assignee:
  - hibiscus
created_date: '2026-11-08T23:38:00Z'
updated_date: '2026-11-09T12:19:00Z'
labels:
  - performance
  - worker
dependencies: []
references:
  - doc/performance/2026-11-concurrent-import-validation.md
  - tmp/591/concurrency-v2/full-register/benchmark.log
documentation:
  - >-
    statbus-591-concurrency-reviewed:doc/performance/2026-11-concurrent-import-validation.md
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
- [x] #1 A representative statement-level profile names the dominant operations in flush_staging and derive_statistical_unit, distinguishes serial wall from summed concurrent work, and records source, data and resource context.
- [x] #2 [Owner] An adopt-or-reject decision for the measured prototype is recorded in Implementation Notes, with exact row, state and temporal parity plus same-environment baseline/prototype timing evidence.
- [x] #3 [Owner] Implementation Notes record the chosen next step: adopt requires an implemented change with a positive original-failing regression, PostgreSQL and real-worker acceptance, paired schema documentation and reviewed commit/CI evidence; reject requires a linked measured rejection report and no runtime change.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-09 08:42UTC: owner explicitly delegated this future-improvement work to Hibiscus while Rabbit and owner focus on final personal review/release readiness of existing serialrc03fc183. Hibiscus received the execution brief: statement-level measurements and private-clone/rollback prototype on retained data, positive output/temporal invariants and measured adopt-or-reject proposal. No addition to existingRC, no Norway/dev/production operation, no deletion/release/promotion/Saga adoption or business-policy change. Rabbit coordinates tracker/master integration; exactdiff/test evidence required before landing. Current Norway comparison doc/performance/2026-11-norway-serial-rc03-comparison.md is context, not authorization to rerun its host.

2026-11-09 12:10UTC Hibiscus: profile done and three changes landed on master (Rabbit cherry-picked unchanged, patch-ids equal): 0c0f79420, c9f19a0a5, 1b59d5da6 (branch origin/statbus-598-su-rc03 = fc1830fe4 + a87a60067, e6123d826, ce3ad43dc).

Profile (retained full register import_benchmark_64469, plpgsql_check profiler + rolled-back probes; journal tmp/591/journal.md in Hibiscus checkout):
- derive_statistical_unit 509 s cycle: NOT multirange containment (1.2 s). Dominant: (a) worker.spawn loop copying the whole changed_*_id_ranges (4.2 MB text, 272,511 LU ranges) into each of 1,855 refresh batches = 7.5 GB payload in one cycle; (b) get_temporally_closed_change_sets appending each enterprise group to a temp table with 4 INSERTs.
- statistical_unit_flush_staging: DELETE/MERGE small on medium batches; ANALYZE of the 9 GB, 40-index statistical_unit is ~7 s fixed per cycle; the 607 s cycle is a MERGE of ~1.2M rows.
- derive_used_tables: activity/region/sector *_used_def aggregated all 3.1M statistical_unit rows (21.8/15.9/3.2 s); its 227 s in-run time was contention.

Changes (each: paired up/down migration, down = exact dumped rc03 definition, schema docs):
1. 20261109094235 refresh batch carries only its own changed ranges. Real 20k-range sample: derive 55.8 -> 31.0 s, payload 483 -> 24 MB, one batch 1.7-6.6 -> 0.85 s. Effective ES/LU/EN refresh sets identical: 1,791 batches, 0 differences. Test 392: RED on unmodified schema (0/2 batches own share, union f) -> GREEN (2/2, t).
2. 20261109095151 change sets assembled in arrays. Identical output filtered/paged/full (1,791/3/3,098 sets, 0 differences); filtered 27.9 -> 17.2 s, full 43 -> 42 s.
3. 20261109095648 used-code views skip-scan distinct paths. Rows identical (1,782/376/33); 12.1 -> 0.6, 5.4 -> 0.1, 1.3 -> 0.01 s. Test 393 asserts exact content (passes on old and new views).

Verification: local ./dev.sh test fast at exact ce3ad43dc 133/133 + 094 + 143 PASS, stamp ce3ad43dc/source 20261109095648; doc-db regenerated, types unchanged. Hosted Fast 42611161354 at master 6392981e5: 392 and 393 ok (its only failure was 008 for the separate recalculate_all, fixed by Rabbit in b9d6661e0).

Scope of benefit: medium/large incremental recalculation (imports) gains most from 1 and 2; 3 saves ~18 s on every recalculation including full and small ones. Full refresh derive and small edits are otherwise unchanged.
Owner 12:09: concurrency measurement moves to dev or tonight, not local; local timing today was contaminated by concurrent profiling/test load. Remaining before Done: real-worker acceptance rc03 vs rc03+598 on BRREG selection with exact statistical_unit/history parity, and a completed green hosted Fast at b9d6661e0 or later.

2026-11-09 12:19UTC Hibiscus: real-worker acceptance and hosted coverage complete. Released in v2026.11.3-rc.04 (tag on b9d6661e0, 12:18 UTC).

Real Crystal worker, BRREG selection, same machine, idle database, run one after the other: rc03 fc1830fe4 (import_benchmark_24502) vs rc03 + these three changes ce3ad43dc (import_benchmark_42729), both import concurrency 1. Both exit 0, 0 failed tasks, history checks A/B/C pass. Exact parity across 10 tables (unit ids mapped to tax_ident, audit clocks dropped): statistical_unit 33,876 rows, statistical_history 48, statistical_history_facet 215,544, statistical_unit_facet 17,748, and all six *_used tables. Worker 100.5 s vs 86.4 s on one small sample (an indication, not a measured speedup). Evidence in Hibiscus checkout tmp/598/accept/ (RESULT.md, parity.log, parity.py).

Hosted Fast Tests 42614109802 at exact b9d6661e0: checkout and stamp b9d6661e0 (source 20261109111905), 134/134 shared plus 094 and 143 passed, including 392_statbus_598_refresh_batch_own_changed_ranges and 393_statbus_598_used_code_views. All seven b9d6661e0 workflows completed/success.

Owner decision (AC2/AC3): adopt. Owner directed landing these improvements in the current release candidate (2026-11-09 10:16-11:13); Rabbit cherry-picked them unchanged (patch-ids equal) after the owner-approved concurrency revert ebd890fa6. Next step is a separate ticket for the flush step and per-cycle ANALYZE, measured on a quiet machine.
<!-- SECTION:NOTES:END -->
