---
id: STATBUS-113
title: >-
  scheduled-db-dump: add an automated regular logical backup (pg_dump) +
  retention
status: To Do
assignee: []
created_date: '2026-06-29 09:44'
updated_date: '2026-06-29 10:14'
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
- [ ] #1 On a STANDALONE install, `./sb install` AUTOMATICALLY installs a USER systemd timer + service in ~/.config/systemd/user/ (owned by `statbus`, sibling of statbus-upgrade.service) — runs as the user, fires unattended (linger already enabled), no manual step
- [ ] #2 The scheduled job runs `./sb db dump` then `./sb db dumps purge N`; retention keeps a bounded set and old dumps are removed
- [ ] #3 Verified on a standalone box: the timer fires UNATTENDED (no login required), a dump lands in dbdumps/, purge enforces N
- [ ] #4 doc/DEPLOYMENT.md documents the built-in standalone backup; the doc/CLOUD.md crontab recommendation is reconciled with what's implemented
- [ ] #5 The scheduled `./sb db dump` is UPGRADE-AWARE: it checks the upgrade-in-progress flock (IsFlockHeld, install/state.go) and SKIPS/defers if an upgrade is mid-flight (no collision with migrations / DB-stop / rollback); the skipped run is logged and the next scheduled run catches up
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SCOPE REFINEMENT (King, 2026-06-29) — SUPERSEDES the per-slot multi-tenant framing above. TARGET = STANDALONE installs (external customers); the SSB cloud is de-scoped (SSB-managed / infra-handled — King: 'it doesn't matter if our cloud box does it or doesn't'). The feature is BUILT INTO the standalone install and runs AS THE LOCAL USER (dumps owned by that user). On standalone there is no other backup, so this scheduled dump IS the backup → data-safety-critical for every external customer.

MECHANISM (open, King): 
- LEAN: a SYSTEM systemd timer with `User=<localuser>` — runs as the user, no `enable-linger` needed (system units fire unattended), journald logging + `Persistent=` missed-run catch-up, consistent with the existing upgrade units.
- FALLBACK: a USER crontab — simplest, runs as the user, no linger, universal; weaker logging, no catch-up.
- DISFAVORED: a *user* systemd timer (`systemctl --user`) — needs `enable-linger` (a root step) to run without an active login.
Settle crontab-vs-systemd by how the standalone install already sets up its systemd units + whether setup runs as root (grounding in flight).

MECHANISM SETTLED (grounded 2026-06-29; tmp/operator-standalone-systemd.md, foreman-verified). The standalone box runs everything as USER-level systemd as user `statbus`, with `enable-linger` ALREADY set (setup-ubuntu-lts-24.sh:1091) — the upgrade service itself is a USER unit (ops/statbus-upgrade.service: WantedBy=default.target, ~/.config/systemd/user/, `systemctl --user`, WorkingDirectory=%h/statbus). 

So the backup = a USER `.timer` + `.service` pair in ~/.config/systemd/user/, owned by `statbus`, installed by `./sb install` (same path as statbus-upgrade), managed via `systemctl --user`. Linger already enabled → fires without login. 

This SUPERSEDES the open crontab-vs-systemd question: NOT a system timer with `User=` (the box uses user units), NOT a crontab — a user timer is the consistent, lowest-friction fit. (The earlier 'user systemd needs enable-linger' caveat is moot: linger is already on.) Install code lives at cli/cmd/install.go.

THIRD OPTION CONSIDERED (King, 2026-06-29) + SYNTHESIS. King raised: have OUR service run the backup, for control over how it interacts with upgrades. The real requirement this surfaces: the backup must not COLLIDE with an upgrade (a pg_dump firing mid-migration / during the DB-stop).

Option C — in-service scheduler (the upgrade daemon owns backup scheduling):
- PROS: knows the upgrade state → can sequence/skip cleanly; one place for all scheduled DB work; unified status/observability (same logs/Slack); scheduler-agnostic.
- CONS: COUPLES backup reliability to the service being up — if the service is crashed/stopped/wedged (exactly when you most want a backup), backups stop too (a safety net should be MORE reliable than what it protects); reinvents scheduling + missed-run catch-up that systemd gives free; broadens the upgrade service's responsibility.

SYNTHESIS (recommended) — get C's coordination WITHOUT C's coupling: keep the INDEPENDENT user systemd timer for SCHEDULING, put the COORDINATION in the existing upgrade lock. `./sb db dump` checks the upgrade-in-progress flock (IsFlockHeld, install/state.go:172); if an upgrade holds it → SKIP this run (the upgrade takes its own snapshot, nothing lost; next run catches up). Two-way safe via the shared lock. The backup keeps running even when the service is down.

DECISION (rec, pending King): HYBRID — independent user timer + upgrade-aware dump (flock check). NOT in-service scheduling (coupling cost). Open: King may still prefer scheduling inside the service for unified control.
<!-- SECTION:NOTES:END -->
