---
id: STATBUS-596
title: >-
  Power-group processing meets its first-pass bound after the full shared SQL
  suite
status: In Progress
assignee: []
created_date: '2026-11-08T17:56:00Z'
updated_date: '2026-11-08T18:09:00Z'
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
Hosted Fast runs 42500931828 at e6eb065f5 and 42506168812 at 745c14282 fail SQL374 after 298,688 ms and 288,390 ms. The retained diff on the second run is only under_10_seconds=false. All 6,000 roots link correctly, all 6,000 groups are recorded for collection, and all 12,000 relationships reuse their groups and levels.

Candidate fc1830fe4 passed full local and hosted SQL. Later SQL, migrations and expected outputs are byte-identical. The exact e6 published image and seed locally pass SQL374 alone and SQL372 immediately followed by SQL374. Full-suite physical/statistical state, seed lineage, architecture and planner behavior remain hypotheses, not established causes.

STATBUS-454 repaired the diagnostic lifecycle. Genuine artifact 13628031707 retains all results and the exact diff. Its downloaded ZIP SHA256 is d9756fed08734907b3617be393410b4ef1650b5c53a1d8f02d65ce6006c134e1. Preserve the ten-second assertion and serial queue default one. Stable remains held. No Norway or full-register benchmark operations are authorized.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A retained real-database reproduction or hosted plan/timing identifies the slow first-pass operation and distinguishes full-suite or seed-state effects from unrelated runner variation.
- [ ] #2 A minimal serial repair preserves the exact6000group/12000relationship/derived-change results and meets the existing first-pass bound, with regression failure before and success after the repair.
- [ ] #3 The relevant SQL regressions and full fast suite pass, exact-SHA CI status/conclusion and any required named-candidate guest acceptance are recorded without discarding the original failures.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-08 17:57 UTC: actual genuine hosted output downloaded under tmp/serial-rc/diagnostic-fast-hosted-artifact/. SQL failure remains true, diagnostic upload succeeded with409files after both summaries were absent. Next controlled probe: actual131shared cases in isolated exact published-image cluster, writable archived source workspace and retained nested statement plans, preserving original probe and all logs. No performance threshold change.

2026-11-08 17:59 UTC: the prior note timestamp17:57 was written at17:56, a note-time typo, not an additional run. Controlled actual131shared sequence670035pd88 started17:57, network-none exact published-image cluster, database serial_full596 cloned from inspected e6 baseline, writable git-archived source and auto_explain nested-statement plans with timing instrumentation off. Initial40cases pass. Original procedure dumped before experiments to tmp/serial-rc/596-process-power-group-link-original.sql, SHA25685459459a3697b918068b3eb713b87fbf9bff4b4911ea9916f2bc12f4b63c7e1. Actual downloaded artifact ZIP hash verified and embedded results.tar equals every extracted result byte. No tracked SQL changes.

2026-11-08 18:09 UTC: controlled actual131shared sequence670035pd88 completed exit0 in432.3s on local ARM using exact published e6 DB image and seed. SQL374 total38239ms, timed first CALL4709.102ms. The two relationship UPDATEs cost1708.401ms and1693.590ms. A separate24,378.899ms range_agg assertion rescans6004logrows6000times, outside the timed first pass, so it does not explain the hosted boolean failure. First-pass pending singleton27pages, no observed lock wait. Preserved full596-shared.log, full596-postgres-plans.log, results and596-storage-observed.log under tmp/serial-rc. Full-suite state alone on ARM is insufficient to reproduce. Next purposeful CI change captures actual hosted nested plans and configuration, with timing instrumentation off and no product SQL or threshold changes.
<!-- SECTION:NOTES:END -->
