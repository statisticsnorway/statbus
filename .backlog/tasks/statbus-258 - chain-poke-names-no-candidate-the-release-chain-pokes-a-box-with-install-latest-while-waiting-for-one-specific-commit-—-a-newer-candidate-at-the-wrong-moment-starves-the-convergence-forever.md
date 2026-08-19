---
id: STATBUS-258
title: >-
  chain-poke-names-no-candidate: the release chain pokes a box with "install
  latest" while waiting for one specific commit — a newer candidate at the wrong
  moment starves the convergence forever
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-19 19:14'
updated_date: '2026-08-19 19:53'
labels:
  - release
  - upgrade
dependencies: []
priority: medium
type: bug
ordinal: 251000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The dev-canary leg of the release chain (STATBUS-247, landed with C1 4324f1d3a) points dev's deploy branch at the candidate's commit and pokes the box via `./sb upgrade apply-latest` — but apply-latest resolves THE LATEST tag on the channel, not the commit the chain just pushed. If a newer RC exists at that moment (two cuts in flight, or a fix release tagged during the window), the box installs the newer one while the chain polls for convergence on the older one — and the convergence never arrives. The chain then reds (or hangs) on a box that is actually healthy and newer than requested.

Same defect family as STATBUS-256: a mechanism addressing "latest" where the contract is a SPECIFIC candidate. The architect flagged it during the 2026-08-19 dev-down incident review; it cannot bite on the first cut (the pushed candidate IS the newest) but becomes live the first time two candidates overlap.

THE FIX SHAPE (to be designed, not assumed): the poke should carry the candidate identity (commit SHA per canonical-commit-naming) and the box should install exactly that — register+schedule of a named target, not apply-latest — OR the chain's convergence check should accept "box is at the poked commit OR a descendant candidate on the same channel" with the reason logged. The first shape is preferred (candidate-addressed, matching STATBUS-244's ruling that only named candidates reach installations).

WHAT IS ACHIEVED: the chain's convergence poll can never be starved by a concurrent newer candidate, and a box never installs something other than what the chain believes it is testing.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 19:52
---
Assigned to the architect for design (dispatched 2026-08-19 post-cut). The approval unit is the architect's concrete design comment; the King reviews that, not a general direction. Context for the design: v2026.08.0-rc.08 was just cut — the chain's first live run is in progress, and this cut is the safe case (the pushed candidate IS the newest). The fix must land before two candidates can overlap.
---

author: architect
created: 2026-08-19 19:53
---
DESIGN, part 1 of 2 — what the mechanism actually does, which is worse than the ticket states, and which of the two shapes survives it.

## THE PROBLEM IS NOT A HANG. IT IS A GREEN THAT REPORTS ON A DIFFERENT QUESTION.

I expected the poll to wait forever for a commit the box never installed. It does not, and the truth is sharper.

`deploy-to-dev.yaml:85-94` captures apply-latest's stdout and takes the commit **from apply-latest's own `deployed_commit=` emit** — the commit the BOX resolved — then polls `ci-deploy-status.sh` for **that** (:100-102, :138). So the convergence check asks:

> *did the box converge on whatever the box decided to install?*

That is very nearly self-referential. It cannot hang, and it cannot fail for the reason we care about. **If a newer candidate exists when the poke lands, apply-latest installs the newer one, the poll confirms the newer one converged, and `deploy-to-dev` reports SUCCESS — while the chain believes dev took the candidate under test.**

That is the zero-scope family exactly: a green reporting on an examination it did perform, but not the one it claims. The promotion gate would still refuse later, because it looks for a completed upgrade at the candidate's own commit and would not find one — so the **safety** holds. What breaks is the signal, and it breaks in the direction that costs a debugging session: the chain says dev took it, the gate says it did not, and the two disagree with no line of output explaining why.

## SHAPE (b) IS NOT VIABLE. IT WOULD FORMALISE THE DEFECT.

Accepting poked-commit-or-descendant treats "the box installed something newer" as success. That is not a loosened tolerance, it is a decision to call testing-something-else a pass — the precise thing STATBUS-249 exists to remove one layer up, and it contradicts STATBUS-244's rule that only a named candidate reaches an installation.

**Shape (a): the poke names the candidate.**

## THE CONSTRAINT THAT DECIDES THE IMPLEMENTATION: the allowlist is byte-pinned

The remote command is not free-form. `ops/niue/sshdoers` pins the exact byte-string, and both call sites say so at the line (`deploy-to-dev.yaml:56-58`, and the poll at :129-131 warns explicitly *"it must match the sshdo-pinned byte-string exactly. Do NOT change it to $HOME."*). So the fix is not "pass an argument" — **it is a new allowlist entry, which needs root on the box.**

