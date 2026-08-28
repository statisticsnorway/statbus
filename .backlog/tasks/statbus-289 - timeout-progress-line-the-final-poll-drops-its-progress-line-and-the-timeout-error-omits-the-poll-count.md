---
id: STATBUS-289
title: >-
  timeout-progress-line: the final poll drops its progress line and the timeout
  error omits the poll count
status: Done
assignee:
  - '@mechanic'
created_date: '2026-08-27 18:42'
updated_date: '2026-08-28 09:11'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-28 09:11
---
LANDED at 51a7bbeef and CLOSED (exec.go + ready_warmup_test.go, +90/−10). Both changes as designed: progress emission reordered before the deadline check (throttle semantics preserved — verified by exact count, not assumed) and ', %d poll(s)' added to both timeout errors, everything else byte-identical. THE CRAFT POINT worth keeping: the mechanic rejected the ticket's own suggested pin ('timeout output contains at least one progress line') because it ALREADY PASSED with the bug — earlier passes log plenty — and would have pinned nothing; he built an EXACT assertion instead (polls-1 lines, derived from the error's own poll count so it cannot drift if intervals change) and proved it in a three-step red: unfixed code fails on the missing count; count-added-but-unreordered isolates property 1 precisely (22 polls, 20 lines — the final pass's line demonstrably dropped); full fix passes 22-polls-21-lines with all success-path tests unchanged. Verbatim new error texts on the freeze report. Validated: build, vet, uncached package suite, and the new gofmt gate. Line citations from the morning's rewrite matched master exactly — no drift despite 294 landing in the same file hours earlier.
---
<!-- COMMENTS:END -->
