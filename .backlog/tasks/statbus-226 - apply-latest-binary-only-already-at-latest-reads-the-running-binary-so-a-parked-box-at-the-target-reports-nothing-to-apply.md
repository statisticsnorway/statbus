---
id: STATBUS-226
title: >-
  apply-latest-binary-only: "already at latest" reads the running binary, so a
  parked box at the target reports nothing to apply
status: Done
assignee: []
created_date: '2026-08-18 09:57'
updated_date: '2026-08-18 14:57'
labels:
  - upgrade
  - deploy
  - park
dependencies: []
references:
  - cli/cmd/upgrade.go
  - .github/workflows/deploy-to-demo.yaml
priority: low
type: bug
ordinal: 226000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: `./sb upgrade apply-latest` resolves the channel's latest version and, when the box is genuinely behind, registers and schedules it. It first short-circuits the common no-op case: if the target resolves to the commit the running binary was built from, there is nothing to deploy, so it prints "Already at &lt;version&gt; — nothing to apply" and returns success instead of driving a whole no-op upgrade pipeline.

WHAT GOES WRONG: the comparison reads the running binary's compiled-in commit, which answers "what code is executing", not "did this box converge". A box can be running the target binary and still not be at the target — most concretely a box parked after a post-swap failure whose era guard refused the source restoration: the swap already happened, so the binary is the target, while the upgrade row sits parked and the services stay behind the maintenance page. Asked to apply that same version, the command reports nothing to apply and exits 0.

THE DETAIL: the skip is in cli/cmd/upgrade.go, comparing the first 8 hex of the resolved target against the ldflags-set `commit`, and returning nil on a match. Its documented fall-throughs are careful in the other direction — an unresolvable target or an unknown build commit always proceeds — so the only way to reach the skip is a positive match, and a positive match is exactly the parked-at-target state as well as the healthy already-converged one. The two are indistinguishable to this check because the row is never consulted.

Reachability is real, not theoretical: STATBUS-200's era guard refuses restoration on a post-delta park by design, which leaves precisely this shape — target binary, parked row, dark box.

**Not a deploy-path defect, and the ticket is Low for that reason.** The deploy workflows do not trust the poke's exit code: apply-latest emits its `deployed_commit=` line before the skip, and the STATBUS-170 phase-2 step then polls that exact commit until the row reaches `completed` (.github/workflows/deploy-to-demo.yaml). A parked row never reaches it, so a CI deploy goes red on the poll. The exposure is a human running the command directly on a box, who is told there is nothing to do while the box is parked and dark.

THE FIX: consult the row, not only the binary. Skip only when the target's row is actually `completed`; when the row exists in any other state — parked above all — say so and name the remedy (`./sb install` un-parks for one fresh attempt) rather than reporting nothing to apply.

WHY THAT HELPS: it closes the same class STATBUS-210 and STATBUS-212 close one layer down — a marker that describes one thing while its reader infers another. Here the claim is about the binary and the operator hears it as a claim about the box.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The already-at-latest skip consults the target's upgrade row and short-circuits only when that row is completed
- [ ] #2 A parked row at the target version produces an actionable message naming the un-park remedy, not "nothing to apply"
- [ ] #3 The documented fall-throughs still never produce a false skip: unknown build commit or unresolvable target still proceeds to register+schedule
- [ ] #4 A genuinely converged box still skips without running a no-op upgrade pipeline
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-18 14:54
---
**REPRODUCER WENT RED — the bug is real, and the fix is BUILT and FROZEN for review (no commit).** Files: new `cli/cmd/upgrade_apply_latest_decision.go`, new `cli/cmd/upgrade_apply_latest_decision_test.go`, `cli/cmd/upgrade.go` (the skip block), `cli/internal/upgrade/service.go` (one new reader).

**TEST-FIRST, AND THE RED IS GENUINE — not red-by-nonexistence.** The decision lived inside apply-latest's cobra `RunE` closure, so I extracted it to a pure function FIRST, carrying the pre-226 binary-only logic verbatim, and ran the oracles against that. Result: the parked-at-target row earned a **SKIP**, and so did every other non-completed row — eight shapes in one property test, including `{Found:true State:in_progress Parked:true ParkedReason:"post-swap health park"}`. That is the ticket's defect reproduced exactly: the box is dark and the operator is told "nothing to apply". Then the row consult went in and all arms went green.

**THE FIX (AC#1-#4).** `decideApplyLatest(latestVersion, resolvedCommit, buildCommit, row)` returns Skip / Refuse / Proceed:
- **Skip** ONLY when the row is found, unparked, and `completed` (AC#1, AC#4 — the converged box still short-circuits, no no-op pipeline).
- **Refuse** when the row is PARKED: names the park reason and the remedy (un-park for one fresh attempt, or schedule a fix release to supersede), and returns a non-zero exit rather than a reassuring zero (AC#2).
- **Proceed** for every uncertainty — unknown build commit, unresolvable target, no row, unreadable row, or a row in any other state (AC#3). The one-directional discipline the pre-226 fall-throughs had is preserved and now stated as its own property test: *no row shape may earn a Skip except found+unparked+completed*, with a positive control so it cannot be satisfied by never skipping at all.

**On the deploy path:** this turns a parked box from "exit 0, then red at the STATBUS-170 convergence poll" into "red at the poke, with the reason". Same redness, earlier and legible — no deploy that passes today starts failing.

**One implementation detail I corrected mid-build rather than leaving:** my first `RowStateForCommit` called `connect()` by hand, which opens BOTH a query and a listen connection and leaves them open for the life of the process — wrong for a one-shot CLI verb. It now goes through the house `runOneShot` wrapper, which is what `RunSchedule`/`RunRegister` use and which closes both on the way out. I checked `connect()` for an advisory-lock side effect before wiring it (there is none, so no daemon conflict).

**Verification:** `go test ./...` in cli/ — 12 packages ok, 0 failures. `gofmt -l` clean on all four files. `golangci-lint` 2.12.2 — 0 issues.

**Not claimed:** AC#2's message is pinned by unit test, not observed on a parked box — no VM. The behaviour is a pure function of the row state, so the risk sits in the row READ, not the decision; `applyLatestRowState` collapses every read failure to "proceed", which is the safe direction.
---

author: foreman
created: 2026-08-18 14:57
---
LANDED at 4bfdefa8d, architect-approved (his verdict: the refusal is keyed on the TARGET'S OWN row, so a box parked on one version deploying a fix release proceeds — the refusal can never block the cure, which was the one way this fix could have hurt; the extracted-verbatim RED method praised as pinning the parked-at-target behavior permanently without a VM). His optional nit folded at commit: the refusal names ./sb install literally. Done.
---
<!-- COMMENTS:END -->
