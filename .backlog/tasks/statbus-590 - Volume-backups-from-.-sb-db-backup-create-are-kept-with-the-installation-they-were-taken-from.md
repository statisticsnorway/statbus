---
id: STATBUS-590
title: >-
  Snapshot archives from ./sb db snapshot create are kept with the installation
  they were taken from
status: In Progress
assignee: []
created_date: '2026-11-06T18:30:00Z'
updated_date: '2026-11-06T19:24:00Z'
labels:
  - cli
  - backup
dependencies: []
type: enhancement
ordinal: 494204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A volume snapshot belongs to the installation it was taken from, so a restore can only bring back that installation's own data, and the archive stays inside the project.

### Zoom out
Files an installation writes for itself live under that installation, named so another installation cannot mistake them for its own. The logical backups already do this (`<project>/dbdumps/<slot>_<timestamp>.pg_dump`).

### Zoom in
Since STATBUS-574, `./sb db snapshot create` (cli/cmd/db.go) wrote `~/statbus-upgrade-snapshots/snapshot-<timestamp>.tar.gz`, staging through `~/statbus-upgrade-snapshots/staging`. Before 574 the same command was `./sb db backup create`, writing `~/statbus-backups/backup-<timestamp>.tar.gz`. `restore`, `list` and `purge` read the same folder:

- The archive name holds neither slot nor instance. Two checkouts on one box share the folder, and `restore` accepted any archive in it, including another installation's.
- Found on the owner's Mac: two stray archives in `~/statbus-backups` (490 MB), removed 2026-11-06 at the owner's request.
- Out of scope: the upgrader's own pre-upgrade snapshot (`~/statbus-upgrade-snapshots/pre-upgrade-active`, cli/internal/upgrade/exec.go), the installer Directories step, and the monitor and uninstall readers.

Filed by hibiscus against the pre-574 names; rewritten against the snapshot command by rabbit with the owner's approval (2026-11-06).

### Closing review
- **Memory:** none expected.
- **Documentation:** `./sb db snapshot --help`, doc/DEPLOYMENT.md, doc/upgrades.md.
- **Cleanup:** none expected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ./sb db snapshot create writes its archive to <project>/dbdumps/<slot>_<timestamp>.snapshot.tar.gz and stages under <project>/dbdumps, beside the backups
- [ ] #2 With archives of two slots in one dbdumps folder, ./sb db snapshot list, restore and purge act only on the current slot's archives; restore names the other slot when refusing (Go test)
- [ ] #3 With a temporary HOME and project directory, create, list, restore and purge resolve only under <project>/dbdumps; the temporary HOME stays empty (Go test)
- [ ] #4 doc/DEPLOYMENT.md, doc/upgrades.md and ./sb db snapshot --help name <project>/dbdumps as the place of snapshot archives; dbdumps/*.snapshot.tar.gz and dbdumps/staging/ are git-ignored
<!-- AC:END -->
