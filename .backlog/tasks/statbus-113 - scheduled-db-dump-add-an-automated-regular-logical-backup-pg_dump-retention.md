---
id: STATBUS-113
title: >-
  scheduled-db-dump: add an automated regular logical backup (pg_dump) +
  retention
status: To Do
assignee: []
created_date: '2026-06-29 09:44'
updated_date: '2026-06-29 11:55'
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
King wants regular logical backups running in the background (2026-06-29). VERIFIED (mechanic + foreman; tmp/mechanic-backup-restore.md): NOTHING schedules `pg_dump` today — the two nightly OnCalendar timers are apt OS-updates (red herring), the only *.timer is upgrade-liveness, scheduled GH workflows are image/docker/log maintenance, and doc/CLOUD.md:548's crontab line is an unimplemented recommendation. Every dump caller is manual CLI / dev / test. So there is NO automated logical backup — a real data-safety gap for a production registry, and it blocks removing the forensics tar (STATBUS-112): today the only DB copies are the transient per-upgrade rsync snapshot (overwritten each run) + ad-hoc manual dumps.

## What (final design — King-ratified 2026-06-29)
The upgrade service (already an always-on USER daemon, ops/statbus-upgrade.service) OWNS the regular logical backup via a small IN-PROCESS periodic runner. No separate systemd timer, cron, or IPC; nothing extra to install (the service is already installed). Runs as user `statbus`, on standalone installs (the SSB cloud is de-scoped — SSB-managed).
- Daily (configurable): `./sb db dump` (pg_dump -Fc → dbdumps/) then `./sb db dumps purge N`.
- Coordination with upgrades is IN-PROCESS (one service sequences a backup vs its own upgrade) + a flock check so it also defers to an install-CLI-driven upgrade. Dumps are atomic, so any rare preemption is harmless.
- Catch-up: on startup, if the last dump is older than the interval, run now.
Full step-by-step in the Implementation Plan.

## Config (.env.config)
- `BACKUP_ENABLED` (default true on standalone; lets the cloud / an operator with their own backups opt out)
- `BACKUP_INTERVAL` (default 24h)
- `BACKUP_RETENTION_COUNT` (default 7 → `db dumps purge 7`)

## Tradeoff (accepted, standalone)
Backups pause if the SERVICE is down — mitigated by manual `./sb db dump`, the service being the hardened always-on core (the recovery model this session), and ≤1-backup loss at a daily cadence.

## Open (King / ops)
Do infra-level backups (e.g. Hetzner snapshots) exist OUTSIDE the repo for the cloud? Standalone has none → this IS the backup. Off-box copy (disk-loss safety) = future enhancement; v1 is local retention. Blocks STATBUS-112 (forensics-tar removal) until this lands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The upgrade service runs the regular backup on a schedule via a small IN-PROCESS periodic runner — no separate systemd timer, cron entry, or external scheduler; nothing extra to install (the service is already installed)
- [ ] #2 Each run executes `./sb db dump` (pg_dump -Fc) then `./sb db dumps purge N`; retention keeps a bounded set, old dumps removed; dumps are ATOMIC (tmp→rename) so a failed/preempted dump leaves no partial file
- [ ] #3 Coordination: the service sequences its own backup vs its own upgrade in-process (never concurrent); the backup ALSO checks the upgrade-in-progress flock (IsFlockHeld) to defer to an install-CLI-driven upgrade — it SKIPS if any upgrade is in flight; a run missed during downtime catches up on startup if overdue
- [ ] #4 Verified on a standalone box: backups run unattended on cadence, are SKIPPED during an upgrade (service- AND install-driven), catch up after downtime, and purge enforces N; a backup failure never crashes the service
- [ ] #5 doc/DEPLOYMENT.md documents the built-in standalone backup (cadence, retention, where dumps land, how to restore/tune/disable); the doc/CLOUD.md crontab recommendation is reconciled / removed
<!-- AC:END -->



## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Implementation plan (architect, 2026-06-29) — get it right; survey before building

### 0. SURVEY FIRST (don't duplicate; reverse half-done bits)
- The service main loop: how `Service.Run` (cli/internal/upgrade/service.go) is structured — where a periodic task hooks in (an existing select/poll loop vs a new goroutine).
- The dump/purge code: `./sb db dump` (cli/cmd/db.go:261) + `db dumps purge` — is the core callable in-process? Is the dump ATOMIC (tmp→rename) and non-interactive (headless-safe)?
- Any partial backup-scheduling (the doc/CLOUD.md:548 crontab note is prose-only; confirm nothing half-built elsewhere). Reuse solid parts; remove conflicting WIP.

