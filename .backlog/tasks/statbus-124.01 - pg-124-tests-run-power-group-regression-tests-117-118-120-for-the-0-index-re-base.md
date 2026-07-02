---
id: STATBUS-124.01
title: >-
  pg-124-tests: run power-group regression tests 117/118/120 for the 0-index
  re-base
status: In Progress
assignee:
  - tester
created_date: '2026-07-02 19:02'
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
