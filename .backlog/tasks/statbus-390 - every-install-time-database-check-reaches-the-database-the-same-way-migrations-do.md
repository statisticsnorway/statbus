---
id: STATBUS-390
title: Every install-time database operation uses a route whose readiness is verified
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - release-bug
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Status 2026-09-24

**To Do.** #1-3 not met: the named transport tests and `5-install-database-route-interrupted.sh` are absent; `cli/cmd/install.go` and `cli/internal/migrate/migrate.go` still have distinct connection paths after `145c17292`. **Remaining:** route every seed/state/migration/lock/readiness and upgrade startup call through a verified internal transport, with unit and VM checks.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Install-time seed restore, state checks, migrations, locks, final readiness, and automatic-update startup use the database service's internal socket or Docker-network route. Host-route use is removed from these installer-owned operations, so their readiness does not depend on the web entry point.

## Evidence, 2026-09-24

The connection study shows seed and some repair work can use the database service directly, while migrations, locks, post-completion checks, and the automatic update service currently use the loopback route (`/Users/jhf/ssb/statbus/tmp/setup-connection-map.md:79-92`). Current post-completion code calls `migrate.AdminConnStr` (`cli/cmd/install.go:2888-2899` at master `7a9cf707e`) and migration subprocesses use the configured host route (`cli/internal/migrate/migrate.go:211-263` at master `7a9cf707e`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_database_transport_test.go::TestInstallerDatabaseOperationsUseInternalRoute` verifies seed, state, migration, lock, and final readiness use the selected internal route.
- [ ] #2 `new: cli/internal/upgrade/service_database_transport_test.go::TestInitialServiceReconciliationUsesInternalRoute` verifies automatic-update startup can reconcile through the same internal route before declaring ready.
- [ ] #3 `new: test/install-recovery/scenarios/5-install-database-route-interrupted.sh` stops the web entry point between seed and migrations and observes seed, migration, lock, final readiness, and automatic-update startup all succeed through the internal route.
<!-- AC:END -->
