---
id: STATBUS-411
title: The installer tells an unmigrated database apart from a pre-1.0 one and continues with seed and migrations
status: To Do
assignee: []
created_date: '2026-09-24 15:59'
labels:
  - install
  - recovery
  - database
dependencies: []
references:
  - /Users/jhf/ssb/statbus/tmp/finland-answers-4.txt
  - /Users/jhf/ssb/.jcode/scratch/rest-loop.md
priority: high
type: bug
ordinal: 361100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An initialized but unmigrated database is a fresh installation in progress. The installer continues with seed and migrations instead of directing its operator to the legacy upgrade procedure. A genuine pre-1.0 database, which contains StatBus tables and data but no `public.upgrade`, retains the existing refusal and manual-upgrade guidance.

## Grounded evidence

At master `7a9cf707e`, `cli/internal/install/state.go:138-148` checks `DBReachable`, then `HasUpgradeTable`, then returns `StateLegacyNoUpgradeTable` whenever the table is absent. This does not distinguish a database initialized by `postgres/init-db.sh` (roles and an application database, before the StatBus schema is installed) from an established pre-1.0 database. The differentiator to test is presence of StatBus schema/tables and data, not just absence of `public.upgrade`.

In `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:69-89`, the operator removed `statbus-local-db-data`, ran `./sb restart all` to create a fresh database volume, then ran `./sb install`. The output was exactly:

> Detected install state: legacy-no-upgrade-table (current=v2026.09.2, target=v2026.09.2)
>   Pre-1.0 install detected (public.upgrade absent). Install will refuse; automatic upgrade from pre-1.0 tracked as #65.6.
>
> Error: pre-1.0 install detected (public.upgrade table absent). Automatic upgrade from pre-1.0 is not yet implemented (tracked as #65.6). Contact support or follow the manual upgrade path in doc/CLOUD.md

The related VM reproduction is `/Users/jhf/ssb/.jcode/scratch/rest-loop.md:48,168`. STATBUS-408 covers a *different entry into this same state ladder*: an interrupted installation whose original database volume survives. Keep the scenarios separate and cross-link their implementation.

## Proving scenarios

Existing unit-test location: `cli/internal/install/state_test.go:46` (`TestDetectWith`). Extend its fake-probe cases for init-db-only, established pre-1.0, and migrated databases. **New** install-recovery harness case: complete a fresh install, stop services and remove its test database volume, run `./sb restart all`, then paste the published one install command. Assert it reaches green and creates the StatBus schema rather than reporting a pre-1.0 installation. Run this only on an isolated disposable test VM and volume, never an operator database.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `TestDetectWith` classifies a reachable init-db-only database with no StatBus schema as fresh and not yet migrated, an established database with StatBus tables and no `public.upgrade` as pre-1.0, and a migrated database as its existing state.
- [ ] #2 On the fresh-unmigrated state, the installer proceeds through seed and migrations (steps 12-13) and the published install command completes with every required service ready.
- [ ] #3 On the established pre-1.0 state, the installer keeps the existing refusal and manual-upgrade guidance rather than writing over its data.
- [ ] #4 The new isolated fresh-volume/restart/install harness case completes without the `legacy-no-upgrade-table` refusal.
<!-- AC:END -->
