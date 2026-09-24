---
id: STATBUS-394
title: >-
  After database setup, the installer confirms the API, application, worker, and
  automatic updates are ready
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
After database setup, the installer keeps database role passwords and generated settings in agreement, waits for the API, application, and worker to become ready, and confirms the automatic update service can reach the database before enabling it.

## Evidence, 2026-09-24

The Finland API restart loop reported `FATAL: password authentication failed for user "authenticator"`. An interrupted first run left the database role password and generated settings out of agreement. Step 17 then enabled automatic updates before proving its database route and timed out.

## Proving scenario

New harness scenario `5-install-rest-crashloop` injects a mismatched API database password and verifies that rerunning the one install command reconciles the role password and settings. A route check confirms the database is reachable through the automatic update service path before that service is enabled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every installer run keeps database role passwords and generated settings in agreement.
- [ ] #2 The installer confirms the API, application, and worker are ready after database setup.
- [ ] #3 The installer confirms the database is reachable through the automatic update service route before enabling that service.
- [ ] #4 The `5-install-rest-crashloop` scenario converges through the one install command and ends with every application service ready.
<!-- AC:END -->
