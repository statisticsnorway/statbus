---
id: STATBUS-252
title: >-
  gate-on-per-scenario-evidence: shadow first, switch on evidence — the
  promotion gate is the last thing to change
status: To Do
assignee: []
created_date: '2026-08-19 10:00'
updated_date: '2026-08-19 10:50'
labels:
  - release
  - quality-gate
dependencies: []
references:
  - cli/cmd/release.go
  - cli/internal/release/coverage.go
  - cli/internal/release/evidence.go
priority: medium
type: enhancement
ordinal: 245000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The promotion gate currently accepts whole-suite proof: one run in which every required scenario was present and succeeded, at the candidate's commit or at a ridable anchor. STATBUS-249 built a per-scenario decision that can answer the same question more precisely — twenty-seven scenarios covered by an earlier candidate, one that must run — and the question is whether the gate should move onto it.

**IT SHOULD, AND IT SHOULD BE THE LAST THING THAT DOES.** The gate is the single surface standing between us and a bad promotion. Everything else in the release chain is a cost optimizer whose wrong answer costs a fleet dispatch; the gate's wrong answer ships software. So the per-scenario path earns the gate rather than inheriting it.

**WHAT IS ACTUALLY GAINED** — this is not tidiness. Whole-suite proof is all-or-nothing: one missing scenario forces the entire 28-machine suite to re-run even when twenty-seven are demonstrably covered. Per-scenario turns that into running the one. That is real money and real wall-clock on every candidate, and it is exactly the saving STATBUS-249 exists to make honest.

**WHY IT IS SOUND HERE, stated so it is checked rather than assumed.** Whole-suite carries one property per-scenario does not: that the suite passed TOGETHER at a single code-state. For this harness that property is empty — every scenario provisions its own VM and runs alone, with no shared state between them (install-recovery-harness.yaml's one-VM-per-scenario matrix). Each scenario passing is the whole of what the suite passing means. **This reasoning must be re-examined if any suite ever gains inter-scenario dependencies**, because there the switch would genuinely weaken the gate.

**THE PLAN: SHADOW, THEN SWITCH.** Once STATBUS-246/247 land, the chain uses the per-scenario path on every cut while the gate keeps whole-suite authority. Both already run, so the comparison is free. Any disagreement between them is a signal, observed at zero risk, before anything is rewired. Switch when the two have agreed across real candidates; investigate rather than switch if they have not.

**THREE PRECONDITIONS ON THE SWITCH:**

1. **The required-scenario list must be derived from the TARGET commit's domain, never from the evidence found.** The gate today derives it at the candidate's commit (`upgradeArcNamesAtCommit`), which is what makes a newly added scenario un-inheritable — an old run cannot contain it, so the suite is incomplete and the gate refuses. If the per-scenario loop instead iterated over scenarios it found evidence for, a newly added scenario would silently drop out of the gate entirely. That is a zero-scope green of the exact family this work exists to remove, arriving through the fix for it.

2. **A per-commit cache for run and job lookups is required, not optional.** Per-scenario, each of ~28 scenarios may walk up to 20 candidates — up to ~560 API calls against a gate that today makes ~20. The candidate commits are the same across scenarios, so caching by commit collapses this back to roughly today's cost. Without it we would meet the API limits for real: STATBUS-249's first live run already surfaced 7 runs it could not read.

3. **Coverage refusals must keep naming what they examined.** The per-scenario verdict already carries its anchor, its blocked-by, and its unreadable candidates. The gate's rendering must surface all three, or the switch trades a blunt refusal for a quieter one.

WHAT IS ACHIEVED: the gate becomes as precise as the evidence it reads, and it gets there by having been proven in the seat where mistakes are cheap first — which is the same discipline we apply to release candidates themselves.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The chain runs the per-scenario path while the gate retains whole-suite authority, for a period covering multiple real candidates
- [ ] #2 Disagreements between the two paths are surfaced and investigated, not averaged — agreement across real cuts is the evidence that authorizes the switch
- [ ] #3 The required-scenario list is derived from the target commit's domain; a newly added scenario is never inheritable and never silently absent
- [ ] #4 Run and job lookups are cached per commit, keeping the gate's API call count at roughly its current level
- [ ] #5 Gate refusals name the anchor ridden, the anchor blocked and why, and any candidate that could not be read
- [ ] #6 The independence argument is recorded with the switch: it holds because scenarios share no state, and must be re-examined for any suite where they do
- [ ] #7 The switch is a deliberate, separately reviewed change — never folded into a wave doing other work
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 10:50
---
SHADOW PHASE LANDED as 3bb852eb6 (architect APPROVED through the memoize amendment cycle). Live advisory-only from the next gate run: both promotion gates print the per-scenario answer beside the whole-suite authority at all six outcomes; the shadow structurally CANNOT vote (runShadowCoverage returns nothing — consulting it requires a signature change, RED-verified both directions); domain from the target commit with refusal-to-report on an empty/underivable domain; undecidable mapped onto neither verdict; both disagreement directions (too-lenient / too-strict) reported separately; shared causes reported once with 'no comparison is possible, so none is claimed'. Resource starvation closed by an (apiBase, workflow, commit) process-lifetime memo — 50→1 calls RED-verified, errors NOT cached, answers provably unchanged, lock released before the network call. HOW TO READ THE FIRST LIVE RUN (architect's note, do not misread): an ALL-UNDECIDABLE shadow is a TOKEN/BUDGET SIGNAL, never a coverage signal, and under this entry it is explicitly NOT a disagreement — the switch decision needs runs where the two paths actually compared. The switch itself (authority transfer) remains this entry's second half, King/architect-gated on accumulated agreement across real candidates.
---
<!-- COMMENTS:END -->
