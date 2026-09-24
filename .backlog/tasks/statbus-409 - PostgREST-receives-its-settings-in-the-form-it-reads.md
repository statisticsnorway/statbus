---
id: STATBUS-409
title: Each installed site gives the API its selected site settings
status: In Progress
assignee: []
created_date: '2026-09-24 15:46'
updated_date: '2026-09-24 18:44'
labels:
  - release-bug
  - api
  - configuration
  - postgrest
dependencies: []
references:
  - 'https://docs.postgrest.org/en/v14/references/configuration.html#app-settings'
  - 'https://docs.postgrest.org/en/v14/references/configuration.html#db-config'
priority: medium
type: bug
ordinal: 362000
---

## Status 2026-09-24

**In Progress.** `598b35e1b`: `docker-compose.rest.yml` uses `PGRST_APP_SETTINGS_DEPLOYMENT_SLOT_CODE`; `test/config/postgrest-environment-test.sh` covers #1. #2 `cli/internal/config/postgrest_test.go` and #3 non-default-slot integration proof are absent. **Remaining:** cover both `PGRST_DB_CONFIG` Boolean cases and observe the selected slot via PostgREST/SQL on a non-default installation.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The API receives the selected deployment slot as `app.settings.deployment_slot_code`, and its in-database configuration switch is a Boolean. Database functions therefore read the correct non-default site code.

## Evidence, 2026-09-24

Current compose configuration assigns the site-setting expression to `PGRST_DB_CONFIG` (`docker-compose.rest.yml:28-30,37-40`, especially line 38, at master `7a9cf707e`). PostgREST 14 documentation, sections “Environment Variables”, “app.settings.*”, and “db-config”, states that `PGRST_APP_SETTINGS_*` maps to `app.settings.*`, while `PGRST_DB_CONFIG` is Boolean and enables in-database configuration: <https://docs.postgrest.org/en/v14/references/configuration.html#app-settings> and <https://docs.postgrest.org/en/v14/references/configuration.html#db-config>.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/config/postgrest-environment-test.sh` asserts `PGRST_APP_SETTINGS_DEPLOYMENT_SLOT_CODE` carries the selected slot and `PGRST_DB_CONFIG` is exactly `true` or `false`.
- [ ] #2 `new: cli/internal/config/postgrest_test.go::TestPostgRESTDBConfigBooleanCases` covers both true and false switch values.
- [ ] #3 `new: test/integration/postgrest-deployment-slot-test.sh` starts a non-default slot and observes that `current_setting('app.settings.deployment_slot_code', true)` returns that slot through a database function.
<!-- AC:END -->
