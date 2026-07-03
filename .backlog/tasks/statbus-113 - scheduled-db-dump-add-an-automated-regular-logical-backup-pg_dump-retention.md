---
id: STATBUS-113
title: >-
  scheduled-db-dump: add an automated regular logical backup (pg_dump) +
  retention
status: Done
assignee: []
created_date: '2026-06-29 09:44'
updated_date: '2026-07-03 10:46'
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
- [ ] #2 Each run calls `dbdump.DumpDatabase` then `dbdump.PurgeDumps(N)` IN-PROCESS (not a subprocess); dumps are ATOMIC (tmp→rename) so a failed/preempted dump leaves no partial file; retention keeps N
- [ ] #3 Coordination: the service sequences its own backup vs its own upgrade in-process (never concurrent); the backup ALSO checks the upgrade-in-progress flock (IsFlockHeld) to defer to an install-CLI-driven upgrade — it SKIPS if any upgrade is in flight; a run missed during downtime catches up on startup if overdue
- [ ] #4 Verified on a standalone box: backups run unattended on cadence, are SKIPPED during an upgrade (service- AND install-driven), catch up after downtime, and purge enforces N; a backup failure never crashes the service
- [ ] #5 doc/DEPLOYMENT.md documents the built-in standalone backup (cadence, retention, where dumps land, how to restore/tune/disable); the doc/CLOUD.md crontab recommendation is reconciled / removed
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Implementation plan — FINAL (survey-grounded 2026-06-29; tmp/mechanic-backup-survey.md). No open choices.

### Survey result: CLEAN SLATE
Grep-confirmed zero existing BACKUP_* / backupTicker / dailyBackup. The 6h-ticker `reconcileBackupDir`/`pruneBackups` are rsync UPGRADE-SNAPSHOT ops, NOT pg_dump — leave them alone. Nothing to reverse.

### 1. Extract two callable, hardened cores (cli/cmd/db.go → reusable funcs)
- `dumpDatabase(projDir, dbName, slotCode) (path, err)` — extract from dbDumpCmd.RunE (db.go:233). Make it ATOMIC: write to `<dbdumps>/<slot>_<ts>.pg_dump.tmp` → rename to `.pg_dump` on success; remove the .tmp on any error. Command unchanged: `docker compose exec -T db pg_dump -Fc --no-owner --exclude-table-data=auth.secrets -U postgres <db>` (already headless). The cobra cmd now calls this func.
- `purgeDumps(projDir, keepN) error` — extract the purge core from dumpsPurgeCmd.RunE (db.go:404) WITHOUT confirmAction (db.go:480). Keep newest N per source-prefix (lexicographic = chronological). The cobra cmd keeps its own confirm + calls this func.

