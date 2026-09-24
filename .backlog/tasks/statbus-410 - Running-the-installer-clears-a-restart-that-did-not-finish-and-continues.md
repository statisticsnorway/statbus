---
id: STATBUS-410
title: Running the installer clears a restart that did not finish and continues
status: To Do
assignee: []
created_date: '2026-09-24 15:47'
labels:
  - install
  - restart
  - recovery
dependencies: []
references:
  - /Users/jhf/ssb/statbus/tmp/finland-answers-4.txt
priority: high
type: bug
ordinal: 363000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Running the one install command detects whether a recorded restart still owns its lock. When the lock is free, installation treats the record as an unfinished restart, clears any failed-state start limit for the automatic update service, restores the services according to the saved restart intent, clears the record after readiness is confirmed, and continues installation. When a restart process still owns the lock, the installer says in plain words that restart is in progress and asks the operator to wait.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

Finland operator output at 17:46 showed that an earlier `./sb restart all` stopped services and then failed while starting the automatic update service because of the stale database password. The saved restart record remained. A later `./sb install` was refused with `a restart is running or did not finish` and directed the operator back to `./sb restart all`. `cli/internal/upgrade/restart.go:19-38` currently refuses whenever the restart record exists through `restartRefusal` and `CheckRestartBarrier`, before distinguishing a live lock holder from an unfinished restart.

The local Multipass replay reproduced a second dead end after repeated failed restarts: the automatic update service reached its start-rate limit, every subsequent restart failed immediately, and the installer directed the operator back to the same restart command. Recovery succeeded only after clearing the unit's failed state, but none of the messages identified that recovery. The installer can make the documented one-command recovery converge by clearing this failed state before it starts the service. Source: `/Users/jhf/ssb/statbus/tmp/local-ville-replay.md`, lines 964-980 and 1017-1018.

## Proving scenario

Add an install-recovery harness case that starts `./sb restart all`, terminates it after services are down and the restart intent is saved, then runs `curl -fsSL https://statbus.org/install.sh | bash`. The installer acquires the free lock, restores the saved service set, confirms readiness, clears the restart record, continues, and exits successfully with every required service running. A companion live-lock case keeps restart running and observes the plain wait message.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The installer checks the restart lock when a restart record exists.
- [ ] #2 With a free lock, the installer restores the saved service set, confirms readiness, clears the restart record, and continues installation.
- [ ] #3 With a held lock, the installer states that restart is in progress and asks the operator to wait.
- [ ] #4 The interrupted-restart harness case completes through the one install command with every required service running.
- [ ] #5 Before restoring an unfinished restart, the installer clears the automatic update service's failed state so a previous start-rate limit cannot block recovery.
<!-- AC:END -->
