---
id: STATBUS-520
title: Reading applied migrations on a fresh database answers none instead of failing
status: In Progress
assignee: []
created_date: '2026-10-20 18:07'
updated_date: '2026-10-20 18:07'
labels:
  - migrate
  - install
dependencies: []
priority: medium
ordinal: 446204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Every caller that asks which migrations are applied gets the true answer on a fresh database: none applied, so every migration on disk is pending.

### Zoom out
`listAppliedVersions` (`cli/internal/migrate/migrate.go`) is the one reader of `db.migration` behind `HasPending`, `HasPendingAbove`, `HasPendingAtOrBelow`, `Up` and `Redo`. On a database where `db.migration` does not exist yet, the answer is "nothing applied". Today it guesses that from psql's error text, and the guess stopped working.

### Zoom in
- **Mechanism:** since `94bfe3350` (2026-09-06) `runPsql` returns an `UpFailure` whose message is `migration failed (class=N): exit status 3`, without psql's output. `listAppliedVersions` looks for `db.migration ... does not exist` in that message, never finds it, and returns an error.
- **Prototype:** 2026-10-20 14:27 (`tmp/journal.md`): on a database without `db.migration`, `listAppliedVersions` returned `query applied migrations: migration failed (class=0): exit status 1`.
- **Callers today:**
  - `checkMigrationsDone` (install step) reads the error as "not done" and runs `Up`, which creates the table first, so install still works.
  - `HasPendingAtOrBelow` (inline upgrade dispatch) reads an error as "migrate to the floor first", the same outcome.
  - `HasPendingAbove` (service boot log) skips its line on error.
  - `resumeNewSb` defers to rollback on error; a fresh database cannot reach that path.
  - `Up` and `Redo` call it after the table exists.
  - So the defect is latent, but any new caller that trusts the error gets the wrong answer.
- **Fix:** ask the database whether the table exists (`to_regclass('db.migration')`, which answers NULL for a missing table or schema without failing), then read versions only when it does. Any query error is a real error. `contentHashColumnExists` carries the same error-text branches, but its `information_schema` query never fails on a missing table, so those branches are dead and go too.

### Closing review
- **Memory:** none needed.
- **Documentation:** `listAppliedVersions` comment states it asks whether the table exists and returns every query error.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Write a Go test with a fake psql where db.migration does not exist: listAppliedVersions returns no versions and no error, and HasPending reports the on-disk migrations pending; record it failing on master before the fix
- [ ] #2 Write a Go test where the database cannot be reached: listAppliedVersions returns an error
- [ ] #3 Write a Go test where db.migration holds versions: listAppliedVersions returns exactly those versions
- [ ] #4 Run the existence query against a brand-new empty database and against the dev database, and record both answers in Implementation Notes
- [ ] #5 Remove the error-text branches from listAppliedVersions and contentHashColumnExists, and update listAppliedVersions' comment to state that it asks whether the table exists and returns every query error
<!-- AC:END -->
