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
Running the one install command detects whether a recorded restart still owns its lock. When the lock is free, installation treats the record as an unfinished restart, restores the services according to the saved restart intent, clears the record after readiness is confirmed, and continues installation. When a restart process still owns the lock, the installer says in plain words that restart is in progress and asks the operator to wait.

## Evidence, 2026-09-24

Finland operator output at 17:46 showed that an earlier `./sb restart all` stopped services and then failed while starting the automatic update service because of the stale database password. The saved restart record remained. A later `./sb install` was refused with `a restart is running or did not finish` and directed the operator back to `./sb restart all`. `cli/internal/upgrade/restart.go:19-38` currently refuses whenever the restart record exists through `restartRefusal` and `CheckRestartBarrier`, before distinguishing a live lock holder from an unfinished restart.

## Proving scenario

Add an install-recovery harness case that starts `./sb restart all`, terminates it after services are down and the restart intent is saved, then runs `curl -fsSL https://statbus.org/install.sh | bash`. The installer acquires the free lock, restores the saved service set, confirms readiness, clears the restart record, continues, and exits successfully with every required service running. A companion live-lock case keeps restart running and observes the plain wait message.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The installer checks the restart lock when a restart record exists.
- [ ] #2 With a free lock, the installer restores the saved service set, confirms readiness, clears the restart record, and continues installation.
- [ ] #3 With a held lock, the installer states that restart is in progress and asks the operator to wait.
- [ ] #4 The interrupted-restart harness case completes through the one install command with every required service running.
<!-- AC:END -->
