---
id: STATBUS-410
title: Running the installer completes or waits for an earlier restart
status: In Progress
assignee: []
created_date: '2026-09-24 15:47'
updated_date: '2026-09-25 12:20'
labels:
  - release-bug
  - install
  - restart
  - recovery
dependencies:
  - STATBUS-407
priority: high
type: bug
ordinal: 363000
---

## Release gate observation 2026-09-25

**In Progress.** rc.02 (`2198185bb`) failed `5-install-live-upgrade-wait` ([run 36104217764, job 107973801494](https://github.com/statisticsnorway/statbus/actions/runs/36104217764/job/107973801494)): the fixture's flock forked, so its child retained the lock instead of releasing it for the subsequent install retry. `1f84f55d4` (merge `51503fbbe`) changes the holder to `flock -F`, keeping the lock in the recorded process (`test/install-recovery/scenarios/5-install-live-upgrade-wait.sh:31`). This addresses the scenario's live-holder and recovery boundary for AC #2, but is not a successful VM observation. AC #1-4 remain open pending the rc.03 gate, including the absent start-limit scenario (#3).

## Status 2026-09-24

**In Progress.** `3fa3d744d`, `474cf6119`: `cli/cmd/service_restart.go`, `cli/internal/upgrade/restart_test.go` and authored `5-install-interrupted-restart.sh`, `5-install-live-upgrade-wait.sh` cover ownership and intent (#1-2 proof pending on VM; #4 partly). #3 start-limit scenario is absent. **Remaining:** run interrupted/live scenarios and prove cause-first repair before reset followed by ready service.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When an earlier restart is no longer running, the installer restores the saved service set, confirms readiness, clears the saved restart state, and continues. When the restart is still running, the installer asks the operator to wait. Recovery from a start-rate limit occurs after the underlying password or route cause is corrected.

## Evidence, 2026-09-24

Finland retained a saved restart after restart failure and later refused installer recovery (`/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:69-75`). Current restart refusal and saved intent are at `cli/internal/upgrade/restart.go:19-87` at master `7a9cf707e`. The local replay recovered from the start-rate limit only after the password cause was corrected (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:964-980,1017-1018`).
## rc.03 evidence, 2026-09-25

rc.03 run 36116753412 job 108013586646 (5-install-live-upgrade-wait): rerun refused `a restart is still running, or its services could not be restored`. Review established the marker writer (PID 16498) was the installer's own stale-restart recovery and the refusal came from an invalid fixture that requested a daemon restart for an app-only restart with no unit, not a product bug; scenario fixed in `faf0905be`, merged in `a3526f832` (rc.05). VM proof pending.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/install-recovery/scenarios/5-install-interrupted-restart.sh` terminates a restart after saving intent, then observes the installer restore exactly that service set, confirm readiness, clear saved state, and complete.
- [ ] #2 `new: test/install-recovery/scenarios/5-install-live-upgrade-wait.sh` keeps the earlier operation active and observes a plain wait message with no competing recovery.
- [ ] #3 `new: test/install-recovery/scenarios/5-install-start-limit-recovery.sh` first proves reset alone cannot recover while the password or route cause remains, then fixes the cause, clears failed state, and observes a ready service.
- [ ] #4 `new: cli/internal/upgrade/restart_test.go::TestInterruptedAndLiveRestartClassification` deterministically covers both ownership states and saved-intent preservation.
<!-- AC:END -->
