---
id: STATBUS-622
title: A dump with no sql_saga receipt restores at sql_saga 1.0 and fails Phase 3
status: In Progress
assignee:
  - hibiscus
created_date: '2026-11-11T16:19:00Z'
updated_date: '2026-11-11T16:26:00Z'
labels:
  - db
  - ops
dependencies: []
type: bug
ordinal: 535204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Any dump restores with its sql_saga version read from its own history, never defaulted to 1.0 when that history says otherwise.

./sb db restore loads a dump only if sql_saga is first created at the version the dump's rows were written for. A dump of a database created at the image's sql_saga pin and never updated, as rune has been since its 2026-11-08 reset, carries neither a sql_saga receipt in db.extension_upgrade nor any of the retired update migrations, so the restore created sql_saga 1.0 and Phase 3 failed on sql_saga.era.catalog_format (added after 1.0). Every Norway dump since that reset was unrestorable.

Zoom out: a restore reads the extension version from the dump's own history; when a database never changed its extension, the history is the release it was created on, so the version is that release's pin.

Zoom in: dumpSqlSagaVersion falls back, for a ledger past STATBUS-533's migration 20261027221500, to sqlSagaImagePins: the pin in force at the ledger's newest migration (1.4 today). TestSqlSagaImagePinMatchesDockerfile keeps the newest row equal to postgres/Dockerfile's sql_saga_release.

Closing review: no memory change; the reason is documented at sqlSagaImagePins and in the test; no other documentation or cleanup needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TestSqlSagaImagePinMatchesDockerfile passes with the Dockerfile's sql_saga_release
- [x] #2 rune's dump no_20261110_161917.pg_dump restores with ./sb db restore on a box at rc.01 (Phase 0 creates sql_saga 1.4, the restore exits 0)
- [x] #3 TestDumpSqlSagaVersion's case for a ledger past 20261027221500 with no sql_saga receipt passes, expecting 1.4
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
RED: the new case returned 1.0 (tmp/616/saga-red.log). GREEN: all 6 TestDumpSqlSagaVersion cases and TestSqlSagaImagePinMatchesDockerfile pass (tmp/616/saga-green.log). Found while restoring rune's dump on the bench box (STATBUS-616): Phase 0 created sql_saga 1.0, Phase 3 failed on sql_saga.era.catalog_format. Rune: sql_saga 1.4, db.extension_upgrade has receipts only for jsonb_stats, ltree, citext; 20261027221500 applied 2026-11-08.

AC2: on the bench box (ccx33, rc.01 stack 4a66d259) ./sb db restore dbdumps/no_20261110_161917.pg_dump --yes with sb built from the fix: 'Phase 0: sql_saga created at the dump's version 1.4', Phase 5 extension lifecycle ran, exit 0 in 994 s. Before the fix the same command failed in Phase 3 (Phase 0 at 1.0).
<!-- SECTION:NOTES:END -->
