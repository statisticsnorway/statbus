---
id: STATBUS-542
title: >-
  reset() fails on a pg_restored database: sql_saga uk_truncate_check_c rejects
  external_ident_establishment_id_fkey_uk_truncate
status: In Progress
assignee: []
created_date: '2026-10-30T11:57:00Z'
updated_date: '2026-10-30T11:59:00Z'
labels:
  - sql_saga
  - reset
  - restore
dependencies: []
priority: medium
type: bug
ordinal: 468204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: public.reset() works on any statbus database, including one restored from a dump.

Evidence (2026-10-30, found while verifying STATBUS-538): restoring dbdumps/demo_20261030_093705.pg_dump (demo) with pg_restore --no-owner into a fresh database on the local db image (statbus-db:531-proof-14, sql_saga 1.4), then SELECT public.reset(true,'data') fails: ERROR trigger "external_ident_establishment_id_fkey_uk_truncate" on table "establishment" is not a sql_saga foreign key trigger (sql_saga.uk_truncate_check_c, raised by the TRUNCATE in reset()). The pre-STATBUS-538 reset() fails the same way, so this is independent of 538.

### Zoom out
Hypothesis: sql_saga identifies its foreign-key triggers by OID or attributes that change across pg_restore. Unknown whether ./sb db restore, seed restore, or operator demo->local restores hit it. Production reset after a restore would be blocked.

### Closing review
Record the cause in tmp/journal.md; document restore caveats in doc/DEPLOYMENT.md if operators are affected; drop scratch databases.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A script in tmp/ restores the demo dump into a scratch database and reproduces the reset() error
- [ ] #2 A regression test restores a dump and runs reset(); it fails before the fix
- [ ] #3 reset(true,'data') succeeds on a restored database and the regression test passes
<!-- AC:END -->
