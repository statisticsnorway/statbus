---
id: STATBUS-390
title: Every install-time database operation uses a route whose readiness is verified
status: In Progress
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

## Progress 2026-09-24 (proof pending)

Migration subprocess *host mode*, migration and seed pgx locks, installer post-completion connection, and upgrade daemon share `dbroute.FromFile` for CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT. No-Docker tests cover command builders, the seed-lock DSN and source-level caller wiring, but do not prove a real seed restore or daemon reconciliation. This is not Done: no `5-install-database-route-interrupted.sh` has been authored or run. A VM experiment must preserve Caddy's Layer4 database listener while interrupting only its web entry point. Acceptance criteria remain unchecked pending observed end-to-end proof.

**Deliberate socket exception, not a second host endpoint:** `cli/cmd/seed.go:301-319` runs the *actual* installer seed restore as `docker compose exec -T db pg_restore`, independently of `migrate.PgRestoreCommand`; `cli/internal/dbroles/dbroles.go:1-18,273-281` uses the same trusted local socket to repair stale role passwords when TCP authentication fails. `cli/cmd/install.go:2044-2059` likewise uses local Unix-socket `local all postgres trust` authentication (still occupying a PostgreSQL slot, with superuser access to reserved slots) for orphan cleanup when the external connection pool is exhausted. `cli/internal/migrate/migrate.go:101-109,114-139,194-196` selects that socket when host `psql` is absent or `DOCKER_PSQL=1`; its host mode resolves CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT. Forcing these rescue operations through the Caddy TCP route would remove their recovery property. Thus there is **not** one physical route for every operation, despite the shared resolver for TCP clients. `cli/cmd/install_services.go:497-519` explicitly verifies the upgrade daemon's own TCP route before service startup; container DB health alone (`:523-544`) does not verify TCP reachability. Unit test `TestDockerDatabaseCommandsUseLocalSocket` pins this distinction without Docker. The web/DB separation and full install timeline still require VM proof.

<!-- SECTION:DESCRIPTION:BEGIN -->
Install-time seed restore, state checks, migrations, locks, final readiness, and automatic-update startup use the database service's internal socket or Docker-network route. Host-route use is removed from these installer-owned operations, so their readiness does not depend on the web entry point.

## Evidence, 2026-09-24

The connection study shows seed and some repair work can use the database service directly, while migrations, locks, post-completion checks, and the automatic update service currently use the loopback route (`/Users/jhf/ssb/statbus/tmp/setup-connection-map.md:79-92`). Current post-completion code calls `migrate.AdminConnStr` (`cli/cmd/install.go:2888-2899` at master `7a9cf707e`) and migration subprocesses use the configured host route (`cli/internal/migrate/migrate.go:211-263` at master `7a9cf707e`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No-Docker builder/source-level tests pin seed, state, migration, lock, and final-readiness wiring; actual install operations require VM proof.
- [ ] #2 `TestRecoveryDSNUsesInternalRoute` checks DSN reload and source-level assertions pin the pre-start probe; actual daemon reconciliation still requires VM proof.
- [ ] #3 `new: test/install-recovery/scenarios/5-install-database-route-interrupted.sh` stops the web entry point between seed and migrations and observes seed, migration, lock, final readiness, and automatic-update startup all succeed through the internal route.
<!-- AC:END -->
