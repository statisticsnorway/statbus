---
id: STATBUS-136
title: >-
  abort-terminal-write: catastrophic rollback abort writes its terminal into a
  DB it just stopped
status: To Do
assignee: []
created_date: '2026-07-04 22:31'
labels:
  - upgrade
  - install-recovery
  - product
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
  - STATBUS-044
priority: medium
ordinal: 137000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND live in r17 (2026-07-05): the git-restore ABORT path ([ROLLBACK_FAILED_GIT_CORRUPT]) stopped services (incl. db) for the restore, then attempted the terminal row write against the stopped DB → connection EOF → INVARIANT ROLLBACK_TERMINAL_WRITE_FAILED, flag kept, process exit → guaranteed death + systemd restart on a path that had already concluded. The terminal write can never succeed in that ordering. Repeated ×3 in r17 (each pass re-ran the whole abort). FIX SHAPE (architect): on the abort path, bring the DB back up BEFORE the terminal write — StartDBForRecovery-style `docker compose start db` (the asymmetric-safe start-existing primitive, never up -d) + the existing bounded write retry. The restore never ran (that is what aborted), so the DB volume is untouched and starting the existing container is safe by the same argument as install crash-recovery's connect-first pattern (cli/cmd/install_upgrade.go:192-219). Evidence: r17 journal on the kept VM / tmp logs. Verification: unit-level ordering guard (db-start precedes terminal write on the abort path) + the future rollback-crash-loop scenario (STATBUS-134's natural oracle) asserts the terminal actually lands.
<!-- SECTION:DESCRIPTION:END -->
