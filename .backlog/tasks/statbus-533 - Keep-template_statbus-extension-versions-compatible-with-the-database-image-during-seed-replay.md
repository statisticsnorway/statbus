---
id: STATBUS-533
title: >-
  Keep template_statbus extension versions compatible with the database image
  during seed replay
status: To Do
assignee: []
created_date: '2026-10-27T20:48:00Z'
updated_date: '2026-10-27T20:49:00Z'
labels:
  - database
  - seed
  - migrations
  - sql-saga
dependencies: []
priority: high
type: bug
ordinal: 459204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A database image with a newer sql_saga can rebuild the seed on any existing development volume. The template database's extension version follows the image, so a released migration never runs against an incompatible native library.

### Zoom out
STATBUS-531 exposed this remaining design gap: a long-lived `template_statbus` still had sql_saga 1.1 while the image provided 1.4. The era guard correctly chose FULL_REPLAY, but the template fork then reached the released 1.3 migration, whose native-library guard correctly refused the 1.4 libraries. The template was repaired manually with a direct `ALTER EXTENSION sql_saga UPDATE TO '1.4'`. Fresh installs and app-database upgrades work, but the next extension bump would recreate the replay failure on an old volume.

### Zoom in
Choose one way to keep the template compatible before migration replay:
- Align forked database extensions to the image's `pg_available_extensions` defaults after `CREATE DATABASE ... WITH TEMPLATE`, or
- Have the database container entrypoint upgrade template extensions on boot when the image default is newer, before writers start.

The upstream direct-update path must be preserved: do not hop through older extension versions with a newer native library, and do not edit released STATBUS migrations or weaken upstream guards. Include the case where several extension versions are behind, not only 1.1 -> 1.4.

Evidence: tmp/531-template-version.log, tmp/531-template-repair.log, tmp/531-test-fast.log. Ticket 531 has the full diagnosis.

### Closing review
- **Memory:** the template/image version rule is in the chosen definition comment and this ticket.
- **Documentation:** the migration procedure explains how the container keeps the template compatible.
- **Cleanup:** no manual template-repair step remains necessary for normal development.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Choose seed create-db alignment versus container-entrypoint upgrade. Record the choice in Implementation Notes and the chosen definition comment, including what it means for migration replay and application writers
- [ ] #2 A long-lived template at an older extension version reaches the image's current version before any migration runs, using the upstream direct-update path
- [ ] #3 Fresh PGDATA, a template several versions behind, and an app database at the previous extension version all complete migration and integrity checks without a manual ALTER EXTENSION step
- [ ] #4 The full fast suite passes after an extension bump on the long-lived template, and CI including the database image build is green at the fix commit
<!-- AC:END -->
