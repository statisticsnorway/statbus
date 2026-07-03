---
id: STATBUS-124.01
title: >-
  pg-124-tests: run power-group regression tests 117/118/120 for the 0-index
  re-base
status: Done
assignee:
  - tester
created_date: '2026-07-02 19:02'
updated_date: '2026-07-03 19:30'
labels:
  - power-group
  - testing
dependencies: []
parent_task_id: STATBUS-124
ordinal: 126000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Authorizes the tester (restrict-agent-spawn.sh Rule 4) to run the power-group pg_regress tests for the STATBUS-124 0-index re-base. Tester runs `./dev.sh test 117_power_group_fundamentals`, `118_power_group_worker_derivation`, `120_power_group_lifecycle` and reports PASS/FAIL + diffs to the architect. Diffs are EXPECTED (architect blesses the 0-based expected .out after reviewing actual output). Do not modify expected .out.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Tests 117_power_group_fundamentals, 118_power_group_worker_derivation, 120_power_group_lifecycle all PASS on the current tree (fast suite run 2026-07-03, tmp/test-fast-doc025.log: 117 = 556ms ok, 118 = 999ms ok, 120 = 3777ms ok; suite 84/85 with the sole failure an unrelated 092 doc-drift since fixed in 447999ff9). The 0-based expected .out files were blessed and committed with the STATBUS-124/125 packages (8a45e2945 lineage); today's green suite on top of those commits is the confirming run. 119_roller_data_power_groups also passed (1455ms) as a bonus check.
<!-- SECTION:FINAL_SUMMARY:END -->
