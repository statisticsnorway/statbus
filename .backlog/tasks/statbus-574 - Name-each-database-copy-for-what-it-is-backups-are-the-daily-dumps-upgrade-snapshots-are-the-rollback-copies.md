---
id: STATBUS-574
title: >-
  Name each database copy for what it is: backups are the daily dumps, upgrade
  snapshots are the rollback copies
status: In Progress
assignee: []
created_date: '2026-11-06T10:36:00Z'
updated_date: '2026-11-06T12:09:00Z'
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
- [x] #1 The upgrade snapshot folder is ~/statbus-upgrade-snapshots and its commands are ./sb db snapshot create/restore/list/purge; docs, ./sb monitor help and the uninstall plan use the word snapshot for it
- [x] #2 On an existing box the install moves ~/statbus-backups to ~/statbus-upgrade-snapshots once, only when no upgrade is in progress, and rewrites recorded snapshot paths in public.upgrade.backup_path in the same step; no second name remains
- [ ] #3 An upgrade that fails after the move rolls back from the moved snapshot (real VM upgrade test)
- [x] #4 ./sb db backup names the daily database backup (dump); the old ./sb db backup snapshot subcommands are not kept as aliases
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-06: in rc.13. Plan: (1) one name constant ~/statbus-upgrade-snapshots; (2) migration moves ~/statbus-backups once, only with no upgrade marker present, refuses if both hold data; (3) a recorded old-root path (marker BackupPath, public.upgrade.backup_path) resolves to the new root, and the upgrader rewrites the rows at start; (4) ./sb db backup -> ./sb db snapshot, no alias; (5) harness and tests follow; rollback proof = rc.13 gate upgrade arcs.

4fdbbcfbb. Folder: upgrade.SnapshotRootName=statbus-upgrade-snapshots (one constant; install Directories, disk policy, ownership heal, db snapshot, upgrader backupRoot). Move: MigrateSnapshotRoot renames ~/statbus-backups (or merges entry by entry, never overwriting; a namesake stays behind and is named), only while SnapshotRootMoveAllowed (marker records no upgrade). Runs in the install Directories step and in the upgrader at boot after recovery and on each idle tick; the upgrader rewrites public.upgrade.backup_path rows recorded under the old folder (exact-value UPDATE). restoreDatabase, restoreOperatorConfig and reconcile resolve a path recorded before the move to the moved snapshot. CLI: ./sb db backup create|list|purge (the daily pg_dump, was db dump/db dumps), ./sb db snapshot create|list|purge|restore (was db backup), no aliases. Uninstall removes both folders. Docs, monitor help, hook and harness follow (historical-release baselines keep the old name). Red then green: tmp/574-{upgrade,cmd,uninstall,terminal}-{red,green}.log; live DB row rewrite tmp/574-livedb.log; full go test ./... exit 0 (tmp/574-go-all.log); hook test 57/57. AC3 = rc.13 gate: 0-happy-upgrade now asserts the move and the rewritten rows on a real upgrade, and the rollback arcs restore from ~/statbus-upgrade-snapshots.
<!-- SECTION:NOTES:END -->
