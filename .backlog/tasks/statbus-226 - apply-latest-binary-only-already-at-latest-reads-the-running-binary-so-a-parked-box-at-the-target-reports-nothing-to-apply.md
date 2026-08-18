---
id: STATBUS-226
title: >-
  apply-latest-binary-only: "already at latest" reads the running binary, so a
  parked box at the target reports nothing to apply
status: To Do
assignee: []
created_date: '2026-08-18 09:57'
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
