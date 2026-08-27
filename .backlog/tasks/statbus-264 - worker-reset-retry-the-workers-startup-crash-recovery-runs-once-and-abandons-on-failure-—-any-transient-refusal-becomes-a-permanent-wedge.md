---
id: STATBUS-264
title: >-
  worker-reset-retry: the worker's startup crash recovery runs once and abandons
  on failure — any transient refusal becomes a permanent wedge
status: To Do
assignee: []
created_date: '2026-08-27 12:48'
labels:
  - worker
dependencies: []
priority: high
type: bug
ordinal: 257000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-262 (Norway wedge): worker.reset_abandoned_processing_tasks() runs exactly once per worker startup; when it failed (refused inside the upgrade's read-only window), it logged ERROR and never ran again, leaving four 'processing' rows wedged for a week behind a healthy-looking worker.

Architect's PRIMARY structural fix: the reset must RETRY until it succeeds, not log-and-abandon — a once-per-startup recovery that can fail permanently converts ANY transient condition (this window, a slow database, a blip) into a permanent wedge. Additionally ruled: a failed startup crash-recovery must never be merely logged — either it retries until success, or the worker refuses to report healthy.

Evidence and full root cause: STATBUS-262 comments #3-#5 (worker started +0.3s before its recovery call, window lifted +2.4s after start, RestartCount=0 since).

WHAT IS ACHIEVED: no transient startup condition can permanently disable the worker's crash recovery, and a recovery that cannot run is loud instead of silent.
<!-- SECTION:DESCRIPTION:END -->
