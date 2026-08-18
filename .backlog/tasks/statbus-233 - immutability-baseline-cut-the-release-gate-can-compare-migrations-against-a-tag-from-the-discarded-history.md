---
id: STATBUS-233
title: >-
  immutability-baseline-cut: the release gate can compare migrations against a
  tag from the discarded history
status: To Do
assignee: []
created_date: '2026-08-18 14:53'
labels:
  - release
  - quality-gate
  - migrations
dependencies: []
references:
  - cli/cmd/release.go
  - cli/cmd/release_verify.go
priority: medium
type: bug
ordinal: 233000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A released migration must never be edited, because boxes that already applied it would silently differ from boxes applying the new version. The release gate enforces that by comparing this release's migrations against the previous release's. That comparison only means something if the two releases share a history — and right now, for one case, they do not.

WHAT GOES WRONG: this repository was rebaselined on 2026-07-14 — `77fa16fb25bfefe` is the root commit of the current history, and every earlier stable tag sits on a disconnected graph (`git merge-base --is-ancestor v2026.05.5 HEAD` says no). When the gate needs the previous *stable* rather than the previous RC, it reaches back across that boundary and compares two trees that share no ancestry. Git will happily diff them; the answer just means nothing. Every migration that was re-committed in the new root reads as "modified", and a genuine post-release edit would be indistinguishable from the noise.

THE DETAIL: `checkImmutabilityGate` (cli/cmd/release.go) asks `pickPrereleasePredecessor` for the tag to compare against. With prior RCs for the same patch it returns the previous RC — connected, meaningful, and the reason rc.02 through rc.04 were correctly quiet: nothing changed between consecutive RCs. With no prior RC it falls through to `findLatestStableTagBeforePrefix` (cli/cmd/release_verify.go:248), which crosses year-month boundaries by design — a correct rule that, since the rebaseline, can only land on a disconnected tag.

Scope is narrow and self-closing: it affects the FIRST release candidate of a new patch, and only until a stable exists in the current history. Promoting v2026.08.0 gives the next patch's first RC a connected baseline and the gate becomes meaningful again — for the first time since the rebaseline.

THE FIX: the gate should REFUSE rather than compare across disconnected histories. Check that the candidate predecessor is an ancestor of HEAD before diffing; if it is not, fail loudly, name the tag, and say that no meaningful immutability comparison exists — which is the honest state, and a state an operator can act on by blessing deliberately. A comparison whose result is noise must not be presented as a verdict either way.

WHY THAT HELPS: the gate stops being able to produce a confident answer from an unrelated tree. This class has bitten repeatedly this week in other costumes — a check reporting a result it had no basis for — and here the failure could go in either direction: a flood of false positives that trains an operator to bless past the gate, or, if blessed once, a whole corpus baselined without anyone reading it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The immutability gate verifies the chosen predecessor is an ancestor of HEAD before diffing migrations against it
- [ ] #2 A disconnected predecessor produces a loud refusal naming the tag and the reason, never a pass and never a flood of false modifications
- [ ] #3 The connected cases are unchanged: previous-RC comparisons and, once a stable exists in this history, previous-stable comparisons still work exactly as today
- [ ] #4 Verified against the current tree, where v2026.05.5 is provably not an ancestor of HEAD
<!-- AC:END -->
