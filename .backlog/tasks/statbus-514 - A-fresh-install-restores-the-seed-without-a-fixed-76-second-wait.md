---
id: STATBUS-514
title: A fresh install restores the seed without a fixed 76-second wait
status: Done
assignee: []
created_date: 2026-10-16 13:43
updated_date: '2026-10-28T01:09:00Z'
labels:
  - install
  - performance
dependencies: []
priority: medium
type: bug
ordinal: 440204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A fresh install goes from "Database sessions" to restoring the seed as soon as the database answers and is empty, with no fixed wait.

### Zoom out
Before restoring the seed, the installer must know the database is fresh: restoring over user data or a migrated schema would destroy it. The check therefore retries while the database cannot be reached. An empty database that answers is not a transient state, it is the answer, so waiting on it adds time without adding safety.

### Zoom in
- **Observed:** every fresh install pauses about 76 s between `[13/18] Database sessions OK` and `[14/18] Seed RUNNING`. In smoke run `38818339306` (v2026.10.2-rc.01): 22:43:30, then "Pausing application traffic" at 22:44:07, then Seed at 22:44:48. The same gap is in both smoke installs and all 15 fresh-install scenarios of fault fleet `38819807364`.
- **Mechanism:** `checkSeedRestored` (`cli/cmd/install.go`) loops 15 times with a 2 s sleep while `dbHasUserData`, `dbHasAppliedMigrations` and `checkMigrationsDone` are all false, which is exactly the fresh case, so it always runs to the end (about 38 s with probe time). It is called twice: once by the quiesce gate before Seed (`!s.check(installDir)`) and once by `executeInstallStep`.
- **Cost:** about 1.3 min on every real first install, on the release gate's smoke stage (critical path), and about 20 guest-minutes per candidate across the fault fleet.
- **Constraint:** the probes treat an unreachable database or a missing table as "no data". The fix asks the database directly (which tables exist, then whether they hold rows) and treats any query error as an error: the Seed step stops with a clear message and the database is never read as fresh.

### Closing review
- **Memory:** none needed.
- **Documentation:** the function's comment states that it decides from one direct read, and that a query error stops the Seed step and is never read as fresh.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Write a Go test where the database answers with no data and no migrations: `checkSeedRestored` returns false without sleeping (test measures under 2 s); record it failing on master before the fix
- [x] #2 Write a Go test where the database query fails: the check returns an error, the Seed step stops, and the database is never reported fresh; record it failing on master before the fix
- [x] #3 A candidate smoke run after the fix shows "[14/18] Seed RUNNING" within 10 s of "[13/18] Database sessions OK" in `0-happy-install`; run ID recorded in Implementation Notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-20 owner-approved design (simple version):
- One direct read replaces the 15 x 2 s loop: a query using to_regclass() asks which of db.migration, statistical_unit, legal_unit, establishment, import_job exist (never errors on a reachable database); then, only for the tables that exist, whether any user table has rows and whether db.migration has any row.
- Fresh = no user rows and no applied migration -> run the seed restore at once.
- Any query error stops the Seed step with a clear message (re-run ./sb install continues); never read as fresh. No retry loop, no caching (same rule as STATBUS-439's JWT step).
- checkMigrationsDone is dropped from this decision (covered by 'any migration applied', and broken on a fresh database, see below).
- Tests in cli/cmd/install_seed_freshness_test.go (uncommitted draft, to be cut down to: empty -> fresh at once; user data -> not fresh; applied migration -> not fresh; query error -> error, never fresh), driven by a fake psql on PATH (DOCKER_PSQL=0); shown red on the parent, green after.
Second defect found (separate ticket to open after 514): listAppliedVersions detects a missing db.migration by matching 'does not exist' in err.Error(), but since 94bfe3350 (2026-09-06) runPsql wraps errors in UpFailure whose message lacks psql output, so HasPending errors on a fresh database. Prototype in tmp/journal.md 2026-10-20 14:27.

2026-10-20 implemented in 3a3fec4db (install.go: seedFreshness replaces the 15 x 2 s loop and the dbHasUserData/dbHasAppliedMigrations/checkMigrationsDone guess-on-error probes; runSeedRestore reads again before restoring and stops on a read error).
Tests cli/cmd/install_seed_freshness_test.go drive the real Seed step (executeInstallStep) with a fake psql:
- Red on parent ba00e9294 (tmp/test-514-red.log): empty database took 29.15 s and 29.22 s (no tables / empty tables); unreadable database gave err=<nil> instead of stopping. User rows and applied migrations passed (unchanged behaviour).
- Green after (tmp/test-514-green.log): all four pass, empty case 1.18 s for both subtests including the fake fetch; go test ./cmd/ ./internal/migrate/ ok (tmp/test-514-cmd-full.log).
- Real queries checked on the dev database (lists all five tables, answers t) and on a brand-new empty database (empty list).
AC3 waits for the next candidate's smoke run (no RC until sql_saga 1.2).

AC3 candidate smoke evidence: rc.03 Test Smoke run 40607115914, 0-happy-install job 122549573505. Database sessions OK at 00:15:03.9806830; Seed RUNNING at 00:15:06.3923313, 2.41 seconds later. The steps are now 14/19 and 15/19 because later steps were added; the AC's timing requirement is met.
<!-- SECTION:NOTES:END -->
