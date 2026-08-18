---
id: STATBUS-229
title: >-
  unpark-arc-red: the un-park test scenario has been failing since before rc.02
  — nobody noticed because no full suite concluded honestly until now
status: To Do
assignee: []
created_date: '2026-08-18 10:37'
labels:
  - upgrade-recovery
  - install-recovery
  - release
dependencies: []
references:
  - test/install-recovery/arcs/un-park-to-completion-arc.sh
  - cli/internal/upgrade/service.go
  - tmp/operator-arc-fails34-triage-2026-08-18.md
priority: high
type: bug
ordinal: 229000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A parked upgrade is one the operator deliberately releases for a fresh attempt — the un-park path. The test scenario proving that path end-to-end is red, and has been since at least the previous full suite: it is not part of the rc.03 regression, it is an older break that only became visible now that suites conclude honestly instead of green-skipping.

WHAT THE EVIDENCE SHOWS: at rc.03 (job 95644095097) the scenario's un-parked attempt died at the install precondition check before booting the new binary — "INSTALL_PRECONDITION_FAILED: the upgrade was interrupted before it changed anything and was rolled back" — and the box rolled back CLEANLY to normal operation (state rolled_back, system running the old version). Same failure at the previous full suite (run 30755799405). Distinct from STATBUS-228's signature (no crash-deaths, no failed state, clean rollback) — though 228's Defect-1 fingerprint ("could not record backup_path ... unexpected EOF") also appears in this log, so the 228 fix may change this scenario's behavior and any diagnosis must re-run after it lands.

OPEN QUESTIONS FOR THE TRACE: is the precondition refusal the product being RIGHT (the un-parked state legitimately fails a precondition the scenario doesn't satisfy — assertion problem) or WRONG (un-park grants an attempt the preconditions then wrongly refuse — product problem)? And is this scenario the observation arm some recent un-park work was waiting on — in which case its permanent redness has been silently blocking that closure?

WHAT IS ACHIEVED: every scenario in the suite is either green or has a named owner and cause — a fully-green suite becomes reachable again, which is what any promotion after the 228 fix will require.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Trace AFTER the 228 fix lands: reproduce at the fixed code, then root-cause with file:line — product refusal wrong vs scenario assertion stale
- [ ] #2 Fix or ruled scenario correction landed via the standard review gates
- [ ] #3 Scenario green at a full suite
<!-- AC:END -->
