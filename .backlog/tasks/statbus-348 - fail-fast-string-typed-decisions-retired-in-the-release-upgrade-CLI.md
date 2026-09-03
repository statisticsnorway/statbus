---
id: STATBUS-348
title: >-
  fail-fast: string-typed decisions retired in the release/upgrade CLI
status: In Progress
assignee: []
created_date: '2026-09-03 23:27'
updated_date: '2026-09-03 22:01'
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
Luna's hunt is in `tmp/luna-string-hunt.md`: 6 DEFECT, 15 SMELL, 20 ACCEPTABLE-CONTRACT. Sol's review (`tmp/sol-review-347.md`) finding 4 lands on THIS ticket.

REOPENED 2026-09-03 22:01 (foreman): 050a37655 is incomplete. `release covered` was kept in readOnlyCommandPaths, so the guard never exits 69 for it and the orchestrator's 69 arm cannot fire for the condition it names (Sol S4). Two more collisions on the same channel: cobra argument refusal exits 1 (= `covered`'s must-run, Luna D2) and inject.Validate exits 2 (= undecidable, Luna D3). Luna owns the coherent contract: 0/1/2 verdicts only; 69 for every binary refusal including inject; 64 (EX_USAGE) for usage; orchestrator arms for 0/1/2/64/69/other. Proof required with real binaries. Closes when that commit lands.

Deferred from Luna's hunt to STATBUS-349: D4 (migrate exit 22 has no producer), D5 (apply-latest second tag classifier), D6 (isConnError retries context cancellation by prose), and the 15 SMELLs.
<!-- SECTION:FOLLOW-UPS:END -->
