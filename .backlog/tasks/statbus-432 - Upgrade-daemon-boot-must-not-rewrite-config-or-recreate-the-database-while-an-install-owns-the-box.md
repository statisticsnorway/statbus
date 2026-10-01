---
id: STATBUS-432
title: >-
  Upgrade daemon boot must not rewrite config or recreate the database while an
  install owns the box
status: To Do
assignee: []
created_date: '2026-09-29 13:29'
labels:
  - upgrade
  - install
dependencies: []
priority: high
ordinal: 381200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the Ville replay D4 (tmp/ville-replay-v2026.09.3.md, STATBUS-430) and confirmed by review tmp/review-430.md section 3. Service.Run() Pre-flight A (config generate, service.go:2982) and Pre-flight B (EnsureDBUp -> docker compose up -d db, service.go:3062 / exec.go:1366) run on every unit (re)start and take no mutex. After install.sh has swapped the binary and checked out the target, a restarting unit (e.g. a 09.2 unit in a Restart=always loop after a failed step 17) regenerates .env with the target COMMIT_SHORT and recreates PostgreSQL. ./sb install then sees 'FATAL: the database system is shutting down' during detection or later steps. Crash recovery already avoids this hazard with the non-recreating EnsureDBReachable (exec.go:1358-1365).
<!-- SECTION:DESCRIPTION:END -->

Owner note 2026-10-01 13:17 UTC: prefer logical/unit tests over full installation sequences wherever the mechanism can be pinned without a guest; AC#5 (Go unit tests) is the primary coverage and AC#4's LXD repro yields wherever the unit tests genuinely take over. Implementer argues the coverage boundary in this ticket.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When tmp/upgrade-in-progress.json is install-held and its flock is held, daemon boot performs neither config generate nor any docker compose up; it logs one line naming the holder and waits (watchdog-pinged, bounded) or exits with a code that does not consume StartLimitBurst
- [ ] #2 Outside a service-held forward recovery (flag.IsServiceNewSbRecovery()), boot's DB bring-up never recreates the db container (start only); post_swap recovery keeps today's recreate because it needs the target image
- [ ] #3 The detection window is closed: ./sb install holds the install mutex across detectInstallState (Detect tolerates its own holder), or criterion 2 alone is shown to make detection safe; the choice is argued in the ticket
- [ ] #4 LXD reproduction of the replay's shape (failed Settings after the binary swap, unit restart-looping, operator fixes config and reruns): the db container ID and StartedAt stay unchanged from detection through step 16; before the fix the same arc reproduces 'the database system is shutting down' or a db recreate
- [ ] #5 Go unit tests: boot with an install-held live flock does not call config-generate/compose; a non-recovery boot uses the non-recreating bring-up; a post_swap recovery boot still recreates
<!-- AC:END -->

## Implementation Notes

### 2026-10-01

- `Service.Run` now classifies the canonical flag and live flock before recovery checkout, config generation, or database bring-up. A live install holder is named once in the journal. Boot then waits for at most 30 seconds, pings the watchdog during the wait, and exits 75 if the install still owns the flock. This leaves 90 seconds of the unit's 120-second `TimeoutStartSec` for normal startup, and a unit test parses the shipped unit to require at least 60 seconds of remaining budget. The systemd unit lists 75 in `RestartPreventExitStatus`, so this outcome does not consume `StartLimitBurst`.
- Database boot strategy is now explicit: only `flag.IsServiceNewSbRecovery()` uses `EnsureDBUp` and its target-image `docker compose up -d db`; ordinary and pre-swap boots use `StartDatabaseRouteServingMayRun`, which starts the existing db and proxy containers without recreation.
- AC#3 uses criterion 2 rather than widening the install mutex across `detectInstallState`. Before install acquires its flag there is no owner for daemon boot to observe, but the only overlapping ordinary boot operation is now start-only. It cannot replace the db container or change its image/identity, so the detection window no longer contains the destructive operation that produced `the database system is shutting down`. Once install acquires the flock, AC#1 blocks config generation and every container action altogether.
- AC#5 is the primary coverage. Focused Go tests use real live install flocks to pin bounded expiry, watchdog notification, exactly one holder-identifying log, release-to-continue, and stale-flag continuation. Additional tests pin expiry-to-exit-75 wiring, `RestartPreventExitStatus=75`, the wait-versus-`TimeoutStartSec` startup margin, source ordering before config/database actions, and start-only versus recreation strategy selection.
- AC#4's LXD reproduction was not added. The defect mechanism is completely at the Go dispatch boundary: canonical flock classification/order and the mutually exclusive start-versus-recreate callback. The unit tests observe those decisions directly and deterministically. A guest arc would retest Docker/systemd behavior already represented by the selected commands, at substantially higher cost, without covering an additional decision or race boundary.
