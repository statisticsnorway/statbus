---
id: STATBUS-157
title: >-
  fast-stamp-overreach: any targeted test writes the fast-suite stamp and
  bypasses the dirty-tree withhold — stamp only what ran
status: Done
assignee:
  - mechanic
created_date: '2026-07-11 20:47'
updated_date: '2026-07-12 03:31'
labels:
  - dev-tooling
  - testing
  - fail-fast
dependencies: []
references:
  - dev.sh
  - STATBUS-132
priority: medium
ordinal: 158000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the fast-test freshness stamp asserts exactly what happened — the FULL fast suite passed on a tree whose state the stamp names; nothing else can write it.
> STAGE: gate integrity (the King's quality-mechanism lane). FOUND: 2026-07-11 by the engineer during the 154 work — flagged, not fixed (correctly; gate machinery changes get ruled first).
> COMPLEXITY: mechanic-simple once the architect confirms the shape.

OBSERVED: a single targeted run (./dev.sh test 330_test_upgrade_invariant_trigger) on a DIRTY tree printed "Fast test stamp recorded" and wrote tmp/fast-test-passed-sha with HEAD 60acd3e + source 20260711201432 — a stamp claiming fast-suite freshness that (a) came from ONE test, not the suite, and (b) recorded a HEAD not containing the uncommitted work actually tested. The stamp-write block (dev.sh:969-983) fires for ANY successful ./dev.sh test <target>; the dirty-tree WITHHELD logic runs only when the selector is literally "fast".

BOUNDED RISK, honestly stated (the engineer's own note): post-commit HEAD changes, so a SHA-matching preflight forces a fresh run anyway — the gap is real but narrow. Still a gate that can be satisfied by something other than what it claims, which is the class the house removes on principle (strict gating, no hedges).

FIX SHAPE (architect confirms): the stamp write becomes conditional on the selector being the full fast suite (same condition as the withhold logic — one predicate, shared, so they cannot diverge again), and the dirty-tree withhold applies wherever the stamp can be written. A targeted test run gets its normal pass/fail output and writes no freshness stamp.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Only a full fast-suite run can write tmp/fast-test-passed-sha; targeted runs never do
- [x] #2 The dirty-tree withhold and the stamp write share one selector predicate (cannot diverge)
- [x] #3 A targeted run on a dirty tree leaves any existing stamp untouched
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SHIPPED 1f88536ce (2026-07-12), dev.sh only, +23/−8, architect SHIP as-built. The build found the bug WORSE than the ticket framed: the stamp-write gate checked ONLY the exit code — never the selector at all — so any successful targeted run stamped. The fix: one shared predicate (IS_FAST_SUITE_RUN, computed once where TEST_ARGS finalizes) feeds BOTH the dirty-tree withhold and the stamp write — single source of truth, structurally non-divergent (AC-2). Targeted runs can neither write nor touch a stamp (ACs 1/3), proven live on the REAL bug scenario (the mechanic's own uncommitted edit dirtying the tree): targeted run green, no stamp line, pre-existing stamp byte-identical with UNCHANGED mtime — the block was skipped, not re-entered. Fast-path preservation by code reading (the predicate's condition is the withhold's original verbatim, routed through the variable); failure mode of a predicate typo is a withheld stamp — loud at preflight, never a false stamp; the next organic fast run is the confirming oracle. CONSCIOUS BEHAVIOR CHANGE recorded (architect note): "test all" no longer writes the fast stamp — it only ever did via the exit-code bug, and the stamp's claim is exactly "the fast suite passed on a clean tree"; all-run stamping, if ever wanted, is a deliberate one-line follow-up, not gate looseness. This closes the last known gate-integrity hole on the board.
<!-- SECTION:FINAL_SUMMARY:END -->
