---
id: STATBUS-574
title: >-
  Name each database copy for what it is: backups are the daily dumps, upgrade
  snapshots are the rollback copies
status: In Progress
assignee: []
created_date: '2026-11-06T10:36:00Z'
updated_date: '2026-11-06T10:57:00Z'
labels: []
dependencies: []
priority: medium
ordinal: 493204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner decision 2026-11-05: 'backup' means the daily pg_dump the upgrade service takes (~/statbus/dbdumps, BACKUP_ENABLED, BACKUP_INTERVAL), the portable copy an operator restores and keeps through an uninstall. 'Upgrade snapshot' means the raw data-folder copy the upgrader takes before each upgrade so it can roll back; it only fits the installation it came from. Today the snapshot folder is ~/statbus-backups and its CLI is ./sb db backup, so the names are the wrong way round. The snapshot's absolute path is recorded in the upgrade marker (BackupPath) and in public.upgrade.backup_path, and recovery matches on it (recoveryAttemptPredicate), so the folder move must carry those records with it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The upgrade snapshot folder is ~/statbus-upgrade-snapshots and its commands are ./sb db snapshot create/restore/list/purge; docs, ./sb monitor help and the uninstall plan use the word snapshot for it
- [ ] #2 On an existing box the install moves ~/statbus-backups to ~/statbus-upgrade-snapshots once, only when no upgrade is in progress, and rewrites recorded snapshot paths in public.upgrade.backup_path in the same step; no second name remains
- [ ] #3 An upgrade that fails after the move rolls back from the moved snapshot (real VM upgrade test)
- [ ] #4 ./sb db backup names the daily database backup (dump); the old ./sb db backup snapshot subcommands are not kept as aliases
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-06: in rc.13. Plan: (1) one name constant ~/statbus-upgrade-snapshots; (2) migration moves ~/statbus-backups once, only with no upgrade marker present, refuses if both hold data; (3) a recorded old-root path (marker BackupPath, public.upgrade.backup_path) resolves to the new root, and the upgrader rewrites the rows at start; (4) ./sb db backup -> ./sb db snapshot, no alias; (5) harness and tests follow; rollback proof = rc.13 gate upgrade arcs.
<!-- SECTION:NOTES:END -->
