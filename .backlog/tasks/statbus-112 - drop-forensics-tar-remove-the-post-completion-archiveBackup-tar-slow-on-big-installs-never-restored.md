---
id: STATBUS-112
title: >-
  drop-forensics-tar: remove the post-completion archiveBackup tar (slow on big
  installs, never restored)
status: Done
assignee: []
created_date: '2026-06-29 09:40'
updated_date: '2026-07-03 10:46'
labels:
  - upgrade
  - backup
  - performance
dependencies: []
references:
  - tmp/mechanic-backup-restore.md
  - cli/internal/upgrade/exec.go
  - cli/internal/upgrade/service.go
  - doc/upgrade-vocabulary.md
  - STATBUS-071
priority: medium
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why
King decision (2026-06-29): remove `archiveBackup` — the post-completion `*.tar.gz` forensic archive. It runs after EVERY completed upgrade (`tar -czf`, up to a 60-min timeout), slows upgrades immensely on big installations, and is never read by the restore path. Confirmed forensics-only (exec.go:1036: "the archive is forensics, not the rollback artifact"). The actual rollback artifact is the offline rsync snapshot (`pre-upgrade-active/`), not this tar.

## Grounded (file:line; tmp/mechanic-backup-restore.md)
- `archiveBackup` (exec.go:1023) — `tar -czf ~/statbus-backups/<version>-pre.tar.gz.tmp -C ~/statbus-backups pre-upgrade-active`, atomic .tmp→rename, 60-min timeout.
- Called at service.go:4932 — AFTER state='completed' (:4853) AND removeUpgradeFlag (:4906). Off the upgrade/rollback critical path, but consumes up to an hour of time + IO on the box at the tail of every big-DB upgrade.
- restore (exec.go:763) reads the rsync'd DIRECTORY (`pre-upgrade-active/`), never the tar.

## What
- Remove `archiveBackup` (exec.go:1023) and its call site (service.go:4932).
- Grep-confirm nothing else reads the `*.tar.gz` (the restore path uses the rsync dir only).

## Conscious tradeoff (UN-GATED by King 2026-06-29)
The tar's only value was a retained, per-version, exact-pre-upgrade copy — but it is forensics-only (never restored; no rollback value), and the big-DB upgrade stall it causes is a real, recurring cost. So removal is UN-GATED — it does NOT wait on the scheduled backup (STATBUS-113). ACCEPTED: a short retention gap until STATBUS-113 lands (there are no scheduled backups today anyway; `pre-upgrade-active/` is overwritten each upgrade). STATBUS-113 closes the gap properly with real logical backups.

## Verify
Arc-test (STATBUS-071) that upgrade + rollback are unaffected (the tar was never the rollback artifact); confirm big-install post-completion upgrade time drops.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `archiveBackup` (exec.go:1023) and its call site (service.go:4932) are removed; grep confirms no code reads the `*.tar.gz`
- [ ] #2 Upgrade + rollback are unaffected (arc-proven — the tar was never on the rollback path); post-completion upgrade time drops measurably on a large install
- [ ] #3 Removal is INDEPENDENT of STATBUS-113 (un-gated, King 2026-06-29); the short retention gap until scheduled backups land is accepted — the tar is forensics-only (no rollback value); STATBUS-113 closes the gap
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
N-WATCHDOG ARC RULING (architect, 2026-06-29): RETIRE (option A). Removing archiveBackup removes its stall site (`archive-backup-stall-active-phase-watchdog`, exec.go:1061) — so retire the postswap-archivebackup-watchdog scenario + arc + inject-class + the §4a FIX-A guard + TestArchiveBackupAfterTerminalUpdate IN THE SAME pass (else the post-push arc false-greens). Rationale: archiveBackup was the ONLY long op in the forward post-terminal tail → the real risk is gone; (B) re-point to a quick step-11/12 = a synthetic stall testing a can't-happen scenario on a paid VM. The active-phase watchdog MECHANISM stays, guarded by migrate-up's ticker (migration phase) + the sibling restore-db-stall (rollback restore). Re-add a forward-tail watchdog test IF a real long post-terminal op is ever introduced. King NOT looped: internal arc-harness (STATBUS-071) call, delegated to architect; recorded for transparency.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-03 10:46
---
CLOSED — already shipped in code; verify-and-close per the King-ratified consolidation (Cluster 6). Evidence (operator-verified 2026-07-03): zero archiveBackup code references remain in cli/internal/upgrade/ (grep clean). Doc/diagram residue is tracked in STATBUS-115 (docs sweep cluster).
---
<!-- COMMENTS:END -->
