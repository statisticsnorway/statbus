---
id: STATBUS-586
title: >-
  Upgrader keeps its lock when it reconnects while its previous session is still
  exiting
status: Done
assignee: []
created_date: '2026-11-06T20:18:00Z'
updated_date: '2026-11-06T21:44:00Z'
labels:
  - upgrade
dependencies: []
priority: high
ordinal: 498204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rc.17 gate: Upgrade Arc Harness 42276884758, arc postswap-migration-ceiling. The rollback restored the snapshot and served, then 'Reconnecting to the restored database ... failed: re-acquire lock after reconnect: another upgrader is already running (advisory lock held)' left the row failed-rollback-incomplete. Cause: Service.reconnect closed queryConn and immediately ran pg_try_advisory_lock on a new session, while the daemon's own previous backend (still exiting) held the session lock. Timing dependent: passed on rc.16 and in 28 earlier runs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Reconnect while the daemon's previous session still holds the lock succeeds and the new session holds the lock (livedb test: busy old session)
- [x] #2 A lock held by any other session is still refused as another upgrader
- [x] #3 postswap-migration-ceiling passes in the next RC gate
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Red (tmp/rc17-reconnect-red.log): TestReconnectKeepsTheDaemonLock (livedb) fails 'reconnect while the old session is still busy: re-acquire lock after reconnect: another upgrader is already running'. Fix: reconnect keeps the previous queryConn PID; reacquireAdvisoryLock ends that backend and retries within 15 s when it is the holder, and refuses any other holder as before. Green (tmp/rc17-reconnect-green.log). go test ./internal/upgrade ok; livedb suite: only TestCaptureContainerLogs_PathComputation fails, identically at f8971e2c8 (pre-existing: unit-test docker guard refuses real docker), unrelated.

Also fixed in 1-line follow-up (next commit after 360b1a253): the livedb suite's only other failure, TestCaptureContainerLogs_PathComputation, failed identically at f8971e2c8: captureContainerLogs skipped the per-service file when the docker command could not be constructed, contrary to its comment ('one file per service'). It now writes the '# capture failed' placeholder there too (tmp/capture-livedb-green.log).

rc.18 gate GREEN: Release Fleet Orchestrator 42290374739 for v2026.11.1-rc.18 (360b1a253); Upgrade Arc Harness 42292586368 incl. postswap-migration-ceiling success; LXD Fork Fleet 42292492037. AC2 by code review: reacquireAdvisoryLock returns the original refusal when the holder PID differs from the daemon's previous session (case holder != previousPID), and when previousPID is 0 (first connect path uses acquireAdvisoryLock unchanged).
<!-- SECTION:NOTES:END -->
