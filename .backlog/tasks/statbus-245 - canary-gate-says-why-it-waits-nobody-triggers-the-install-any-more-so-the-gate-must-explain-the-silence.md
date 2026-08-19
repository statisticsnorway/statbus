---
id: STATBUS-245
title: >-
  canary-gate-says-why-it-waits: nobody triggers the install any more, so the
  gate must explain the silence
status: To Do
assignee: []
created_date: '2026-08-19 07:11'
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
When the canary boxes install release candidates on their own, nobody pushes a button any more — which means that when the promotion gate says "not yet", the person reading it has nothing to correlate against. They cannot tell whether the box has not noticed the candidate yet, is installing it right now, or has failed and will never get there. All three look identical: no completed row.

WHAT GOES WRONG: the gate probes each canary for a completed upgrade at the candidate's commit and reports absence. Under the old flow the human had just pushed the deploy branch, so absence obviously meant "wait a moment". Under the automatic flow, absence carries no timing information at all, and the natural response to an unexplained "not yet" is to re-run it a few times and then start looking for something broken — usually in the wrong place.

THE DETAIL: this gap is created BY the improvement. It is not a defect in the automatic flow; it is what happens when a human trigger is removed and the diagnostics still assume one. The box knows the answer — it has a channel, a check interval, a last-check time, and a row for the candidate in some state, or none. The gate is reading only the last of those and reporting the absence rather than the situation.

THE FIX: when the completed row is absent, say which of the three it is. Has the box discovered the candidate at all — is there a row, and in what state? When did it last check, and how often does it? Then the refusal reads as "dev has not checked since 06:40 and checks every 30 minutes" or "dev is installing it now, started 06:52" or "dev tried and the row is parked", each of which points somewhere different. The information is one query further than the gate already goes.

WHY THAT HELPS: the operator learns whether to wait, watch, or investigate — from the gate itself, at the moment of refusal, instead of by opening an SSH session and reconstructing it. A gate that refuses without explaining teaches people to re-run it and hope, which is the habit that turns a five-minute wait into a lost morning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When a canary has no completed row, the gate distinguishes not-yet-discovered, in-progress, and failed/parked, naming which
- [ ] #2 The refusal reports the box's check interval and last check time so 'wait' has a duration attached
- [ ] #3 A parked or failed candidate row is called out as needing action rather than time
- [ ] #4 The gate still refuses in every case where it refuses today — this adds explanation, never permission
<!-- AC:END -->
