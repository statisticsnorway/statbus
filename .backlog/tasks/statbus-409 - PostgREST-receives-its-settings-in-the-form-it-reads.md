---
id: STATBUS-409
title: PostgREST receives its settings in the form it reads
status: To Do
assignee: []
created_date: '2026-09-24 15:46'
labels:
  - api
  - configuration
  - postgrest
dependencies: []
references:
  - 'https://docs.postgrest.org/en/v14/references/configuration.html#db-config'
priority: medium
type: bug
ordinal: 362000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PostgREST receives each setting through the environment variable defined for that setting. The deployment slot code is supplied through the `PGRST_APP_SETTINGS_*` form so database functions can read `app.settings.deployment_slot_code`, while `PGRST_DB_CONFIG` remains a true or false switch for in-database configuration.

## Evidence, 2026-09-24

`docker-compose.rest.yml` currently gives `PGRST_DB_CONFIG` the value `app.settings.deployment_slot_code=...`. PostgREST 14 documentation defines `db-config` as a Boolean with environment variable `PGRST_DB_CONFIG`, and defines arbitrary `app.settings.*` values through `PGRST_APP_SETTINGS_*`. The current value therefore controls the Boolean switch and does not deliver the deployment slot setting described by the comment.

Official documentation: https://docs.postgrest.org/en/v14/references/configuration.html#db-config and the `app.settings.*` section on the same page.

## Proving scenario

Start the API with a non-default deployment slot and query `current_setting('app.settings.deployment_slot_code', true)` through a test database function. It returns the selected slot. A configuration test also confirms `PGRST_DB_CONFIG` is a Boolean value.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The deployment slot code is passed through `PGRST_APP_SETTINGS_DEPLOYMENT_SLOT_CODE`.
- [ ] #2 Database functions read the selected slot from `app.settings.deployment_slot_code`.
- [ ] #3 `PGRST_DB_CONFIG` contains a true or false value that controls in-database configuration.
- [ ] #4 A PostgREST 14 integration test observes the selected slot through `current_setting`.
<!-- AC:END -->
