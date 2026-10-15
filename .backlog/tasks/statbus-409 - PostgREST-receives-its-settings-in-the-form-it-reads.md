---
id: STATBUS-409
title: >-
  Each site passes its site code to database functions through PostgREST app
  settings
status: Done
assignee: []
created_date: '2026-09-24 15:46'
updated_date: '2026-10-15 19:39'
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

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Database functions on every StatBus site can read which site they serve, because the API passes the site code to PostgreSQL the way PostgREST defines it.

### Zoom out
PostgREST forwards `PGRST_APP_SETTINGS_<NAME>` environment variables into each database session as `app.settings.<name>`, readable with `current_setting`. `PGRST_DB_CONFIG` is something else: a true/false switch for reading configuration from the database. The site code had been put into `PGRST_DB_CONFIG`, so every site silently fell back to the default code. Each setting must go through the variable PostgREST defines for it.

### Zoom in
- **Finding, 2026-09-24:** `docker-compose.rest.yml` set `PGRST_DB_CONFIG` to an `app.settings.deployment_slot_code=...` expression. PostgREST 14 documents `db-config` as Boolean and `app.settings.*` as coming from `PGRST_APP_SETTINGS_*` (https://docs.postgrest.org/en/v14/references/configuration.html#app-settings, `#db-config`). Database code reads it as `coalesce(current_setting('app.settings.deployment_slot_code', true), 'dev')` (for example `public.auth_test()`), so the fallback `dev` was returned everywhere.
- **Shipped:** `598b35e1b` (2026-09-24, v2026.09.3): `PGRST_APP_SETTINGS_DEPLOYMENT_SLOT_CODE: ${DEPLOYMENT_SLOT_CODE}` and `PGRST_DB_CONFIG: "true"`.
- **Proof, CI:** `test/config/postgrest-environment-test.sh` checks both variables; it runs in Go Test (`ac660d02e`, merge `367966083`), green in `36564358788`, and locally 2026-10-15.
- **Proof, live (2026-10-15, read-only anonymous call):** `POST https://demo.statbus.org/rest/rpc/auth_test` returns `deployment_slot = demo`, a non-default value read through `current_setting` in a database function. Dev returns `dev`, which equals the fallback and so proves nothing on its own.

### Closing review
- **Memory:** none needed.
- **Documentation:** the compose file comment explains the mapping.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The API passes the site code as `PGRST_APP_SETTINGS_DEPLOYMENT_SLOT_CODE` and `PGRST_DB_CONFIG` is exactly `true` or `false` (`test/config/postgrest-environment-test.sh`, in Go Test)
- [x] #2 A database function on a site with a non-default code reads that code from `app.settings.deployment_slot_code` (demo returns `deployment_slot = demo` from `rpc/auth_test`, 2026-10-15)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** Go Test `36564358788`, step "PostgREST receives the selected site settings"; local pass 2026-10-15.
- **AC2:** live, read-only anonymous `rpc/auth_test` on demo, 2026-10-15.
- **Superseded:** the restyle named `cli/internal/config/postgrest_test.go` (Boolean cases) and `test/integration/postgrest-deployment-slot-test.sh`, neither written. The shell test covers the Boolean value, and the live demo call is the end-to-end proof.
<!-- SECTION:NOTES:END -->
