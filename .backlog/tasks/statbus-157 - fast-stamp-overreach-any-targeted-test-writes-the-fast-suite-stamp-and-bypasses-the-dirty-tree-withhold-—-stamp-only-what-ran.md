---
id: STATBUS-157
title: >-
  fast-stamp-overreach: any targeted test writes the fast-suite stamp and
  bypasses the dirty-tree withhold — stamp only what ran
status: To Do
assignee: []
created_date: '2026-07-11 20:47'
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
- [ ] #1 Only a full fast-suite run can write tmp/fast-test-passed-sha; targeted runs never do
- [ ] #2 The dirty-tree withhold and the stamp write share one selector predicate (cannot diverge)
- [ ] #3 A targeted run on a dirty tree leaves any existing stamp untouched
<!-- AC:END -->
