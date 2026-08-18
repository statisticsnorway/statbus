---
id: STATBUS-216
title: >-
  arc-domain-empty: an empty arcs/ folder passes the release gate and breaks the
  test matrix — both sides must fail loudly
status: To Do
assignee: []
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 07:43'
labels:
  - ci
  - release
  - quality-gate
  - install-recovery
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
  - cli/cmd/release.go
  - cli/internal/release/workflow_check.go
priority: medium
type: bug
ordinal: 216000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: before a release is promoted to stable, a gate checks that the full upgrade test suite really ran. It reads the list of test scenarios ("arcs") from the folder test/install-recovery/arcs/ at the release commit, then demands that a green CI run contains one job per scenario. The CI workflow reads the same folder to build its test matrix. One folder, two consumers, and the promise "promotion means every scenario ran."

WHAT GOES WRONG: if that folder ever comes back empty — renamed, or a path typo in either reader — neither side notices. The gate passes having checked nothing, and the workflow invents a fake test. Not reachable today (the folder holds 31 arcs, found 2026-08-17 by the architect during the STATBUS-215 review), but one rename away.

THE DETAIL, gate side (the serious one): upgradeArcNamesAtCommit (cli/cmd/release.go:1349) returns an empty list AND no error when the folder listing prints nothing. The completeness check (cli/internal/release/workflow_check.go:222-225) then asks "is every required arc present in the run?" of an empty list — automatically yes. The gate prints "✓ upgrade-arc-harness FULL SUITE green (0/0 arc jobs present)" and passes. Any green run now satisfies the gate while proving nothing, and the success line reads like a real pass.

THE DETAIL, workflow side (cosmetic by comparison): the discover job enumerates arcs with a shell glob (`for f in test/install-recovery/arcs/*-arc.sh`). A glob that matches nothing hands the loop the literal `*`, so the matrix becomes one bogus scenario named `*`, which fails on a missing script — noisy, but not the clean, named failure the rest of that job gives.

THE FIX: an empty scenario list becomes an error on both sides. The gate refuses instead of printing a 0/0 pass (with a test pinning that refusal), the workflow fails loudly on an unmatched glob, and the two readers' paths are pinned to each other so they cannot silently diverge.

WHY THAT HELPS: the gate can then never be silently disarmed by a file move. An empty scenario list stops a promotion instead of waving it through — the promise "promotion means proven" stays true even through future reorganisations.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `upgradeArcNamesAtCommit` returns an error when the arc domain at the commit is empty, so checkUpgradeArcHarnessGate refuses instead of printing a 0/0 pass
- [ ] #2 A Go test pins the refusal: an empty required-arc list must never yield a gate pass (assert on the gate's boolean, not just on the helper)
- [ ] #3 discover fails loud on an empty/unmatched arcs glob (nullglob or an explicit count check) instead of emitting the literal `*` as a scenario
- [ ] #4 The two sides derive the arc domain from paths that cannot silently diverge, or a test pins them to each other (the STATBUS-199 comment #6 duplication-guard pattern)
<!-- AC:END -->
