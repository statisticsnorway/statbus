---
id: STATBUS-245
title: >-
  canary-gate-says-why-it-waits: "not yet" should say whether to wait, watch, or
  investigate
status: To Do
assignee: []
created_date: '2026-08-19 07:11'
updated_date: '2026-08-19 10:11'
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

author: engineer
created: 2026-08-19 10:07
---
**WAVE B1 BUILT AND FROZEN. `cli/cmd/release_canary.go` only, plus its new test file. All nine ACs met; five oracles RED-verified.**

**AC#1 — THE STRUCTURAL CHANGE.** The probe no longer carries `AND state = 'completed'`. That filter WAS the defect: the box knew whether it had been offered, started, or failed, and the query threw it away before anyone could read it. One SSH round trip now returns two labelled lines — the candidate's row (state, completed/started/discovered timestamps, `recovery_parked_at`, error) and a context line (check interval, newest discovery). A missing ROW line IS the NOT-OFFERED answer, so absence is read as a fact rather than as an ambiguous empty string.

**AC#2/#5 — five named outcomes, with two classifications that are easy to get wrong and are pinned:**
- **A PARKED row is FAILED, not started.** It is `in_progress` with `recovery_parked_at` set — stopped, and it will not resume on its own. Calling it “in progress” would tell the reader to wait for something that never moves.
- **An UNKNOWN state is FAILED, not waiting.** Something we do not understand about a box we are about to promote past is closer to a fault than to patience.

**AC#4 — role-aware reading, the heart of it.** `canarySlot` gained a role. The same `available` row now renders in opposite directions:
- Norway: *“NOTHING IS WRONG — this slot is installed BY A PERSON, on purpose… The box has been holding the offer for 1 day(s) 1h.”*
- dev: *“THIS IS A FAULT ON THIS SLOT: dev is installed by the release chain, so it should never sit waiting for a person… which means the chain's deploy step did not run or did not reach this box.”*

**AC#9 — every line hands over the next move**, checked as a property across BOTH roles × every refusing outcome: each must contain “Your next move” plus a concrete handle (a command, a person, or a place). Norway's awaiting line names the person AND the exact command they run (`cd statbus && ./sb upgrade apply-latest`); the failed line is a numbered three-step — read the log, see the row, recover — and ends *“Do NOT promote past this: a canary that failed to install is the signal this gate exists to catch.”*

**AC#6 — duration, honestly.** The refusal reports the configured interval and when the box last DISCOVERED a release, and says in the same breath that this is *“not the last check”* — because a check that finds nothing new leaves no record. Claiming the stronger reading would be the same overstatement this gate exists to stop, one level down. Pinned.

**AC#7/#8 — explanation, never permission.** Exactly one outcome passes. The probe-failure path says explicitly that it is *not a verdict about the release* — the box may be healthy and merely unreachable — so an SSH problem is not read as a canary failure. A source pin forbids any timeout-into-pass construct, because the hazard is a future edit (“it has waited three days, let it through”) that would delete the human step the operator slot exists to perform.

**DEPLOY-BRANCH HINTS REMOVED, and pinned out.** The old refusal told the reader to `git push -f origin master:ops/cloud/deploy/dev`. Those refs are gone from origin as of this morning (STATBUS-244a), so that hint would now send someone to a branch that does not exist — worse than no hint, because it looks authoritative. A test fails on `ops/cloud/deploy`, `ops/standalone/deploy`, `master-to-`, or `push -f origin` reappearing anywhere in the file.

**TOPOLOGY** unchanged and now asserted: exactly dev (automatic) + no (operator). Demo is excluded with the reason recorded — it tracks stable, so it can only confirm a release after promotion, which is too late to gate on.

**ORACLES — RED-VERIFIED by mutation:** (1) parked reclassified as started → fails; (2) role-blind rendering → fails on dev's FAULT line; (3) a deploy-branch hint reintroduced → fails; (4) `AND state = 'completed'` reinstated → fails naming AC#1; (5) the wire format, including an error string containing the `|` separator.

**I RENDERED THE REAL OUTPUT AND READ IT** rather than trusting the assertions — the product of this unit IS the message. That caught a wording wart the tests happily passed (“Your next move: ask the Norway operator (SSB) — ask them to run…”), now fixed.

**VERIFY CHAIN:** `go build ./...` OK; `go test -count=1 ./...` 12 packages green; `gofmt -l` clean on both files; `golangci-lint run ./...` 0 issues.
---

author: architect (pinned by foreman)
created: 2026-08-19 10:11
---
B1 REVIEW VERDICT: AMENDMENTS REQUIRED — two must-fix, both in messages not decisions; the engineer's three flagged judgment calls RATIFIED as-is (parked→FAILED; unknown→FAILED as standing policy; the AC#6 honesty call — 'last discovered, not last checked' — ratified WITHOUT the stronger mechanism, which would write to a production box on every poll for a diagnostic nicety). Wire format verified genuinely delimiter-safe (error text is field 6, SplitN(...,6) keeps the remainder; newlines flattened in SQL at :328; unlabelled lines ignored → immune to CombinedOutput stderr merges). system_info + upgrade_check_interval premise verified (seeded '6h' by migration 20260311174120:82).

MUST-FIX 1: upgrade_state also carries superseded / skipped / dismissed (service.go:1494; :1707 sets superseded). The switch at release_canary.go:104-121 sends all three to default → canaryAttemptFailed → ':242 THE INSTALL WAS TRIED AND DID NOT SUCCEED' + failure archaeology — but none of them was tried. superseded = a newer candidate displaced this one (real next move: promote the newer). skipped/dismissed = deliberately set aside (STATBUS-250 will produce dismissed ON PURPOSE at every dev reset — a healthy reset would make the gate shout that an install failed). Verdict (refuse) is right in all three; only the message lies — the exact defect class this unit removes. Three explicit cases with true reasons; default stays FAILED for genuinely unknown states.

MUST-FIX 2: release_canary.go:190 tells the operator to run './sb upgrade apply-latest' — which resolves the LATEST on the channel (upgrade.go:210-232), not the specific rcCommit the gate waits on. The moment a newer RC exists (routine), the instruction installs a DIFFERENT version and the gate still refuses. Must name the candidate: './sb upgrade register <target> && ./sb upgrade schedule <target>' (register accepts tag or 40-char SHA, upgrade.go:77-79). Also aligns the gate with 247's ruled operator action and doc-035's card — as written they would contradict each other in front of the operator.

Re-freeze on those two for immediate turnaround.
---
<!-- COMMENTS:END -->
