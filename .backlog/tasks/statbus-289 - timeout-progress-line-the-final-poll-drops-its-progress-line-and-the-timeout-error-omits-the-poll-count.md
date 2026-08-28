---
id: STATBUS-289
title: >-
  timeout-progress-line: the final poll drops its progress line and the timeout
  error omits the poll count
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-27 18:42'
updated_date: '2026-08-28 09:04'
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
NORTH STAR: an operator watching a ready-wait time out must see evidence of the attempts — how many, and what the last one saw — without reading source code to know whether the poller ran.

CORRECTED SCOPE (verified against exec.go at master, 2026-08-28 — the original filing overstated the symptom): a timeout is NOT "indistinguishable from a hang". Two things already guarantee evidence: the intro line ("Waiting for PostgREST schema cache to load (admin /ready, up to Xs)...", exec.go:1594) always prints before the loop, and BOTH timeout errors (:1616-1620 cache-never-loaded, :1622-1626 admin-unreachable) end with "last: <detail>" — and lastDetail is always populated, because each pass polls (:1598) before it checks the deadline (:1614). The timeout error always proves at least one poll happened and shows its result.

THE TWO REAL GAPS, both small:
1. The deadline check (:1614) runs before the progress branch (:1627), so the FINAL pass never emits its "Still waiting" line. In production (minutes-scale timeout, regular progress lines on earlier passes) this loses only the last line. But a run whose first deadline evaluation already exceeds the budget — timeout shorter than one poll round trip — prints the intro and then the error with ZERO "Still waiting" lines in between. No production victim at current intervals; the hazard was exposed by the test's 40ms budget.
2. The poll COUNT appears in the success line (":1602, '%d poll(s)'") but not in either timeout error. "last: connection error" with no count reads the same after 1 attempt as after 40.

SMALLEST FORM (architect's original, extended by the count): move the progress emission before the deadline check so every path to a timeout has emitted at least one "Still waiting" line beyond the intro; add the polls count to both timeout error messages. Keep the clock seam (waitForRestReadyNow/Sleep, :1560-1563) untouched; extend the owned-clock test to pin both properties — "timeout output contains at least one progress line" and "timeout error names the poll count".

WHAT IS ACHIEVED: every timeout tells the operator how hard the poller tried and what it last saw — in the error itself, not by archaeology.
<!-- SECTION:DESCRIPTION:END -->
