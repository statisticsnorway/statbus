---
id: STATBUS-246
title: >-
  supersede-cancels-and-reaps: a newer candidate must stop the old one's
  spending, not just its bookkeeping
status: To Do
assignee: []
created_date: '2026-08-19 07:14'
updated_date: '2026-08-19 07:16'
labels:
  - release
  - ci
  - infra
dependencies: []
references:
  - .github/workflows/release-fleet-orchestrator.yaml
  - .github/workflows/upgrade-arc-harness.yaml
  - test/install-recovery/lib/vm-bootstrap.sh
priority: high
type: enhancement
ordinal: 239000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a new release candidate is cut, the previous one will never be promoted — so every machine still testing it is being rented for an answer nobody will read. Cutting a candidate should stop the previous candidate's testing, and stop it in the way that actually saves the money.

WHAT GOES WRONG WITH THE OBVIOUS FIX: the coordinating workflow could simply be told to cancel itself when a newer one starts. That saves the cheap resource and leaks the expensive one. The coordinator does not own the test machines — it dispatches separate runs which rent them. Cancelling the coordinator leaves those runs going, and cancelling those runs mid-flight skips the per-machine cleanup that returns them. **The naive version spends more, not less.**

THE DETAIL, and why the existing sweep does not cover it: each test run cleans up after itself when it finishes normally, and there is a global sweep for stragglers. But that sweep is deliberately AGE-GATED — it only reaps machines older than a threshold comfortably above a test's own timeout, so it can never mistake a live machine from a concurrent run for an orphan. Cancellation orphans machines that are YOUNG. The one safety property that makes the sweep safe is exactly what makes it useless here.

What rescues it is that the machines are named per run. A cancellation knows which run it cancelled, so it can reap that run's machines **by name**, immediately, with no age gate — because run-scoped naming already proves ownership. Age-gating exists to answer "is this mine?"; a run id answers it exactly.

THE FIX, in order, on a new candidate's tag:
1. Find the previous candidate's in-flight coordinating run.
2. Find its dispatched child runs — by querying each fleet workflow for in-flight runs at the PREVIOUS candidate's commit, the same commit-keyed query the release gates already use. This is more robust than parsing the coordinator's logs for the ids it correlated.
3. Cancel the children first, then the coordinator, so the coordinator does not react to its children dying.
4. Reap each cancelled run's machines by its run-scoped name prefix, immediately and without the age gate.

Step 4 is the one that matters. Steps 1-3 without it make the problem worse.

ACCEPTED COST, stated so it is chosen rather than discovered: cancelling unconditionally discards evidence already paid for when the previous chain was nearly finished. We take that deliberately — a simple, predictable rule ("a newer candidate stops the older one") is worth more than a heuristic that tries to salvage occasional near-complete runs, and the newer candidate's own chain re-proves the same fixes anyway.

WHY THAT HELPS: the cost of cutting frequently stops scaling with how often we cut. The King's loop — cut, observe, fix, cut — becomes affordable to run as fast as the fixes arrive, which is the whole point of having it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A new candidate's tag cancels the previous candidate's in-flight coordinating run AND its dispatched fleet runs
- [ ] #2 Every cancelled run's rented machines are reaped by run-scoped name immediately, without waiting for the age-gated sweep
- [ ] #3 The age-gated global sweep is unchanged — it still cannot mistake a live machine from a concurrent run for an orphan
- [ ] #4 Verified on a real supersession: no machine belonging to the cancelled chain survives it, checked against the provider rather than inferred from logs
- [ ] #5 Cancelling the previous chain never disturbs the new candidate's own chain
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 07:16
---
REAL-WORLD DATA POINT for this design (operator provider check, 2026-08-19 morning, after the manual rc.06 cancellation): NO orphans — but only by timing luck. Fleet 1 (test-install) had completed with normal teardown; fleet 2 (install-recovery, run 32226271716) was cancelled while still QUEUED, so it never provisioned a machine. The dangerous window — cancellation landing MID-FLIGHT with young VMs the age-gated sweep cannot touch — did not occur this time. That is precisely the window the run-scoped immediate reap (step 4, the heart of this entry) exists to close: the next manual or automatic supersede will not be guaranteed the same timing. Provider state at check: one production server (niue, unrelated) + one 2-minute-old recovery VM legitimately owned by rc.07's live run 32226442525.
---
<!-- COMMENTS:END -->
