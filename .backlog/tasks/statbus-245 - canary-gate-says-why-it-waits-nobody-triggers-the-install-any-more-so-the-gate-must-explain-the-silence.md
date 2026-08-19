---
id: STATBUS-245
title: >-
  canary-gate-says-why-it-waits: "not yet" should say whether to wait, watch, or
  investigate
status: To Do
assignee: []
created_date: '2026-08-19 07:11'
updated_date: '2026-08-19 07:16'
labels:
  - release
  - quality-gate
dependencies: []
references:
  - cli/cmd/release_canary.go
priority: medium
type: enhancement
ordinal: 238000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A release cannot be promoted until both canary boxes have installed it and survived. When the promotion gate says "not yet", the person reading it cannot tell whether the box has not started, is installing right now, or has failed and never will. All three look identical: no completed row.

WHAT GOES WRONG: the gate probes each canary for a completed upgrade at the candidate's commit and reports absence — nothing more. The natural response to an unexplained "not yet" is to re-run it a few times and then start looking for something broken, usually in the wrong place. That is how a five-minute wait becomes a lost morning.

THE DETAIL: the box knows the answer. It has a row for the candidate in some state, or none at all; it has a service with a check interval and a last-check time; and if it tried and failed, it has a parked or failed row saying so. The gate reads only the last of those and reports the absence rather than the situation.

Note this matters even once the release tag deploys the canary automatically (STATBUS-247). That change makes the deployment deterministic and gives the release chain its own convergence verdict — so most waiting resolves inside the chain — but the promotion gate can still run long after the chain finished, against a box that has since been redeployed, drifted, or parked. The gate is a separate observer of a separate moment, and it should explain what it sees rather than only report what it did not find.

THE FIX: when the completed row is absent, say which of the three it is. Is there a row for this commit at all, and in what state? When did the box last check, and how often does it? Then the refusal reads as "has not checked since 06:40, checks every 30 minutes", or "installing now, started 06:52", or "tried and is parked" — each pointing somewhere different. The information is one query further than the gate already goes.

WHY THAT HELPS: the operator learns whether to wait, watch, or investigate — from the gate itself, at the moment of refusal, instead of by opening an SSH session and reconstructing it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When a canary has no completed row, the gate distinguishes not-yet-discovered, in-progress, and failed/parked, naming which
- [ ] #2 The refusal reports the box's check interval and last check time so 'wait' has a duration attached
- [ ] #3 A parked or failed candidate row is called out as needing action rather than time
- [ ] #4 The gate still refuses in every case where it refuses today — this adds explanation, never permission
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 07:16
---
FRAMING CORRECTED BEFORE THE KING READS IT — and the correction is the stale-premise class, mine. The original opening said "nobody triggers the install any more, so the gate must explain the silence", written when I was proposing the channel-poll design now retracted as DRAFT-001. Under STATBUS-247 something DOES trigger the install, deterministically, and the release chain carries its own convergence verdict — so that sentence became false the moment the King ruled.

The substance survives on its own merits, which is why this is a reframe and not a retraction: the promotion gate runs at a DIFFERENT MOMENT from the chain, potentially long after it, against a box that may since have been redeployed, drifted, or parked. It is a separate observer, and a separate observer that reports only absence teaches people to re-run and hope.

Recorded rather than silently rewritten because a motivating sentence that a later ruling falsifies is exactly what cost us STATBUS-197 → 210 → 228 → 229, and the fix each time is the same: correct it where a reader would otherwise act on it.
---
<!-- COMMENTS:END -->
