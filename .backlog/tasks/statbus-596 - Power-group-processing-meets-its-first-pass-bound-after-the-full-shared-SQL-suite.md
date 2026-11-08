---
id: STATBUS-596
title: >-
  Power-group processing meets its first-pass bound after the full shared SQL
  suite
status: Done
assignee: []
created_date: '2026-11-08T17:56:00Z'
updated_date: '2026-11-08T19:14:00Z'
labels:
  - database
  - performance
  - testing
dependencies: []
references:
  - STATBUS-591
  - STATBUS-454
priority: high
type: bug
ordinal: 512204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Hosted Fast runs 42500931828, 42506168812 and 42509814106 failed SQL374 only at its first-pass ten-second bound, preserving all 6,000 roots, change collection and 12,000 reused relationship/group/level results. The original logs and genuine artifacts remain retained.

Cause: the direct bulk fixture loaded 18,000 legal units while their planner statistics still described an empty table. PostgreSQL 18 PERIOD foreign-key checks chose a range-only index, filtering the other 17,999 units per lookup. A matched uninstrumented clone reproduced a 121.524-second first call. An otherwise unchanged clone with ANALYZE public.legal_unit after fixture insertion passed in 4.399 seconds. Rebuilding relationship indexes alone did not help. Actual matching FK-query plans show the refreshed composite ID/range primary-key lookup.

Repair 612a911871fd40b562b20a016a78ca9d3ceccc62 refreshes only fixture referenced-unit statistics. Runtime SQL, real constraints/triggers, all-NULL relationship statistics, serial concurrency one and the ten-second assertion are unchanged. The repaired fixture still detects the original processing defect. Full local fast and all seven exact-source CI workflows pass, including hosted SQL and live-database tests. Stable remains held, Norway unchanged, and no full-register speed claim is made.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A retained real-database reproduction or hosted plan/timing identifies the slow first-pass operation and distinguishes full-suite or seed-state effects from unrelated runner variation.
- [x] #2 A minimal serial repair preserves the exact6000group/12000relationship/derived-change results and meets the existing first-pass bound, with regression failure before and success after the repair.
- [x] #3 The relevant SQL regressions and full fast suite pass, exact-SHA CI status/conclusion and any required named-candidate guest acceptance are recorded without discarding the original failures.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-08 17:57 UTC: actual genuine hosted output downloaded under tmp/serial-rc/diagnostic-fast-hosted-artifact/. SQL failure remains true, diagnostic upload succeeded with409files after both summaries were absent. Next controlled probe: actual131shared cases in isolated exact published-image cluster, writable archived source workspace and retained nested statement plans, preserving original probe and all logs. No performance threshold change.

2026-11-08 17:59 UTC: the prior note timestamp17:57 was written at17:56, a note-time typo, not an additional run. Controlled actual131shared sequence670035pd88 started17:57, network-none exact published-image cluster, database serial_full596 cloned from inspected e6 baseline, writable git-archived source and auto_explain nested-statement plans with timing instrumentation off. Initial40cases pass. Original procedure dumped before experiments to tmp/serial-rc/596-process-power-group-link-original.sql, SHA25685459459a3697b918068b3eb713b87fbf9bff4b4911ea9916f2bc12f4b63c7e1. Actual downloaded artifact ZIP hash verified and embedded results.tar equals every extracted result byte. No tracked SQL changes.

2026-11-08 18:09 UTC: controlled actual131shared sequence670035pd88 completed exit0 in432.3s on local ARM using exact published e6 DB image and seed. SQL374 total38239ms, timed first CALL4709.102ms. The two relationship UPDATEs cost1708.401ms and1693.590ms. A separate24,378.899ms range_agg assertion rescans6004logrows6000times, outside the timed first pass, so it does not explain the hosted boolean failure. First-pass pending singleton27pages, no observed lock wait. Preserved full596-shared.log, full596-postgres-plans.log, results and596-storage-observed.log under tmp/serial-rc. Full-suite state alone on ARM is insufficient to reproduce. Next purposeful CI change captures actual hosted nested plans and configuration, with timing instrumentation off and no product SQL or threshold changes.

2026-11-08 18:20 UTC: reviewed diagnostic-only26e99184e. Root independently passed20collector/5profiling positive cases, Actionlint and ShellCheck. Exact tracked initialization body executed on the owned network-none published PostgreSQL18 cluster: all8fresh-session settings match and actual analyzed1.05secondquery plan emitted. Exact final log-capture body then consumed actual PostgreSQL logs using the real sb dotenv parser, preserved plan/row bytes and redacted the known fixture secret, status0. First root harness incorrectly expected Docker stdout only; Docker actual stderr carried the plans and product retained them correctly. Corrected harness checks both streams and passed, initial failure retained. Evidence tmp/serial-rc/596-root-{final-review,initialization-final,log-capture-corrected}.log and corresponding retained directories. Separate plan capture/upload now runs after either SQL success or failure, strict SQL outcome and thresholds unchanged. Instrumented timings are diagnostics, not performance acceptance. Next normal push/CI seeks actual hosted slow plan.

