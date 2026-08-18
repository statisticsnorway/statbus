---
id: STATBUS-216
title: >-
  arc-domain-empty: an empty arcs/ folder passes the release gate and breaks the
  test matrix — both sides must fail loudly
status: To Do
assignee: []
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 07:41'
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
> NORTH STAR: the list of arc scenarios on disk is the release gate's ground truth. If that list ever comes back empty, something is broken — both sides must stop and say so, loudly.

FOUND: 2026-08-17 by the architect during the STATBUS-215 review. Not reachable today — the folder holds 31 arcs. But it is one rename or path typo away, and one of the two failure modes is exactly the "looks green, proved nothing" class the 199 gate exists to refuse.

THE SERIOUS SIDE — the release gate can pass on nothing. Before promoting a release, the gate builds its list of required arc scenarios by listing test/install-recovery/arcs/ at the release commit (upgradeArcNamesAtCommit, cli/cmd/release.go:1349). If that listing prints nothing — folder renamed, pathspec typo — the function returns an empty list AND no error. The completeness check (cli/internal/release/workflow_check.go:222-225) then asks "is every required arc present in the run?" of an empty list, and the answer is automatically yes. The gate prints "✓ upgrade-arc-harness FULL SUITE green (0/0 arc jobs present)" and passes. Plainly: break the path and ANY green run passes the gate while proving nothing — and the success line reads like a real pass.

THE COSMETIC SIDE — the workflow invents a fake scenario. The discover job enumerates arcs with a shell glob (`for f in test/install-recovery/arcs/*-arc.sh` in .github/workflows/upgrade-arc-harness.yaml). When a glob matches nothing, the shell hands the loop the literal `*`, so the matrix becomes one bogus scenario named `*`, which then fails on a missing script. Noisy enough to notice, but not the clean, named failure the rest of that job gives (an unknown selector already exits with a list of the valid arcs).

One rule covers both sides: an empty arc list is never a legitimate state. Neither side may treat it as one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `upgradeArcNamesAtCommit` returns an error when the arc domain at the commit is empty, so checkUpgradeArcHarnessGate refuses instead of printing a 0/0 pass
- [ ] #2 A Go test pins the refusal: an empty required-arc list must never yield a gate pass (assert on the gate's boolean, not just on the helper)
- [ ] #3 discover fails loud on an empty/unmatched arcs glob (nullglob or an explicit count check) instead of emitting the literal `*` as a scenario
- [ ] #4 The two sides derive the arc domain from paths that cannot silently diverge, or a test pins them to each other (the STATBUS-199 comment #6 duplication-guard pattern)
<!-- AC:END -->
