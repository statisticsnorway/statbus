---
id: STATBUS-431
title: >-
  The upgrade service can always write its maintenance flag:
  ~/statbus-maintenance is created by the install user on every install path
status: To Do
assignee: []
created_date: '2026-09-29 10:28'
updated_date: '2026-09-29 11:47'
labels:
  - install
dependencies: []
priority: medium
ordinal: 380200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by review tmp/review-425-m3a.md R3 (2026-09-29), first hit live on LXD arcs (un-park-to-completion could not write its park flag). cli/cmd/install.go runCreateConfig (install.go:1504, the Configuration step) is the only place that creates $HOME/statbus-maintenance (install.go:1601-1605), and it runs only when .env.config is absent (checkConfigDone, install.go:1172). Any install where .env.config already exists skips it: the unattended answer file (STATBUS_ENV_CONFIG imports .env.config), ops/create-new-statbus-installation.sh (touch .env.config, line 346), and a rerun after an interrupted install. Then caddy/docker-compose.yml:28 bind-mounts ${HOME}/statbus-maintenance and Docker creates it as root, so the upgrade daemon (running as statbus) cannot write the maintenance/park flag (cli/internal/upgrade/exec.go:428-439). Fix: create the directory (and statbus-backups) owned by the install user on every install path, before any container starts, and repair a root-owned one on existing boxes (same container mechanism as Backup ownership / STATBUS-429).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every install path (interactive, answer file, pre-seeded .env.config, rerun) leaves ~/statbus-maintenance owned by the install user before the first compose up
- [ ] #2 An existing box with a root-owned ~/statbus-maintenance is repaired by the installer without sudo
- [ ] #3 A test observes the upgrade service write and clear its maintenance flag on a box installed from an answer file
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Scope correction 2026-09-29 (coordinator): an answer-file install DOES create the directory: runCreateConfig reads STATBUS_ENV_CONFIG (install.go:1507) and the Configuration step runs because .env.config is absent. Only paths that pre-create .env.config before install skip it: the test harness (vm-bootstrap.sh copies /tmp/env-config to ~/statbus/.env.config) and ops/create-new-statbus-installation.sh (touch .env.config, line 346). Live boxes checked: dev statbus_dev 775, no statbus 755, demo statbus_demo 775, all owned by the service user. So no NSO box is affected today; the fix is still right (create the directories on every path, not only inside Configuration).
<!-- SECTION:NOTES:END -->
