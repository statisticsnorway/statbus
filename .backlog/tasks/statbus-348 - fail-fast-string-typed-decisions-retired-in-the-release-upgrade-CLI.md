---
id: STATBUS-348
title: >-
  fail-fast: string-typed decisions retired in the release/upgrade CLI
status: Done
assignee: []
created_date: '2026-09-03 23:27'
updated_date: '2026-09-03 23:27'
labels:
  - release
  - upgrade
  - cli
  - correctness
dependencies: []
priority: medium
type: enhancement
ordinal: 341000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The release and upgrade CLI still had decisions encoded indirectly in loose strings: a scenario name needed a separately reconstructed workflow identity, while the binary-staleness refusal reused a subcommand verdict exit code. Both shapes allowed invalid or ambiguous states to be expressed and interpreted downstream.

King's creed and rationale: **“sound column constraints, make the invalid impossible to express, actionable fail-fast, no loose string matching.”** Carry decision-bearing identity in typed values, and reserve a distinct process exit code when the binary itself is unusable so callers cannot mistake infrastructure failure for a domain verdict.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A release scenario carries its own home workflow as a typed value; coverage and evidence consumers do not reconstruct that decision from its name
- [x] #2 The covered command asks the scenario's own workflow, including the fleet/home workflow path
- [x] #3 The staleness guard has a dedicated fail-fast exit code that cannot collide with covered's 0/1/2 verdict contract
- [x] #4 The release fleet orchestrator treats a stale binary as a loud failure, not an undecidable scenario verdict
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 6ba703087 fixes the covered home-workflow defect. Evidence: the focused reproducer was red when every scenario was sent to the arc harness and green after routing through the scenario-specific seam; the rebuilt public verb found fleet evidence 15/15 at rc.12.
- 7eb566b9e introduces `release.Scenario{Name, Home}` as the decision-bearing value used by parsing, listing, coverage, evidence, gates, and `covered`, deleting the duplicate cmd-side workflow reconstruction. Evidence: the full Go suite, vet, and lint passed with the typed API as the sole construction path.
- 050a37655 reserves exit 69 for an unusable stale binary and adds the orchestrator's explicit 69 failure arm. Evidence: a real binary with the wrong embedded commit returned 69 for a mutating verb, while `covered` retained its own 0 verdict and a fresh binary returned 0.
<!-- SECTION:NOTES:END -->

## Follow-ups

<!-- SECTION:FOLLOW-UPS:BEGIN -->
A Luna agent is hunting for remaining instances in `tmp/luna-string-hunt.md`; results land there.
<!-- SECTION:FOLLOW-UPS:END -->