### 2. Config — 3 settings mirroring UPGRADE_CHECK_INTERVAL's 4 touch points
Add BACKUP_ENABLED (bool, default true), BACKUP_INTERVAL (duration, default 24h), BACKUP_RETENTION_COUNT (int, default 7) at the SAME points UPGRADE_CHECK_INTERVAL uses: (1) default config.go:388; (2) generateEnvContent config.go:728; (3) *Service struct field service.go:130; (4) loadConfig() service.go:2620. Surface via `./sb config show`. (Do NOT use UPGRADE_CALLBACK's at-call-time dotenv.Load pattern.)

### 3. Periodic runner — one select-case + a GOROUTINE (service.go Run loop, :1770)
- Add `backupTicker := time.NewTicker(d.backupInterval)` alongside the existing tickers; add a case in the `for { select {} }`, slotted between the discovery ticker.C block (~:1816) and notifyCh (:1818):
  `case <-backupTicker.C: go d.maybeRunBackup(ctx)`
- GOROUTINE, not synchronous: a large-DB pg_dump can exceed the 120s watchdog; a synchronous handler would block heartbeatTicker.C (:1776) and get the service killed. (The mechanic's hook LOCATION is right; this refines it to async for heartbeat-safety.)
- `maybeRunBackup(ctx)`:
  1. if BACKUP_ENABLED == false → return.
  2. SKIP + log "backup skipped: upgrade in progress" if `d.upgrading` (service's own upgrade) OR `IsFlockHeld(d.projDir)` (install-CLI-driven upgrade; IsFlockHeld is in-package, service.go:725 — call directly, no import).
  3. concurrency guard: `d.backupMu.TryLock()` — if already running, return; hold for the duration.
  4. DUE check: run only if the newest file in `<projDir>/dbdumps/` is older than BACKUP_INTERVAL (the artifacts ARE the state — no new persistence; none present = due).
  5. `dumpDatabase(...)` → on success `purgeDumps(..., BACKUP_RETENTION_COUNT)`.
- CATCH-UP: run the same due-check once at service start (boot) so a run missed during downtime fires immediately.
- An upgrade STARTING mid-backup is harmless: the dump is atomic, so a DB-stop aborts it with no artifact; next tick retries. NO upgrade-side wait logic (one-way deference + atomicity).

### 4. Logging + notify (reuse the upgrade's existing channels)
- Log each outcome via fmt.Printf → journald (as the service does, e.g. :4915): started / completed (path, size, duration) / skipped (upgrade in progress) / failed (error).
- On FAILURE, call the existing `runCallback` (:5241, the Slack/callback used for upgrades — reuse UPGRADE_CALLBACK); notify on failure only, not success. No new BACKUP_CALLBACK.
- A backup failure NEVER crashes the service: maybeRunBackup recover()s + logs + returns; next tick retries.

### 5. Docs
- doc/DEPLOYMENT.md: document the built-in backup — cadence (BACKUP_INTERVAL), retention (BACKUP_RETENTION_COUNT), dumps in dbdumps/, restore via `./sb db restore <file>`, disable via BACKUP_ENABLED=false.
- doc/CLOUD.md:548: remove the stale "add to root crontab" recommendation (now built-in).
- doc/upgrade-vocabulary.md: `db-dump` already added.

### 6. Verify (arc-tested — STATBUS-071; the run is the only oracle)
Backup fires on cadence unattended; SKIPS during an upgrade (both `d.upgrading` AND an install-CLI flock); catches up on boot after downtime; purge keeps N; dump is atomic (kill mid-dump → only a .tmp, discarded); a DB-stop mid-dump leaves no artifact + next tick retries; a backup failure does not crash the service; the 30s heartbeat keeps firing during a long dump (no watchdog kill).
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

SURVEY DONE + PLAN FINALIZED (2026-06-29; tmp/mechanic-backup-survey.md, foreman-verified Q1/Q2/Q7). The Implementation Plan above is now DEFINITIVE — every prior 'prefer/or/if' resolved to a decision with file:line. Key resolutions: CLEAN SLATE (no WIP to reverse); hook = one select-case in Service.Run (:1770) running the backup in a GOROUTINE (heartbeat-safety — a sync handler could exceed the 120s watchdog); extract+harden two cores (dumpDatabase → atomic .tmp→rename; purgeDumps → headless, drop confirmAction); config mirrors UPGRADE_CHECK_INTERVAL's 4 points; coordination = d.upgrading || IsFlockHeld(d.projDir) (in-package, service.go:725); log via fmt.Printf/journald + reuse runCallback on failure. Ready for build on the King's GO.

DESIGN CALL — dump/purge core HOME = a NEW neutral package `internal/dbdump` (architect, 2026-06-29; engineer-flagged, foreman-verified). IMPORT-CYCLE: `cmd` imports `internal/upgrade` (10 files); `upgrade` imports `cmd` in ZERO — so the cores CANNOT stay in `cmd` (the service calling them would cycle). CORRECTS plan §1 ('extract from cmd/db.go → reusable funcs'): instead, land them in **`internal/dbdump`**, exported `DumpDatabase`/`PurgeDumps`, imported by BOTH cmd (cobra cmds) and upgrade (the service) — no cycle. Chosen over (A) cores-in-`upgrade`: a logical pg_dump is a GENERAL DB op (callers = manual/dev/test, not upgrade), so B keeps it composable/separable (King's principle) vs baking a generic op into the upgrade package. (C) shell-out OUT (contradicts in-process, loses typed errors). Physical snapshot ops backupDatabase/restoreDatabase STAY in `upgrade` (upgrade-specific). Helpers loadDbName/dumpTimestamp/ensureDumpsDir move to dbdump; humanSize stays in cmd (9 callers). FIXES the AC#2-vs-step-3 contradiction — it's IN-PROCESS (`dbdump.DumpDatabase`), NOT shell-out. King NOT looped: internal layering, principle-resolved, his diagram-focus protected; recorded here for transparency.

HELPER CORRECTION (architect, 2026-06-29) — REVERSES the earlier 'helpers move to dbdump'. The helpers loadDbName/dumpTimestamp/ensureDumpsDir have 5 callers OUTSIDE dump/purge (restore db.go:605/837, download :323/328, seed.go:208) that the survey didn't flag. So DUPLICATE, don't move: dbdump gets its own unexported copies; cmd keeps its own. A literal move would force restore/download/seed to import `dbdump` just to read a db name — the same mislocation smell we avoided for the cores; tiny env-readers, duplication is cheap + matches the repo's existing loadDbName/loadSeedDbName near-dup (db.go:114/129).

ALSO blessed (foreman-reviewed, go build + full go test green): (a) the due-check is intentionally TOLERANT (newest >= 0.9*interval), not strict — a strict >=interval vs a ticker firing every interval skips every other tick on jitter and halves the cadence; (b) `DumpsToPurge` (pure selector for cmd's preview) is split from `PurgeDumps` (headless delete for the service). 113 ready to commit; 112 next.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-03 10:46
---
CLOSED — already built; verify-and-close per the King-ratified consolidation (Cluster 6). Evidence (operator-verified 2026-07-03): scheduled logical backup is live — backupTicker (service.go:1832) + maybeRunBackup + catch-up, BACKUP_ENABLED/INTERVAL/RETENTION config fields, and the cli/internal/dbdump/ package (dbdump.go + tests). The task body's 'ready for build' text was stale — the build happened; this close is the bookkeeping catching up.
---
<!-- COMMENTS:END -->
