---
id: DRAFT-001
title: >-
  canary-follows-rc-channel: the canary boxes should install release candidates
  by themselves, the way every operator does
status: Draft
assignee: []
created_date: '2026-08-19 07:10'
updated_date: '2026-08-19 07:15'
labels:
  - release
  - upgrade
  - ops
dependencies: []
references:
  - cli/cmd/release_canary.go
  - cli/internal/upgrade/github.go
  - cli/internal/upgrade/service.go
priority: high
type: enhancement
ordinal: 236000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Before a release can be promoted, two canary boxes must have installed it and survived. Today a human makes that happen by pushing a branch, and what gets installed is whatever master's tip happens to be — not the release candidate. That is backwards: the boxes should install the candidate on their own, exactly the way a statistical office installs a release, and the gate should then clear because it really happened.

WHAT GOES WRONG: the release candidate is a tag, but the deployment mechanism pushes a branch. The two drift apart the moment anyone commits after the cut — which happened this morning, when a board commit moved the tip past the tag and the canary installed the wrong thing. Worse, the human push means the canary proves a path no operator ever walks: nobody in an NSO pushes a deploy branch.

THE DETAIL, AND WHY THIS IS SMALLER THAN IT LOOKS: **the product already does this.** The upgrade service on every box polls for its channel's latest release, registers it as a candidate, schedules it, and executes the upgrade autonomously — the same discover → register → schedule → execute path an operator relies on. The channel is a single setting, `UPGRADE_CHANNEL` in `.env.config`, and `prerelease` already means exactly "the latest release candidate" (cli/internal/upgrade/github.go:266, with explicit filtering so it cannot mean "any release"). The canary slots are simply not using it — they sit on the default while a parallel, older mechanism pushes branches at them.

So this is not a new mechanism. It is pointing the canaries at the one the product already ships, and deleting the human from the loop.

THE FIX: set the canary slots (dev on niue, no on rune) to follow the prerelease channel, and let their own service tick do the rest. The completed upgrade row then carries the candidate's exact commit by construction — which is precisely what the promotion gate probes for (cli/cmd/release_canary.go) — so the gate clears without anyone pushing anything.

Two things to verify rather than assume, because the flow only works if both hold: that cutting a candidate publishes a GitHub release marked prerelease, in the shape the channel filter looks for; and that the per-commit images already exist when the tag appears (they are built by the master push that preceded it, so they should, but a canary that installs before its artifacts exist is the one failure this design could introduce).

ACCEPT KNOWINGLY: after this, dev and no upgrade themselves to every candidate, including a bad one, with no human in the loop. That is what a canary is for — they take the damage so production does not — and the rollback, park and un-park machinery hardened this week is exactly what is meant to catch it. The canary becomes the first real user of the recovery system rather than a synthetic test of it.

WHY THAT HELPS: a cut becomes one act with an automatic consequence — tag, build, install, gate clears — with no step that depends on someone remembering to push the right branch at the right moment. And the canary starts proving the operator's real path instead of an internal one, which is the only version of the evidence worth having.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The canary slots follow the prerelease channel and install a newly cut candidate with no human action
- [ ] #2 Verified: cutting a candidate publishes a GitHub release the prerelease channel filter selects, and the per-commit images exist before the canary installs
- [ ] #3 The promotion gate finds a completed upgrade row at the candidate's exact commit on both slots, with no deploy-branch push involved
- [ ] #4 Proven end to end on a real cut (rc.07): tag → build → canary installs itself → gate clears
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 07:15
---
SUPERSEDED BY STATBUS-247 — RETRACTED BY ME, before anyone builds it. I proposed reaching the same outcome by pointing the canaries at the prerelease CHANNEL, so each box discovers the candidate on its own tick. The King ruled for the ops machinery instead: the release tag points the existing deploy branch at the tag's commit, and the existing deploy + convergence layers do the rest.

His is the better answer, and I would rule the same way now that the inventory is in front of me. The channel path makes the box discover on a poll, so the cut waits on a tick and the gate has nothing synchronous to observe. The tag-pointer path is immediate, and it ends in a convergence poll that answers by COMMIT — so the cut gets a verdict rather than a wait, which is what "it's installed, and it clears the gate" actually requires.

I am retracting rather than leaving both on the board, because STATBUS-244 — my own entry — says two mechanisms must not aim at the same box. Leaving a channel-based proposal alongside a tag-based one would be exactly the second source of truth that entry forbids, and it would be worse for being mine. The consistency has to run in both directions or it is not a principle.

What survives from this entry, folded into 247: the operator-parity argument (the canary should prove the path a statistical office walks, not an internal one), the two premises worth verifying rather than assuming (the artifacts must exist when the tag lands), and the acceptance to be made KNOWINGLY — the canaries will take every candidate automatically, including a bad one, which is what a canary is for and what the rollback and un-park machinery exists to catch.

STATBUS-244 (deploy branches out of the RC path) still stands unchanged and is now MORE necessary, not less: under 247 the release path uses those branches deliberately, so the ad-hoc manual buttons must be the thing that leaves the release path, with the boundary documented.
---
<!-- COMMENTS:END -->
