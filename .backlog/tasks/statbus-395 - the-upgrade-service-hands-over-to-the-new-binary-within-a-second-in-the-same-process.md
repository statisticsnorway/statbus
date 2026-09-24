---
id: STATBUS-395
title: A planned upgrade resumes immediately under the new binary
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

## Review correction 2026-09-24

The operator outcome is immediate resumption under the new binary; MainPID, exec, flock, watchdog, and `RestartSec` are implementation details. Permitted current evidence is `ops/statbus-upgrade.service:56` and the upgrade phase code; the excluded `tmp/handoff-and-banner.md` and its 30.17-second figure are not evidence. Add a named new real service-handoff test with a declared reliable timing bound and a separate crash-backoff control test with explicit bounded behavior.
