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

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

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

## Review correction 2026-09-24

Current compose evidence is `docker-compose.rest.yml:5,28-30,37-40`; line 38 is erroneous. Verify semantics against the linked official PostgREST 14 configuration section and record section/version. Add named new config and integration test files, including non-default slot and true/false Boolean cases. PGRST names stay engineering detail; the operator observes the selected site's settings.
