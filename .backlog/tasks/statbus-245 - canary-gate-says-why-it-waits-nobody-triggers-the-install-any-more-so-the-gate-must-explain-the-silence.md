---
id: STATBUS-245
title: >-
  canary-gate-says-why-it-waits: "not yet" should say whether to wait, watch, or
  investigate
status: To Do
assignee: []
created_date: '2026-08-19 07:11'
updated_date: '2026-08-19 07:58'
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
A release cannot be promoted until the canary boxes have installed it and survived. When the promotion gate says "not yet", the person reading it cannot tell whether the box has not been offered the release, has been offered it and is waiting for an operator to act, is installing right now, or has tried and failed. All four look identical: no completed row.

WHAT GOES WRONG: the gate probes each canary for a completed upgrade at the candidate's commit and reports absence — nothing more. The natural response to an unexplained "not yet" is to re-run it a few times and then start looking for something broken, usually in the wrong place. That is how a five-minute wait becomes a lost morning.

THIS BECAME LOAD-BEARING, not merely helpful, under the canary topology (STATBUS-247). Norway is now installed BY A PERSON on purpose, to exercise the real operator surface. So "waiting" is no longer a few minutes of machinery — it is a legitimate, expected, possibly day-long state in which the correct action is to go and ask someone. A gate that cannot separate "waiting for a person" from "the person tried and it failed" reports the most important distinction in the whole release process as a single undifferentiated silence.

THE DETAIL: the box knows the answer. It has a row for the candidate in some state, or none at all; it has a service with a check interval and a last-check time; and if it tried and failed, it has a parked or failed row saying so. The gate reads only the last of those — its query filters to state='completed', so every other state collapses into "no row" (cli/cmd/release_canary.go:100-105, 129-148).

THE FIX: query the row by commit and report its actual state. Named outcomes, each pointing somewhere different:

- **NOT OFFERED** — no candidate row for this commit. The box has not discovered the release. Points at discovery: when did it last check, how often does it check.
- **OFFERED, AWAITING OPERATOR** — row present, state 'available'. Nothing is wrong. A person needs to act, and the gate should print how long it has been waiting and the exact command that person runs on that box. This is the state Norway sits in by design, and on dev it means something quite different — the chain should have installed it, so the same state there is a fault.
- **OPERATOR STARTED** — scheduled or in_progress, with the start time. Wait.
- **OPERATOR ATTEMPT FAILED** — failed, rolled_back, or parked. This is a hard red and must never read like waiting. Investigate.
- **COMPLETED** — pass.

THE WAIT IS OPEN-ENDED BY DESIGN and the gate must never resolve it by timing out into a green. It stays refused-but-explained until a person acts. A gate that ages into a pass would silently delete the very step the human canary exists to perform.

WHY THAT HELPS: the operator learns whether to wait, watch, ask a colleague, or investigate — from the gate itself, at the moment of refusal, instead of by opening an SSH session and reconstructing it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The gate queries the candidate row by commit and reports its actual state, rather than filtering to completed and reporting absence
- [ ] #2 Five outcomes are distinguished by name: not offered, offered-awaiting-operator, operator-started, operator-attempt-failed, completed
- [ ] #3 'Offered, awaiting operator' prints how long it has been waiting and the exact command the operator runs on that box — it reads as a pending human action, not as a malfunction
- [ ] #4 The same state is read against the slot's role: awaiting-operator is the expected resting state on Norway and a fault on dev, where the chain should already have installed it
- [ ] #5 A failed, rolled-back, or parked candidate is called out as needing action rather than time, and is never rendered in the same shape as waiting
- [ ] #6 The refusal reports the box's check interval and last check time so 'not offered' has a duration attached
- [ ] #7 The wait never times out into a pass — the gate stays refused until a completed row exists
- [ ] #8 The gate still refuses in every case where it refuses today — this adds explanation, never permission
- [ ] #9 Every outcome line carries its actionable handle — the exact command to run, the person/place to ask, or the direct link to look at (e.g. the GitHub run, the box's upgrade log) — never a bare state name; the King's test: the reader must end knowing their next move, not merely the system's state
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

author: foreman
created: 2026-08-19 07:58
---
KING APPROVED 2026-08-19 (dialogue presentation, second of five), with a sharpening now added as AC#9, his reasoning near verbatim: the change is "critical and inconsequential" — it changes nothing, only exposes what we already know — and precisely because of that, THE ACTIONABLE PART AND THE MESSAGE ARE WHAT MATTER: the human operator must know what they are waiting for, WHO to speak to, or WHAT to look at (such as the link to the GitHub run) — "not just a black hole, or 'you're waiting for something, I know, but I can't do anything about it.'" Every outcome must hand the reader their next move. Builder note: this is the same doctrine as the failure messages that teach (239's shallow guard, the hybrid-tree diagnosis) applied to the gate's every line.
---
<!-- COMMENTS:END -->