### 1. Reuse the dump/purge core
- PREFER extracting the dump + purge logic into in-process functions the service calls directly (cleaner than re-exec). Shelling to `./sb db dump` is an acceptable fallback.
- ENSURE the dump is ATOMIC: write to `*.tmp` → rename on success, so a failed/preempted dump never leaves a partial/corrupt file. (Load-bearing for coordination — see §3.)

### 2. In-process periodic runner (in the service)
- Cadence from `BACKUP_INTERVAL` (default 24h).
- "Last backup time" = newest file in dbdumps/ — the artifacts ARE the state; no new persistence needed. Due when newest > interval old (or none exist).
- On service start AND each tick: if due and not skipped (§3), run dump → purge. The startup check IS the missed-run catch-up (covers downtime).
- Mechanism: a dedicated goroutine with a timer, or folded into the main select loop — build's choice. A tiny home-grown runner is enough; a small lib (robfig/cron) only if cron-expression config is later wanted.

### 3. Coordination — a backup must NEVER collide with an upgrade
- Upgrades come from TWO sources, both holding the upgrade flock: the service itself (executeScheduled) and `./sb install` inline (separate process).
- Backup BEFORE running: check `IsFlockHeld` (cli/internal/install/state.go:172) on tmp/upgrade-in-progress.json → if held (any upgrade, either source) → SKIP this run, log it, next tick catches up. (flock check works intra-process too — a 2nd fd's LOCK_NB fails when the same process holds it.)
- Service-internal: the service must not start its OWN upgrade while its backup goroutine runs, and vice versa — guard with an in-process mutex; upgrade has priority.
- Reverse edge (install starts an upgrade mid-backup): handled by dump ATOMICITY (the partial tmp is discarded; backup retries next tick). Optional hardening ONLY if the edge proves real in arcs: a dedicated db-busy lock both upgrade + backup respect. Do NOT add it pre-emptively (keep it simple).

### 4. Config (cli/internal/config + .env.config)
- `BACKUP_ENABLED` (default true on standalone), `BACKUP_INTERVAL` (24h), `BACKUP_RETENTION_COUNT` (7). Surface via `./sb config show`. Cloud can set BACKUP_ENABLED=false (de-scoped).

### 5. Observability + failure handling
- Log each attempt via the service's existing journald: started / completed (size + duration) / skipped (upgrade in flight) / failed (error).
- Notify via the existing Slack/callback on REPEATED failures (not every success).
- A backup failure must NEVER crash the service (catch + log + retry next tick). Optional: a disk-space pre-check → skip + warn if low.

### 6. Docs
- doc/DEPLOYMENT.md: document the built-in standalone backup — cadence, retention, where dumps land, how to restore one, how to tune/disable.
- doc/CLOUD.md: remove/reconcile the stale crontab recommendation (:548).
- doc/upgrade-vocabulary.md: `db-dump` already added.

### 7. Verify (arc-tested — STATBUS-071; the run is the only oracle)
- Backup runs on cadence unattended; SKIPS during an upgrade (service- AND install-driven); catches up after downtime; purge keeps N; atomic on failure; a backup failure does not crash the service. Prove the upgrade-coordination on a real VM, not by reasoning.
<!-- SECTION:PLAN:END -->

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

RECOMMENDATION FLIPPED → ONE SERVICE IN CHARGE (King-driven, 2026-06-29). King pushed for radical simplicity; on reflection the hybrid's extra machinery (a separate user systemd timer + cross-process flock coordination) is unnecessary.

SIMPLEST design: the upgrade service (already an always-on user daemon) owns the backup via a small IN-PROCESS periodic runner. Coordination becomes trivial AND stronger — the same process that runs upgrades sequences backup-vs-upgrade in-process (never concurrent), so NO flock dance. Catch-up = run-if-overdue on startup. Logging = the service's existing journald. Install plumbing = NONE (the service is already installed; no new timer/cron unit).

Even 'cron signals the service' is more parts than needed — IPC for no gain, and a service-down still blocks the work — so an in-process timer beats cron+signal.

TRADEOFF (accepted for standalone): backups pause if the SERVICE is down — mitigated by manual `./sb db dump`, the service being the always-on core we're hardening (the recovery model this session), and ≤1-backup loss at a daily cadence.

Scheduler: a tiny home-grown periodic runner suffices ('daily' needs no cron-expression generality); a small lib (robfig/cron) only if config flexibility is wanted — build-detail, King to pick.

This SUPERSEDES the user-systemd-timer mechanism + the flock-coordination AC above.
<!-- SECTION:NOTES:END -->
