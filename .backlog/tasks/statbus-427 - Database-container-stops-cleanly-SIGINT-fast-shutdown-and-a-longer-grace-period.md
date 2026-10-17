---
id: STATBUS-427
title: >-
  Database container stops cleanly: SIGINT fast shutdown and a longer grace
  period
status: In Progress
assignee: []
created_date: '2026-09-28 21:42'
updated_date: '2026-10-17 18:35'
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
- [x] #1 db service stops with SIGINT and a documented grace period
- [ ] #2 A compose stop with live sessions ends with a clean shutdown (no crash recovery on next start), proven on an LXD fork
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): Not addressed in v2026.09.3.

### Fix (91dfe3922, 2026-10-17)
- postgres/docker-compose.yml db: `stop_signal: SIGINT`, `stop_grace_period: 120s`, with the reason in a comment. postgres is PID 1 (start-postgres.sh execs docker-entrypoint.sh, which execs postgres), so the signal reaches it.
- **Measured locally, with live sessions (4 client backends plus a pg_sleep(120) session):**
  - **Before:** `docker compose stop db` logged 'received smart shutdown request' and was killed, exit 137. The next start logged 'database system was not properly shut down; automatic recovery in progress' and 'redo starts'.
  - **After:** 'received fast shutdown request', then 'database system is shut down' in 0.09 s. The stop took 1 s, exit 0. The next start logged 'database system was shut down at ...', with no recovery.
- **AC2** (on an LXD fork): the rc ladder for v2026.10.3-rc.01 exercises compose stops in its upgrade and rollback scenarios. Recorded there.

### rc.01 ladder (2026-10-17 18:35)
- Release, Smoke, Hardening, Fast Tests, the dev deploy and the LXD fault fleet (39052318518) pass at v2026.10.3-rc.01, which contains 91dfe3922.
- The upgrade arcs (39052368235) did not run their arcs on attempt 1. One fixture branch's Images run (39052458994) failed on the arm64 sb build, because GitHub's runner timed out reaching ghcr.io ('Client.Timeout exceeded while awaiting headers') and action downloads timed out. The wait step then reported the images missing after 40 min. That is a GitHub network failure on the runner, not the candidate. Attempt 2 started 18:35 at the same tag. AC2 is read from the arcs that stop and restart the database.
<!-- SECTION:NOTES:END -->
