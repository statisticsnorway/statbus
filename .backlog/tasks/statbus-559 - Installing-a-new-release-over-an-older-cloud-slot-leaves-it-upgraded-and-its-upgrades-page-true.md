---
id: STATBUS-559
title: >-
  Installing a new release over an older cloud slot leaves it upgraded and its
  upgrades page true
status: In Progress
assignee: []
created_date: '2026-11-02T15:12:00Z'
updated_date: '2026-11-02T15:12:00Z'
labels:
  - bug
dependencies: []
priority: high
type: bug
ordinal: 482204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: ./cloud.sh install <slot> <stable> over any older slot completes the upgrade, and the admin upgrades page afterwards shows only the truth: no obsolete parked attempts, no false warnings.

Found 2026-11-02 installing v2026.11.0 on niue cloud slots ug and ma (logs tmp/cloud-install-ug.log, tmp/cloud-install-ma.log).

1. ug (schema v2026.09.0, last migration 20260901212308): ./sb install stopped in state detection: 'query reattemptable restore: column rollback_finish_pending_at does not exist' (added by migration 20260907120000, first in v2026.09.1). The pre-migration state probe (cli/internal/install/state.go QueryReattemptableRestore) assumes the current schema. mw and ua have the same schema and would fail the same way. The message says 'nothing was changed' but install.sh had already swapped sb and checked out v2026.11.0. The gate never installs a candidate over a v2026.09.0 database.
2. ma: the v2026.10.5 row stays parked after v2026.11.0 installed successfully. Installer success bookkeeping (cli/cmd/install.go, STATBUS-452) retires unparked interrupted attempts only. Owner decision 2026-11-02: a successful install supersedes parked attempts for older releases too, keeping the park reason and error as history.
3. ma: the page warns 'The upgrader is installed but not running' while it runs. Install stamps unit_floor_state at 14:21:12 before the deferred service start at install exit, and the service restamps only on its 6-hour poll tick.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Install state detection works on every schema the installer accepts: on a database without rollback_finish_pending_at it proceeds (no rollback can be pending there). A test runs the probe against a schema lacking the column, red before the fix and green after
- [ ] #2 A gate scenario installs the candidate with install.sh --version over a real v2026.09.0 box and the install completes; red against v2026.11.0, green with the fix
- [ ] #3 When ./sb install stops after install.sh swapped the program and checked out the target, the message says what was changed instead of 'nothing was changed'
- [ ] #4 A successful install supersedes parked in_progress attempts for other commits; the row keeps its error and park reason and the state log records the transition. The 452 live install test covers it, red before and green after
- [ ] #5 The upgrade service stamps unit_floor_state when it starts, so a page read right after a successful install shows no 'not running' warning. Covered by a test
- [ ] #6 ug, mw and ua reach the stable release with ./cloud.sh install, ug's statbus-maintenance belongs to statbus_ug afterwards, and ma's v2026.10.5 row shows superseded
<!-- AC:END -->
