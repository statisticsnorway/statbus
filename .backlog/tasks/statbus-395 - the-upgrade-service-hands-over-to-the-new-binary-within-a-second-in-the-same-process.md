---
id: STATBUS-395
title: >-
  The upgrade service hands over to the new binary within a second, in the same
  process
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 14:55'
labels:
  - upgrade
  - recovery
  - cli
dependencies:
  - STATBUS-382
references:
  - tmp/handoff-and-banner.md
priority: high
type: task
ordinal: 85
---

## Description

After the durable `PhaseNewSbSwapped` stamp, the upgrade service execs the new
binary in the same process: the PID stays the same, the new image reacquires
the marker flock, and the upgrade continues at once instead of waiting out the
30-second `RestartSec`. The design is in `tmp/handoff-and-banner.md`, task B.
This is tracked separately from the stale-daemon work in STATBUS-382.

## Done when

- A planned handoff continues within a second of the swap, with the same
  MainPID.
- flock, watchdog, error exit, and crash backoff behave as before.

## 2026-09-24 status

Awaiting owner go. Next step: obtain owner approval, implement the
PID-preserving exec-in-place handoff, and validate flock, watchdog, error, and
crash-backoff behavior.
