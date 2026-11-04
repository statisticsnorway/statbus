---
id: STATBUS-566
title: >-
  Full recalculation of a Norway-sized database is OOM-killed at DB_MEM_LIMIT 8G
  in the power-group refresh batches
status: To Do
assignee: []
created_date: '2026-11-04T00:43:00Z'
updated_date: '2026-11-04T00:43:00Z'
labels:
  - performance
  - worker
dependencies: []
priority: medium
type: bug
ordinal: 489204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On full Norway (3,139,134 units) restored locally with DB_MEM_LIMIT=8G (the documented cap for a private cloud slot, doc/CLOUD.md), worker.enqueue_derive_statistical_unit_all() completes 3,137 of 3,165 statistical_unit_refresh_batch tasks, then the power-group batches (401 power groups each) get PostgreSQL OOM-killed 15 times. The analytics queue runs 4 at a time (worker.queue_registry default_concurrency 4). rune (32G, 8GB shared_buffers, 1GB work_mem) finishes the same batches in 59-70 s.

Measured one batch alone (task 847206 payload, inside BEGIN/ROLLBACK, tmp/558-shd/p14-*):
- baseline container memory 2.5 GiB; one batch peaks at 4.0 GiB (+1.5 GiB), 71 s
- work_mem 64MB instead of 256MB: peak 3.1 GiB (+0.6 GiB), 65 s
- temp_buffers 256MB instead of 1GB: peak 4.0 GiB, no change
So the per-batch growth is work_mem-driven (several sort/hash nodes per query). Four concurrent batches at +1.5 GiB on top of shared_buffers 2 GiB exceed 8 GiB.

computeDbMemory (cli/internal/config/config.go) sets work_mem = DB_MEM_LIMIT/32 without regard to the analytics concurrency.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A full recalculation of a Norway-sized database completes at DB_MEM_LIMIT=8G with no OOM kill
- [ ] #2 The memory derivation (or the batch work) states how work_mem relates to analytics queue concurrency, in its own comment
- [ ] #3 On full Norway at DB_MEM_LIMIT=8G the unit refresh batches finish within the wall time of the same run without OOM (compare 4,273 s)
<!-- AC:END -->
