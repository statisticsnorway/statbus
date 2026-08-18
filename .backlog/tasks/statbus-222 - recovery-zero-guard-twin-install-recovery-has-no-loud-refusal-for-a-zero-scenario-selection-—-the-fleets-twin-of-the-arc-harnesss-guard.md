---
id: STATBUS-222
title: >-
  recovery-zero-guard-twin: install-recovery has no loud refusal for a
  zero-scenario selection — the fleet's twin of the arc harness's guard
status: To Do
assignee: []
created_date: '2026-08-18 09:50'
labels:
  - ci
  - install-recovery
  - quality-gate
dependencies: []
references:
  - .github/workflows/install-recovery-harness.yaml
  - .github/workflows/upgrade-arc-harness.yaml
priority: low
type: enhancement
ordinal: 222000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: the install-recovery fleet discovers its scenario list and runs one VM job per scenario. Its sibling, the upgrade-arc harness, gained a guard in STATBUS-215: a run whose selection is empty (outside the one ratified green-skip case) fails red instead of concluding green with nothing executed.

WHAT GOES WRONG: install-recovery never got the twin. If its discover step ever produced count=0, run-scenario would silently skip and the run would conclude green — the "zero-selection succeeds" softness, on the OTHER fleet. Found 2026-08-18 by the mechanic while folding STATBUS-221 into the 214 pass; flagged, deliberately not fixed in that frozen unit.

THE DETAIL: install-recovery-harness.yaml has three jobs — discover, run-scenario (now with the explicit 221-hardened if), cleanup (always()). There is no job that fires red on count==0. Mitigations already in place soften but do not close it: the 216 empty-domain fixes make an empty scenario FOLDER fail loudly in the Go gate, and the release gate's completeness check would refuse such a run as proof. But the run itself still shows green in the Actions list, misleading anyone reading runs rather than gates.

THE FIX: a no-scenarios-guard job mirroring the arc harness's no-arcs-guard — fires red when discover succeeded with count==0, exempting any legitimate green-skip path this fleet has (none today; if a RIDE-style optimizer is ever added here, the exemption mirrors it, independently re-derived per the 215-review doctrine).

WHY THAT HELPS: both fleets then share one behavior — an empty run is a loud failure, never a quiet green — so nobody has to remember which fleet can be trusted by its color alone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A run whose discover succeeds with count==0 concludes red with a named error
- [ ] #2 Any legitimate zero-selection path is exempted explicitly and independently re-derived, never read from a discover output
- [ ] #3 The guard job cannot poison downstream ifs (the 215 audit applied at birth)
<!-- AC:END -->