2026-11-08 18:37 UTC: actual exact036fc2ab2 six workflows completed/success, Fast42509814106 failed onlySQL374194036ms. All profiler/capture/upload steps succeeded. Genuine artifact13629316142 downloaded and ZIP digestbafdb43194d84721491cc6cc2fa9cd6033517ed3238c466bf58eb5edda9be5aa verified. Timed first CALL166055.676ms is dominated by group UPDATE81785.666ms and level UPDATE82317.329ms. Both actual12000-rowjoin plans match fast local sort/hash shape and cardinalities, so repeated join scans are not the observed cause. Separate range assertion14241.325ms remains outside the first call. Next non-destructive local clone captures trigger/buffer/WAL details to distinguish update-side temporal constraints/GiST maintenance/statement triggers. No SQL fix, threshold change or performance acceptance claimed.

2026-11-08 18:47 UTC: actual local physical clones now reproduce hosted behavior. Instrumented serial_trigger596 first CALL116335ms, group/level UPDATE57896/57108ms. Matched serial_control596 disables session preload and auto_explain, still fails unchanged374 with CALL121524ms and relationship fixture INSERT62349ms. Exact6000/12000 business outputs retained. Logically empty source heap0bytes retains approximately50MB temporal/GiST indexes. A new owned network-none clone serial_reindex596 is testing index-state causality with REINDEX only on that disposable clone, unchanged374 and profiling disabled. Original databases/logs preserved. No runtime repair or threshold change inferred.

2026-11-08 18:52 UTC: index-only prototype remains RED: relationship REINDEX shrinks all20indexes to8KB but unchanged374 CALL120677ms. Statistics-only prototype on an untouched physical clone passes all exact assertions, CALL4399.279ms and fixture INSERT5884.481ms. The only added operation is ANALYZE public.legal_unit after18000fixture units, before relationships. Actual matching PostgreSQL18 PERIOD-FK query witness before/after: empty-table relpages1/reltuples0 uses valid_range-only GiST, filters17999rows,2065buffers,2.836ms perlookup. ANALYZE records18000rows and selects composite legal_unit_pkey(id,valid_range),4buffers,0.041ms. This distinguishes stale referenced-table statistics from relationship-index bloat and unrelated runner variation. Evidence596-{control,reindex,analyze}-* and596-fk-plan-witness.{sql,log}. Repair scope is fixture statistics, not runtime algorithm or ten-second threshold. Next prove repairedfixture still catches original591 merge defect, then full fast and exact CI.

2026-11-08 18:55 UTC: permanent repair adds only referenced-unit fixture ANALYZE and explanatory comments/expected command. Actual normal ./dev.sh test 374_statbus_591_power_group_processing_scales_with_relationships passes13736ms total, all6000/12000/collection/reuse assertions and10secondbound retained. Initial abbreviated ./dev.sh test 374 was rejected before execution, its log preserved separately. Repaired fixture tested against original processing body via down712 in a separate owned clone fails only the unchanged bound, firstCALL20758.712ms; thus fixture repair still detects the original merge-cardinality defect. No runtimeSQL/schema/type/image change, so no new migration/replay/guest release claim. Fullfast and exact-source CI remain required.

2026-11-08 19:14 UTC final acceptance: repair SHA612a911871fd40b562b20a016a78ca9d3ceccc62 full normal local fast passed all131shared+2isolated, exit0 in444.8s, including314/321/344/372/374/377/378. Five test-generated plan/timing files were retained in596-local-generated-plans.diff and only those generated changes restored. Exact-source Go42512364113, app42512364089, Images42512364115, Push42512364123, Harness42512364179, Notify42512364006 and Fast42512709160 explicitly completed/success. Fast SQL131+2, floor checks, live-database tests, profiler initialization, plan collection and artifact upload all passed. Successful genuine artifact13630661616 ZIP SHA2563edd9a272e4ffca8acc6ed5ded511bfb1cc5772b19590dd7ba2559ee52fd0796 verified. Its actual hosted firstCALL4613.711ms and group/level UPDATE1629.223/1617.570ms, collectionstatus0, show the successful slow-query-plan path also works. All original failed runs/diffs and causal prototypes remain retained. First root observer hit its600s tool deadline while CI remained running; its read-only continuation observed actual success, no CI rerun. Evidence tmp/serial-rc/test-596-fast-612a91187.log,596-repair-fast-{final.json,full.log},596-repair-hosted-artifact/,596-repair-source-ci{,-continuation}.log. No deployed image change after rc03 and no new product migration or RC guest claim. Fresh per-SHA CI images were built normally. Ready to close.
<!-- SECTION:NOTES:END -->
