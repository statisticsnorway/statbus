---
id: STATBUS-388
title: When a database step cannot connect, the installer names the unavailable route and its providing service
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - release-bug
  - install
dependencies:
  - STATBUS-390
priority: high
type: bug
ordinal: 1
---

## Status 2026-09-24

**In Progress.** `538c731f4`, `373d15fc3`: `cli/cmd/install_failure_cause.go` and `install_failure_cause_test.go` diagnose the unavailable database route (#1 partly). The named route-provider unit test and `5-install-database-route-interrupted.sh` (#2-3) are absent. **Remaining:** assert address/provider/fix together and prove interrupted-route recovery through seed, migration, and final readiness on a VM.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every database step confirms its required route before use. If the route is unavailable, the operator sees the address, the plain-language service that provides it, and one recovery action. STATBUS-390 owns the common transport decision.

## Evidence, 2026-09-24

Finland migrations attempted `127.0.0.1:5431` after the web entry point had failed, while the database itself remained healthy (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:121-147`). Master publishes the host database route through the web entry point (`caddy/docker-compose.yml:15` at `7a9cf707e`) and invokes migrations through `./sb migrate up` (`cli/cmd/install.go:2557-2559` at `7a9cf707e`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_database_route_test.go::TestDatabaseRouteFailureNamesProvider` forces an unavailable selected route and observes its address, plain-language provider, and one recovery action.
- [ ] #2 `new: test/install-recovery/scenarios/5-install-database-route-interrupted.sh` interrupts the host route before migrations and observes either the STATBUS-390 in-service transport complete successfully or a bounded failure naming the web entry point, followed by a successful rerun.
- [ ] #3 `new: test/install-recovery/scenarios/5-install-database-route-interrupted.sh` records successful seed, migration, and final database readiness after recovery.
<!-- AC:END -->
