---
id: STATBUS-113
title: >-
  scheduled-db-dump: add an automated regular logical backup (pg_dump) +
  retention
status: To Do
assignee: []
created_date: '2026-06-29 09:44'
labels:
  - backup
  - ops
  - data-safety
dependencies: []
references:
  - doc/CLOUD.md
  - ops/
  - cli/cmd/db.go
  - doc/upgrade-vocabulary.md
  - STATBUS-112
  - tmp/mechanic-backup-restore.md
priority: high
ordinal: 113000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why
King wants regular logical backups running in the background (2026-06-29). VERIFIED (mechanic + foreman; tmp/mechanic-backup-restore.md): NOTHING schedules `pg_dump` today.
- The two `OnCalendar` timers (ops/setup-ubuntu-lts-24.sh:672 @01:00, :680 @03:00) are `apt-daily` / `apt-daily-upgrade` overrides (OS unattended-upgrades), NOT DB backups — red herring, ruled out.
- The only `*.timer` is `statbus-upgrade-liveness@.timer` (liveness, not backup).
- Scheduled GH workflows are image/docker/log maintenance — none dump the DB.
- doc/CLOUD.md:548 "Add to root crontab" is a DOC RECOMMENDATION, never implemented.
- Every `pg_dump` / `./sb db dump` caller is manual CLI (cli/cmd/db.go:261/:335), seed gen (dev.sh), or the test harness.

So there is NO automated logical backup — a real data-safety gap for a production registry, and it blocks removing the forensics tar (STATBUS-112): today the only DB copies are the transient per-upgrade rsync snapshot (overwritten each run) + ad-hoc manual dumps.

## What (recommended design)
- A scheduled job: `./sb db dump` (pg_dump -Fc → dbdumps/) then `./sb db dumps purge N` (purge tooling already exists per AGENTS.md).
- Mechanism: a systemd TEMPLATE timer per deployment slot (mirroring `statbus-upgrade-liveness@.timer`) so it covers multi-tenant (niue, per-slot DBs) AND standalone (rune). Implements the doc/CLOUD.md:548 recommendation in code, not prose.
- Cadence: daily, off the 01:00/03:00 apt windows (propose 23:00). Tune per ops.
- Retention: keep N (propose 7) via `./sb db dumps purge`. Tune.
- Consider shipping dumps off-box (an on-box dump survives app failure but not disk loss) — flag for ops; local retention at minimum.

## Open question (King / ops)
Do infra-level backups (e.g. Hetzner volume snapshots) already exist OUTSIDE the repo? If yes, this logical schedule is defense-in-depth; if no, it's the ONLY automated backup (higher stakes). Not resolvable from the repo — needs the King/ops to confirm.

## Verify
On a deployed box: the timer fires, a dump lands in dbdumps/, purge enforces N. Deploy-tested (per-slot infra).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An automated schedule runs `./sb db dump` on a cadence on each deployment (multi-tenant per-slot + standalone) with no manual action
- [ ] #2 Retention/purge keeps a bounded set via `./sb db dumps purge N`; old dumps are removed
- [ ] #3 Verified on a deployed box: the timer fires, a dump lands in dbdumps/, purge enforces N
- [ ] #4 doc/CLOUD.md updated — the crontab recommendation replaced by the implemented mechanism
<!-- AC:END -->