That rules out chaining `register && schedule` over one ssh: two commands with a shell operator is not an allowlistable byte-string of the shape sshdo already uses, and it would need the shell to be permitted rather than a command.

**So the design is a single new verb taking one argument**, matching the pattern `ci-deploy-status.sh <40hex>` already establishes: one command, one pinned argument shape.

## COST, and it is much smaller than it first looks

Only **chain-driven** slots need this, and there is exactly one: **dev**. Norway is human-installed (STATBUS-247), demo is channel-following with its own trigger (STATBUS-248), and the country slots are opt-in human under the King's amendment. So this is **one new verb plus one allowlist line on one box** — not a fleet-wide allowlist rollout.
---

author: architect
created: 2026-08-19 19:53
---
DESIGN, part 2 of 2 — the concrete change, piece by piece.

## 1. NEW VERB — `./sb upgrade apply <commit>` (cli/cmd/upgrade.go)

One command, one argument, candidate-addressed. It does what `apply-latest` does **minus the resolution step**: register the named target, schedule it, and emit `deployed_commit=<40hex>`.

It should be a thin sibling of `upgradeApplyLatestCmd` (cli/cmd/upgrade.go:155), reusing the same register→schedule sequence (:298-302) and the same `deployedCommitLine` emitter (:151). The only difference is where the target comes from: an argument instead of `ResolveChannelToLatestTag`. Everything downstream — the already-converged skip (`decideApplyLatest`), the staleness self-heal annotation, `RunSchedule` carrying `recreate` — is unchanged and must stay shared, not copied.

Accept the same target shapes `register` already accepts (tag, 8-char short, 40-hex full — upgrade.go:77-79), because `resolveUpgradeTarget` already exists and the chain will pass a 40-hex.

## 2. THE CHAIN'S POKE (.github/workflows/deploy-to-dev.yaml:88)

`./sb upgrade apply-latest` → `./sb upgrade apply <sha>`, where `<sha>` is the commit the chain pushed to the deploy branch — the one it already has, and already believes it is testing.

## 3. THE EMIT BECOMES A GUARD, NOT A SOURCE (deploy-to-dev.yaml:94)

Keep the `deployed_commit=` capture, but **stop using it as the poll's input**. The poll must use the SHA the chain REQUESTED. Then assert the two are equal, and **fail loudly if they differ**.

This is the piece that turns a self-referential check into a real one. Under candidate-addressing they can only differ if something resolved a target other than the one asked for — which is the very defect this entry removes, so it must be an error rather than a silent preference for whichever value happens to be at hand. It costs one comparison and it is the only thing standing between us and the same class returning through a future change to resolution.

## 4. THE ALLOWLIST (ops/niue/sshdoers, dev's entries)

One new line permitting `~/statbus/... upgrade apply <40hex>`, pinned in the same shape as the existing `ci-deploy-status.sh <40hex>` entry. **Root access, so it belongs in the King's next root session** — the same session already holding the STATBUS-253 removals.

**Two ordering facts that must travel with it:**
- The allowlist line must land **before** the workflow change, or the poke is refused by sshdo and dev takes nothing at all. Workflow-before-allowlist breaks the canary outright.
- **`apply-latest` must NOT be removed from the allowlist.** Demo's auto-apply trigger (STATBUS-248) depends on that exact byte-string, and demo genuinely wants latest-on-channel — that is the correct verb for a channel-following box. Only dev stops using it.

## WHAT IS DELIBERATELY NOT SPECIFIED

- **Whether the other slots' deploy workflows move.** et/jo/ma/tcc/ug still poke with apply-latest, and under the King's amendment they are opt-in human anyway; their deploy workflows are already queued for deletion behind the Wave D channel confirmation. Changing them here would be work on machinery we intend to remove.
- **Whether `apply-latest` should eventually take an optional target and collapse the two verbs.** Plausible, but it would change an existing allowlisted byte-string's meaning, and a verb whose behaviour depends on argument presence is exactly the shape that produced this ticket. Two verbs that each do one thing is the safer vocabulary; revisit only if a second caller ever wants the choice.
- **Test shape.** The builder should pin that the poke names a commit and that emit≠request fails, but I am not prescribing the mechanism — the recent units have chosen better oracles than I would have specified.

## WHAT IS ACHIEVED

The chain stops asking a box whether it did what it chose, and starts asking whether it did what the chain requested. After this, a `deploy-to-dev` green means the candidate under test is installed on dev — which is what everyone already reads it as meaning.
---
<!-- COMMENTS:END -->
