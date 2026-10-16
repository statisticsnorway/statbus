---
id: STATBUS-514
title: A fresh install restores the seed without a fixed 76-second wait
status: To Do
assignee: []
created_date: '2026-10-16 13:43'
labels:
  - install
  - performance
dependencies: []
priority: medium
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
- **Constraint:** the probes treat an unreachable database or a missing table as "no data". The fix must keep retrying when the database cannot be reached and decide at once only when it answers with no data and no migrations.

### Closing review
- **Memory:** none needed.
- **Documentation:** the function's comment states when it waits and when it decides at once.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Write a Go test where the database answers with no data and no migrations: `checkSeedRestored` returns false without sleeping (test measures under 2 s); record it failing on master before the fix
- [ ] #2 Write a Go test where the database is unreachable for the first attempts: the check keeps retrying and does not return "fresh" until the database answers
- [ ] #3 The Seed step evaluates its check once per install run (quiesce gate and step share the result), shown by the test or a code read recorded in Implementation Notes
- [ ] #4 A candidate smoke run after the fix shows "[14/18] Seed RUNNING" within 10 s of "[13/18] Database sessions OK" in `0-happy-install`; run ID recorded in Implementation Notes
<!-- AC:END -->
