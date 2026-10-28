---
id: STATBUS-427
title: >-
  Database container stops cleanly: SIGINT fast shutdown and a longer grace
  period
status: Done
assignee: []
created_date: 2026-09-28 21:42
updated_date: '2026-10-28T08:30:00Z'
labels:
  - upgrade
  - db
dependencies: []
priority: high
type: bug
ordinal: 376200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while fixing rc.16's c-rollback-resurrection (tmp/rollback-db-recreate.md, follow-up 1). The db compose service sets no stop_signal and no stop_grace_period. SIGTERM is PostgreSQL's smart shutdown, which waits for all sessions; Compose SIGKILLs after 10 s, so any compose stop/recreate with live app/rest/worker/daemon sessions ends in exit 137 and crash recovery on next start. Observed at rollback's pre-restore stop (harmless there: volume overwritten) and at the daemon-boot recreate (harmful). Operator stops and config-driven recreates hit it too. Use stop_signal: SIGINT (fast shutdown: disconnects sessions, clean checkpoint) and a stop_grace_period long enough for a checkpoint on a busy box.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 db service stops with SIGINT and a documented grace period
- [x] #2 A compose stop with live sessions ends with a clean shutdown (no crash recovery on next start), proven on an LXD fork
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

- **18:35 rerun was the wrong remedy:** a rerun of the arc child refuses, because its parent orchestrator (39051244218) is no longer in progress. The child's notice says to re-dispatch the orchestrator. Done 19:51: orchestrator 39064247283 (workflow_dispatch at v2026.10.3-rc.01). Its covered-subset step skips what is already proven at this commit (smoke, faults), so only the arcs run.

### Ladder green, and what dev shows (2026-10-17 21:08)
- Re-dispatched orchestrator 39064247283: success. LXD fault fleet 39064463087: success. Upgrade arcs 39064518381: 41 success, 1 skipped. `./sb release covered` reports arcs and smoke covered at e3359068d.
- **The arc logs do not carry the database server log,** so they can neither show nor refute clean shutdowns. AC2 needs a log that does.
- **dev, read-only:** the new db container (created 17:05:21 by the rc.01 upgrade) has StopSignal=SIGINT, StopTimeout=120. Its first start logged 'database system was interrupted ... not properly shut down; automatic recovery'. That is the stop of the **old** container, created under v2026.10.2 without these settings, so SIGTERM and then the kill. Expected for the one upgrade that introduces the setting; every box sees it once.
- **AC2 is observed at dev's next upgrade** (rc.02 or the stable that follows): its db log must show 'received fast shutdown request', 'database system is shut down', and a start with 'was shut down at' and no recovery.

### Status 2026-10-20
- The ladder is green. AC2 is observed at dev's next upgrade, which waits for the next candidate (blocked on sql_saga 1.2, STATBUS-519).

AC2 real dev-upgrade evidence at rc.03 (Deploy run 40607897050): statbus-dev-db has StopSignal=SIGINT and StopTimeout=120. After the live-service recreate, its new container started at 2026-10-28T00:18:44.601689712Z and logged 'database system was shut down at 2026-10-28 00:18:43 GMT' before ready, with no not-properly-shut-down or automatic-recovery line. Read-only logs: tmp/427-rc03-dev-db-shutdown.log and tmp/427-rc03-dev-retained-logs.log.

Additional literal AC2 LXD evidence from rc.03 fault-fleet run 40608110641: the no-public-DNS failure capture shows 'received fast shutdown request' at 00:32:22.577, 'database system is shut down' at 00:32:23.247, then a new start at 00:32:23.840 with 'database system was shut down at 00:32:23' and ready. The drifted-unit capture independently shows fast shutdown at 00:25:27.126, clean shutdown at 00:25:27.924, and the next fork start at 00:35:34.202 with 'database system was shut down at 00:25:27' and ready. Neither capture contains not-properly-shut-down, automatic-recovery or redo-start lines. These are LXD forks with live application services. Extract: tmp/427-lxd-next-start-audit.log.
<!-- SECTION:NOTES:END -->
