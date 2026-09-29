---
id: STATBUS-427
title: >-
  Database container stops cleanly: SIGINT fast shutdown and a longer grace
  period
status: To Do
assignee: []
created_date: '2026-09-28 21:42'
updated_date: '2026-09-29 08:05'
labels:
  - upgrade
  - db
dependencies: []
priority: high
ordinal: 376200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing rc.16's c-rollback-resurrection (tmp/rollback-db-recreate.md, follow-up 1). The db compose service sets no stop_signal and no stop_grace_period. SIGTERM is PostgreSQL's smart shutdown, which waits for all sessions; Compose SIGKILLs after 10 s, so any compose stop/recreate with live app/rest/worker/daemon sessions ends in exit 137 and crash recovery on next start. Observed at rollback's pre-restore stop (harmless there: volume overwritten) and at the daemon-boot recreate (harmful). Operator stops and config-driven recreates hit it too. Use stop_signal: SIGINT (fast shutdown: disconnects sessions, clean checkpoint) and a stop_grace_period long enough for a checkpoint on a busy box.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 db service stops with SIGINT and a documented grace period
- [ ] #2 A compose stop with live sessions ends with a clean shutdown (no crash recovery on next start), proven on an LXD fork
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): Not addressed in v2026.09.3.
<!-- SECTION:NOTES:END -->
