---
id: STATBUS-390
title: >-
  A database check that passes during install means the next database step can
  connect too
status: Done
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-10-21 14:02'
labels:
  - release-bug
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A database check that passes during install means the next database step can connect too, and when the route is down the operator is told which service provides it.

### Zoom out
The installer reaches the database in two ways, for two reasons:
- **The route:** every normal client (migrations, locks, the final connection, the upgrade daemon) connects over TCP to the address the web entry point publishes for the database. They share one definition of that address, so one passing check speaks for all of them.
- **Recovery exceptions:** a few operations go straight into the database container over its local socket on purpose, so they still work when the published route is broken. These are seed restore, repairing role passwords, and clearing leftover connections when the pool is exhausted. They are named exceptions, not a second route.

The failure to prevent is a check that passes through one route while the next step uses another and fails late. Making everything use the internal route instead would hide a broken published route that the upgrade daemon and operators still depend on.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** seed restored through the container (`docker compose exec`), then Migrations failed: `dial tcp 127.0.0.1:5431: connect: connection refused`. The database was healthy; the web entry point publishing 5431 was not (`tmp/finland-transcript-actual.txt:119-147`).
- **Shipped (v2026.09.3, merged 2026-09-25):** `54e999bac` gives all TCP clients one resolver, `dbroute.FromFile` (`CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT`). `d7b50aaa8` documents the socket exceptions (`cli/cmd/seed.go`, `cli/internal/dbroles/dbroles.go`, orphan cleanup in `cli/cmd/install.go`, `DOCKER_PSQL` mode in `cli/internal/migrate/migrate.go`). Step 8 checks the published ports (`reconcilePublishedPorts`) and the daemon's own route (`checkUpgradeDatabaseRoute`) before starting it. Merge `00704540c`.
- **Operator outcome:** STATBUS-388 (Done) names the unavailable route and its providing service. Its scenario `5-install-database-route-interrupted.sh` cuts the published route before migrations, observes a bounded failure naming the web entry point, then a rerun through seed, migrations and readiness: PASS in rc.17 LXD `36506437069`.
- **Branch:** `fix/db-transport-390` is fully merged.

### Closing review
- **Memory:** none needed.
- **Documentation:** the exceptions are documented at their definitions (`d7b50aaa8`); no separate doc.
- **Cleanup:** the merged local branch `fix/db-transport-390` was deleted 2026-10-15 (tip `a100dd261`, on master).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every installer and daemon TCP client resolves the same `CADDY_DB_BIND_ADDRESS:CADDY_DB_PORT` route and ignores `SITE_DOMAIN` and ambient `PGHOST`/`PGPORT` (`TestInstallerDatabaseOperationsUseInternalRoute`, `TestResolveIgnoresSiteDomainAndRequiresInternalEndpoint`, `TestRecoveryDSNUsesInternalRoute`)
- [x] #2 The recovery operations that must survive a broken route use the database local socket (`TestDockerDatabaseCommandsUseLocalSocket`)
- [x] #3 On a real box with the published database route cut before migrations, the installer fails bounded naming the web entry point, and a rerun completes seed, migrations and readiness (`5-install-database-route-interrupted.sh`, rc.17 LXD `36506437069`, owned by STATBUS-388)
- [x] #4 [Owner] Confirm the two-way design (one shared published route plus the named socket exceptions) as the target and record it in Implementation Notes. Confirmed: check this and set Done. Rejected: add the internal-route design as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green in Go Test `36503468493`; re-run green locally on master, 2026-10-15.
- **Naming:** in the test names, "internal route" means the published `CADDY_DB_BIND_ADDRESS` address as opposed to the public `SITE_DOMAIN`, not the container socket.
- **Superseded criterion:** the 2026-09-24 restyle had asked for every step to succeed with the published route down. That reverses the design above and was dropped; the original goal (`67735dd8f`) is what this ticket states.

### Owner 2026-10-21: confirmed, Done
One shared published route plus the three named socket exceptions is the design. Built, tested, and proven on a real box (rc.17 LXD).
<!-- SECTION:NOTES:END -->
