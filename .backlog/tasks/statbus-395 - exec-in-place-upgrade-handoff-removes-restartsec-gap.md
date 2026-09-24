---
id: STATBUS-395
title: >-
  exec-in-place upgrade handoff removes the RestartSec gap
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 16:44'
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

The upgrade-service handoff should remove the approximately 30-second
`RestartSec` gap after the durable `PhaseNewSbSwapped` stamp. The design is in
`tmp/handoff-and-banner.md`, task B. This is tracked separately from the stale
-daemon work in STATBUS-382.

## 2026-09-24 status

Awaiting owner go. Next step: obtain owner approval, implement the
PID-preserving exec-in-place handoff, and validate flock, watchdog, error, and
crash-backoff behavior.
