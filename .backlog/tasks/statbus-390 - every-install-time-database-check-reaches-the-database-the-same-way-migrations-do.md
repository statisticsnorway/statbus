---
id: STATBUS-390
title: >-
  Every install-time database check reaches the database the same way migrations
  do
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 15:35'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every install-time database operation uses one dependable connection method. Seed restore, state checks, migrations, locks, and final readiness agree on that route, so a healthy database produces the same result in every step.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

Finland seed and state checks could reach the database from inside its service while migrations and the automatic update service used a host route that was absent after the partial first run.

## Proving scenario

Use the existing injection hooks to stop the web entry point between seed and migrations. The migration step completes through the database service, or the installer restores and confirms the required route before continuing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Seed restore, state checks, migrations, locks, and readiness checks use one dependable database route.
- [ ] #2 A healthy database gives consistent reachability results across installation steps.
- [ ] #3 The injected route interruption scenario completes after the installer restores or bypasses the interrupted route.
<!-- AC:END -->

## Review correction 2026-09-24

Current route anchors are `caddy/docker-compose.yml:15`, `cli/cmd/install.go:2889`, and `cli/internal/migrate/migrate.go:156`; each claim must also cite its exact `tmp/setup-connection-map.md` line. Add **new** `test/install-recovery/scenarios/5-install-database-route-interrupted.sh`. Acceptance chooses one reliable transport, or explicitly equivalent readiness guarantees, and observes the selected guarantee at every listed seed, state, migration, and automatic-update step rather than saying “restore or bypass.”
