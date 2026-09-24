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
