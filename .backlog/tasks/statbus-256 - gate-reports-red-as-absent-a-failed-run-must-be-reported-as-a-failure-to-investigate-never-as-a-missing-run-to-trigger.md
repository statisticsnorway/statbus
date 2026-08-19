---
id: STATBUS-256
title: >-
  gate-reports-red-as-absent: a failed run must be reported as a failure to
  investigate, never as a missing run to trigger
status: To Do
assignee: []
created_date: '2026-08-19 12:35'
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
