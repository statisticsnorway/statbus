---
id: STATBUS-289
title: >-
  timeout-progress-line: a ready-wait timeout can print zero progress lines —
  indistinguishable from a hang
status: To Do
assignee: []
created_date: '2026-08-27 18:42'
labels:
  - cli
  - upgrade
dependencies: []
priority: low
type: enhancement
ordinal: 282000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 288/go-test landing review (architect, 2026-08-27): in waitForRestReady (cli/internal/upgrade/exec.go), the deadline check precedes the progress emission, so a run whose polls are slow enough can reach the timeout having printed nothing — and a timeout that prints nothing is indistinguishable from a hang; the operator's first question is "did it even try?" At production intervals (minutes) there is no live victim — the hazard was exposed by the test's 40ms budget — so this is a follow-up, not a fix-now.

Architect's smallest form: emit the first probe's result BEFORE the deadline check, so at least one progress line is guaranteed on every path to a timeout. Keep the clock seam's testability; extend the owned-clock test to pin "timeout output always contains at least one progress line".

WHAT IS ACHIEVED: an operator watching an upgrade never sees a silent timeout — every timeout shows the poller tried, when, and what it last saw.
<!-- SECTION:DESCRIPTION:END -->
