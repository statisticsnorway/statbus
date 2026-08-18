---
id: STATBUS-233
title: >-
  immutability-baseline-cut: the release gate can compare migrations against a
  tag from the discarded history
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-18 14:53'
updated_date: '2026-08-18 15:45'
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
- [x] #1 The immutability gate verifies the chosen predecessor is an ancestor of HEAD before diffing migrations against it
- [x] #2 A disconnected predecessor produces a loud refusal naming the tag and the reason, never a pass and never a flood of false modifications
- [x] #3 The connected cases are unchanged: previous-RC comparisons and, once a stable exists in this history, previous-stable comparisons still work exactly as today
- [x] #4 Verified against the current tree, where v2026.05.5 is provably not an ancestor of HEAD
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-18 15:41
---
**BUILT, FROZEN for review (no commit).** Files: `cli/cmd/release.go` (the refusal + a small extraction), `cli/cmd/release_verify.go` (`tagIsAncestorOfHEAD`), new `cli/cmd/immutability_disconnected_test.go`. All four ACs met.

**PREMISE VERIFIED FIRST, not inherited:** `git merge-base --is-ancestor v2026.05.5 HEAD` exits non-zero on this tree, and `git rev-list --max-parents=0 HEAD` returns exactly `77fa16fb25bfefeb372a6ef0c856353cfe8dd9e6`. The ticket's facts hold as written.

**AC#1 — the gate checks ancestry before diffing.** New `tagIsAncestorOfHEAD` (release_verify.go) wraps `git merge-base --is-ancestor`, and — deliberately — distinguishes the ANSWER from a FAILURE: a non-zero exit is confirmed as a true negative by re-resolving both refs, so a bad ref or an unreadable repo returns an error instead of silently reading as "not an ancestor". The gate refuses on that uncertainty too, with its own message; a typo must never be able to masquerade as a disconnection.

**AC#2 — the refusal names the tag, the reason, the proof and the remedy**, and refuses BEFORE any diff runs so the flood cannot reach the console:
```
✗ Migration immutability CANNOT BE CHECKED against v2026.05.5 — that tag is NOT an ancestor of HEAD
  The two histories are disconnected, so a migration diff between them is noise, not a verdict…
  Verify: git merge-base --is-ancestor v2026.05.5 HEAD   (exits non-zero — no shared ancestry)
  Fix: promote the first stable in THIS history … this refusal then disappears on its own.
```

**RED-VERIFIED, AND THE CAPTURED OUTPUT IS THE TICKET'S ARGUMENT MADE CONCRETE.** With the ancestry check removed, the gate produces exactly what you predicted — including the part that matters most:
```
✗ Migrations modified since v2026.05.5 (previous stable)
M migrations/20260101000000_init.up.sql
  STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=20260101000000 ./sb release prerelease
```
It does not merely report a phantom modification — it hands the operator the **bless command** for it. That is the "trains an operator to bless past the gate" mechanism, captured verbatim rather than argued.

**AC#3 — connected cases unchanged, with a positive control.** `TestImmutabilityGate_ConnectedPredecessorStillCompares_STATBUS233` uses the existing `immutabilityFixture` (tag, then EDIT the released migration) and asserts the gate still FAILS it, and that the disconnection message does NOT appear. Without that arm, "refuses disconnected predecessors" could be satisfied by refusing everything.

**AC#4 — asserted against THIS repository**, not a fixture: `TestRealRepo_PreRebaselineTagIsDisconnected_STATBUS233` checks v2026.05.5 really is not an ancestor of HEAD. It skips when the tag is not fetched locally, and if a future re-graft ever connects it the test says so — because the refusal's wording tells operators the histories are disconnected, and that sentence would then be wrong.

**ONE STRUCTURAL CHOICE TO REVIEW:** I split `checkImmutabilityGate` into predecessor DISCOVERY (which tag) and `checkImmutabilityGateAgainst(projDir, prevTag)` (does comparing against it mean anything, and only then compare). Discovery needs the live tag list, so without the split the gate-level arms could not be driven with an explicit tag. Behaviour is otherwise identical; the early "no previous tag" return stays in discovery.

**Verification:** `go test -count=1 ./...` in cli/ — 12 packages ok, 0 failures (`-count=1` per my own STATBUS-234 finding, since these arms read repo files from outside the module). `gofmt -l` clean. `golangci-lint` 2.12.2 — 0 issues.
---

author: architect (pinned by foreman)
created: 2026-08-18 15:45
---
APPROVED (architect verdict, pinned verbatim in substance): the attack target was tagIsAncestorOfHEAD's failure arm — "couldn't determine" misread as "not an ancestor" is what ships looking right. It is sound, and its imprecision is bounded and lands SAFE: re-resolving both refs is a proxy, so a broken repo with resolvable refs reads "not an ancestor" — but that makes the gate REFUSE, the direction we want under uncertainty. No path to a false positive: true only on exit 0. The discovery/verdict split is better than 216's seam pattern — the tag is a parameter, no mutable global, no cleanup discipline. The positive control genuinely discriminates (without it, refuse-everything would pass). LANDED as 7cbe56008.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The release gate's migration-immutability check now verifies its chosen predecessor tag is an ancestor of HEAD before diffing, and refuses loudly — naming the tag, the verifying command, and the remedy — when it is not. Before this, the first RC of a new patch (no prior RC, previous stable on the pre-rebaseline disconnected graph) diffed two unrelated trees and printed every re-committed migration as \"modified\", complete with the bless command for the phantom edit — the exact mechanism that trains an operator to bless past the gate. tagIsAncestorOfHEAD separates the answer from a git failure (a bad ref errors instead of masquerading as disconnection); a positive control proves connected-predecessor comparisons still fail on a real edit; and the disconnection of v2026.05.5 is asserted against this actual repository. Built by engineer, adversarially reviewed and approved by architect, landed as 7cbe56008.
<!-- SECTION:FINAL_SUMMARY:END -->
