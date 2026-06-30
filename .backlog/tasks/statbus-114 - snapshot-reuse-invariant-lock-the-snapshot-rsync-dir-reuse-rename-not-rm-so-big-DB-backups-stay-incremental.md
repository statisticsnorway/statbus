---
id: STATBUS-114
title: >-
  snapshot-reuse-invariant: lock the snapshot-rsync dir-reuse (rename, not rm)
  so big-DB backups stay incremental
status: Done
assignee: []
created_date: '2026-06-29 13:14'
updated_date: '2026-06-30 20:50'
labels:
  - upgrade
  - backup
  - performance
dependencies: []
references:
  - cli/internal/upgrade/exec.go
  - STATBUS-112
  - tmp/mechanic-backup-restore.md
priority: low
ordinal: 114000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why
The upgrade snapshot rsync (`db-snapshot-backup`) is incremental-fast on big DBs ONLY because `prepareBackupSnapshotDir` (exec.go:401-441) readies the base via an `active → syncing` RENAME (content + mtime preserved), then `rsync -a --delete` (exec.go:563) into it, then `syncing → active` commit (exec.go:623). Local rsync uses `--whole-file` (block-diff off), so the speedup = SKIP UNCHANGED FILES by size+mtime — which works only because the rename preserves mtimes. VERIFIED correct today (rsync double-check, 2026-06-29; the documented "CHANGE 2" design).

FRAGILITY (the reason for this ticket): nothing guards the invariant. If a future refactor ever swapped the rename for `rm`+`mkdir`, EVERY big-DB backup would silently full-copy — minutes → hours on large installs — with no test or comment to catch it.

## What
- Add a one-line INVARIANT comment at `prepareBackupSnapshotDir`: the `active → syncing` RENAME (NOT rm+mkdir) is load-bearing — it preserves content+mtime so rsync stays incremental; wipe-and-recreate would full-copy every run.
- If practical, add a reuse test that fails if the dir is wiped/recreated instead of renamed (e.g., assert the prior snapshot's content/inode carries into `syncing`).

## Verify
The guard (comment + test) makes the rename-not-rm requirement explicit; the test (if added) goes red if a refactor breaks it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `prepareBackupSnapshotDir` carries an invariant comment explaining the rename-not-rm requirement (content+mtime preservation → incremental rsync; rm+mkdir would full-copy big DBs every run)
- [x] #2 If practical, a test asserts the snapshot dir is REUSED across runs (the rename path) and fails if it becomes wipe-and-recreate
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed + committed 6bc3772d2 (cli/internal/upgrade/exec.go + persistent_rsync_test.go). Foreman verified both ACs first-hand:

AC#1: prepareBackupSnapshotDir carries an INVARIANT comment (STATBUS-114): the active→syncing transition MUST stay a RENAME — never rm+mkdir — because the rename preserves content+mtime so the subsequent local `rsync -a --delete` (defaults to --whole-file) stays incremental by skipping unchanged files; wipe-and-recreate would full-copy every run (minutes→hours on big installs).
AC#2: TestPrepareSnapshot_ReusesBaseInodeNotRecopy asserts the snapshot dir is REUSED across runs (inode+mtime carry into syncing), failing if a refactor swaps the rename for wipe-and-recreate.

Locks the incremental-backup invariant against silent regression.
<!-- SECTION:FINAL_SUMMARY:END -->
