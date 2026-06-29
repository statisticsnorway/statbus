---
id: STATBUS-112
title: >-
  drop-forensics-tar: remove the post-completion archiveBackup tar (slow on big
  installs, never restored)
status: To Do
assignee: []
created_date: '2026-06-29 09:40'
updated_date: '2026-06-29 09:45'
labels:
  - upgrade
  - backup
  - performance
dependencies:
  - STATBUS-113
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
King decision (2026-06-29): remove `archiveBackup` — the post-completion `*.tar.gz` forensic archive. It runs after EVERY completed upgrade (`tar -czf`, up to a 60-min timeout), slows upgrades immensely on big installations, and is **never read** by the restore path. Confirmed forensics-only (exec.go:1036: "the archive is forensics, not the rollback artifact"). The actual rollback artifact is the offline rsync snapshot (`pre-upgrade-active/`), not this tar.

## Grounded (file:line; tmp/mechanic-backup-restore.md)
- `archiveBackup` (exec.go:1023) — `tar -czf ~/statbus-backups/<version>-pre.tar.gz.tmp -C ~/statbus-backups pre-upgrade-active`, atomic .tmp→rename, 60-min timeout.
- Called at service.go:4932 — AFTER state='completed' (:4853) AND removeUpgradeFlag (:4906). Off the upgrade/rollback critical path, but consumes time + IO on the box.
- restore (exec.go:763) reads the rsync'd DIRECTORY (`pre-upgrade-active/`), never the tar.

## What
- Remove `archiveBackup` (exec.go:1023) and its call site (service.go:4932).
- Grep-confirm nothing else reads the `*.tar.gz` (the restore path uses the rsync dir only).

## Conscious tradeoff + DEPENDENCY
The tar's ONLY value was a retained, per-version, exact-pre-upgrade copy (history). `pre-upgrade-active/` is overwritten each upgrade (rsync --delete), so after removing the tar, retained history depends ENTIRELY on the regular scheduled logical backups (pg_dump). **Do not remove the tar until regular scheduled backups are confirmed to run** (see the scheduled-backup check) — otherwise we silently remove all retained pre-upgrade history. If no schedule exists, add it first.

## Verify
Arc-test (STATBUS-071) that upgrade + rollback are unaffected (the tar was never the rollback artifact); confirm big-install post-upgrade time drops.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `archiveBackup` (exec.go:1023) and its call site (service.go:4932) are removed; grep confirms no code reads the `*.tar.gz`
- [ ] #2 Upgrade + rollback are unaffected (arc-proven — the tar was never on the rollback path); post-completion upgrade time drops on a large install
- [ ] #3 Retention is preserved: regular scheduled logical backups (pg_dump) are confirmed to run BEFORE this removal lands — removing the per-version tar must not leave a retention gap (pre-upgrade-active/ is overwritten each upgrade)
<!-- AC:END -->
