---
id: STATBUS-256
title: >-
  gate-reports-red-as-absent: a failed run must be reported as a failure to
  investigate, never as a missing run to trigger
status: Done
assignee: []
created_date: '2026-08-19 12:35'
updated_date: '2026-08-19 20:01'
labels:
  - release
  - quality-gate
dependencies: []
priority: medium
type: bug
ordinal: 249000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The release preflight's go-test gate (and any sibling gate using the same walk) reports "workflow has not run for <commit>" with the fix "trigger it and wait for green" — even when a run EXISTS at a relevant ancestor and FAILED. Observed live 2026-08-19: go-test ran automatically at the batch head d59f5e06d and went red (the TempDir/git-gc race, now its own post-tag unit); the preflight at the board-only tip then said "has not run… no green run" and prescribed a manual trigger. The King asked the exact right question — "is there a bug in the detection of needing to run?" — and the answer is: not in the trigger, not in the refusal, but in the MESSAGE.

WHY IT MATTERS: "never ran" and "ran and failed" demand opposite operator actions. A missing run needs a dispatch; a failed run needs an INVESTIGATION — and prescribing a re-run for a red is the re-run-until-green anti-pattern in the gate's own mouth. Today the red was a test-infra race and the re-run was honestly green; had it been a real code bug, the gate's own advice would have green-washed it.

THE FIX: when the walk finds candidate runs that are RED at commits whose diff-to-tip is exempt-only, the refusal must say so first — "go-test FAILED at <commit> (<run link>) — investigate the failure; do not simply re-run" — and only fall back to "has not run, trigger it" when genuinely NO run exists anywhere relevant. The failed-run arm should carry the no-flaky-tests principle in its text: every failure has a real cause; a green re-run without a diagnosis proves nothing.

Same message-truth family as STATBUS-240/245: the verdict was right, the words lied about the world. Post-tag build queue.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 12:36
---
SECOND FACE OBSERVED LIVE, same sitting (King's second refusal paste): the images gate said 'has not run for 0d83061c612c — Trigger: gh workflow run images.yaml' while the images run at that exact commit was IN PROGRESS (created 12:26:30, automatic on push, green minutes later) — the operator was instructed to manually start a job that was already running. So the defect is fully general: the refusal vocabulary has two words (green/absent) for a four-state world — GREEN (pass or ride), RED (investigate, link, never bare re-run), RUNNING (wait, link, re-run preflight after), ABSENT (trigger, command). THE FIX covers all arms: checkWorkflowAtCommit and its callers must distinguish and name all four, each with its own next move. The King found both faces himself from the operator's chair within one sitting — the strongest possible evidence this is operator-surface load-bearing, not polish.
---

author: engineer
created: 2026-08-19 19:59
---
**BUILT AND FROZEN — not landed.** Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, gofmt clean. Files: `cli/cmd/release.go`, `cli/cmd/release_ancestor_verdict.go` (new), `cli/cmd/release_ci_exempt_ride_test.go`.

**Where the defect actually was — not where it looked.** `checkWorkflowAtCommit` was already correct: it returns Green, Failed, Pending, Missing and Unknown, and always has. The four arms in the caller's switch were correct too, and each says something TRUE about the tip. Nothing in the detector was ever missing.

The loss happened in the exempt-ride walk, at one line: when an exempt-clean ancestor's run was not green, `findExemptRide` did `continue` and kept only "not green". So the caller was left with the tip's own state — and a board-only tip legitimately has no run — and printed "has not run — trigger it": true about the tip, and useless about the operator's situation.

That is why both faces looked like the same bug from the console and neither was a detection bug. The King's question was exactly right, and so was the answer: not the trigger, not the refusal, the MESSAGE — but the message was starved by the walk, not written wrong.

**What changed.** The walk now records the first non-green verdict it meets at an exempt-clean ancestor (`ancestorVerdict`: commit, commits-since, full result) and hands it back. When the tip is Missing AND such a verdict exists, that verdict is reported instead — because an ancestor whose diff to the tip is exempt-only is running THE SAME CODE, so its red is a red on what is being released and its in-progress run is this code's verdict still being computed. Both gates are wired: the go-test/images path and the pg_regress path.

`printAncestorVerdict` gives each state its own sentence and its own next move: RED → name the failure, link the run, INVESTIGATE, with the no-flaky principle in the text ("a green re-run without a diagnosis proves nothing except that the second attempt behaved differently, and it green-washes a real bug just as readily as a flaky one"). RUNNING → link, wait, and explicitly do NOT trigger another. The tip's own absence is still printed underneath, so nobody mistakes the ancestor's run for the tip's.

**ONLY A REAL VERDICT COUNTS — and my first version got this wrong.** I initially recorded any non-green ancestor, including Missing. My own test caught it: with no run anywhere, "has not run — trigger it" is the TRUE and correct advice, and reporting a verdict there would have replaced one wrong message with another. Narrowed to Failed and Pending only; Missing and Unknown are not verdicts about the code (Unknown is a statement about the API).

**FIVE REDs, mutation site asserted on each:** discarding the ancestor verdict (the original defect) fires; recording absence as a verdict fires; dropping the run URL/id the operator needs to investigate fires; the red arm prescribing `gh run rerun` fires; the running arm prescribing `gh workflow run` fires.

The last two are behavioural rather than structural — they capture stdout and read what an operator would read, asserting that neither arm contains a dispatch or a bare rerun. The operator surface IS the deliverable here, so testing the intent rather than the output would have missed the point of the ticket.

**Deliberately untouched:** the pending arm on the TIP, which fires correctly today; and the Missing arm's trigger prescription, which stays exactly as it was for the genuine no-run-anywhere case — a test pins that it is still reachable.

One note: `.backlog/tasks/statbus-258…md` is dirty in the tree and is not mine — it was already modified when I started.
---

author: foreman
created: 2026-08-19 20:01
---
LANDED as 540f56417, architect verdict LAND with nothing to fold. The defect was one layer below the brief: the four-state detector was always correct; findExemptRide discarded every non-green ancestor verdict with a bare continue, starving the message. Now the walk hands back the first real verdict (Failed or Pending ONLY — recording Missing would swap one wrong message for another) and it outranks the tip's absence, both gates wired. Architect's noted standout: the default arm declares a state it cannot name and asks for it to be reported, instead of falling through to a plausible wrong message. Risk property: the gate's pass/fail outcome is UNCHANGED — every arm still refuses; only words and prescribed actions changed. Five REDs with mutation sites asserted, two behavioural (captured stdout must not prescribe bare rerun on red, nor dispatch on running). This closes the six-unit queue from the campaign freeze.
---
<!-- COMMENTS:END -->
