---
id: STATBUS-138
title: >-
  migration-validity-split: ground truth counts migration files migrate refuses
  to apply — permanent false Behind
status: In Progress
assignee: []
created_date: '2026-07-04 22:32'
updated_date: '2026-07-11 20:20'
labels:
  - upgrade
  - install-recovery
  - product
  - silent-loss
dependencies: []
references:
  - cli/internal/migrate/migrate.go
  - cli/internal/upgrade/service.go
  - STATBUS-044
ordinal: 139000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: one shared definition of "a migration file" for both the applier and ground truth.
> BENEFIT: a stray invalid-named file in migrations/ can no longer make a healthy box read as Behind forever — which in a flag-driven recovery routes to an AUTOMATIC RESTORE of a healthy box (observed driving r17's rollback crash loop). Closes a silent-loss class with one shared predicate + a loud ignored-file warning.
> STAGE: Stage 1 (r17 live finding).
> COMPLEXITY: mechanic/tester (verification only) — the shared predicate shipped dff5231de (comment #2, 2026-07-08); AC#1-4 checked. What remains: AC#5, a live run proving a stray invalid-named migration file no longer restart-churns a flagless box.
> DEPENDS ON: nothing.

---

FOUND live in r17 (2026-07-05) and MORE SERIOUS than it first looks: the synthetic stall migration named 99999999999999_*.up.sql was REJECTED by migrate's version parser ('parsing time: month out of range' — the version must parse as a timestamp), so `sb migrate up` failed cleanly every pass — but verifyUpgradeGroundTruthEx's on-disk max computation happily COUNTED the same file (disk max 99999999999999 > db max) → GroundTruthBehind, permanently, on a box whose applied schema was actually current. In r17 that false Behind drove the recoveryRollback crash loop. GENERALIZED HAZARD: any stray invalid-named *.up.sql landing in migrations/ (operator copy, partial rsync, editor backup with a mangled prefix) makes ground truth read Behind FOREVER while migrate can never fix it — and during any flag-driven recovery that false Behind routes to an automatic restore of a healthy box. The two readers disagree on what a migration IS. FIX SHAPE (lego principle — one source of truth): a single shared lister/validity predicate used by BOTH migrate.Up's listMigrationFiles and the ground-truth diskMax computation — a file the applier would reject must be INVISIBLE to the comparator (and loudly logged as ignored-invalid so the operator hears about the stray file rather than silence). Verification: unit test — directory containing one valid + one invalid-version migration → ground truth diskMax == the valid one AND a warn line names the ignored file; migrate up applies the valid one and errors/skips-loudly on nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One shared version-validity predicate + lister in the migrate package; service.go's latestDiskMigrationVersion DELETED (clean break) and verifyUpgradeObservedStateEx reads the shared max — a file migrate refuses is INVISIBLE to the comparator
- [x] #2 Invalid-version *.up.sql files are SKIPPED LOUDLY by the shared lister (warn names the file), not a hard error for the whole run; valid-version files with other defects still hard-error
- [x] #3 Extension sets unified: .up.psql counted by BOTH readers (closes the inverse false-AtNew hazard)
- [x] #4 Pinning tests: valid+invalid fixture → identical sets from both readers + warn line; migrate.Up applies the valid file despite the stray; comparator never reads Behind from a refused file; .up.psql counted by both; floor bump-guard consistent on the same fixture
- [ ] #5 Flagless churn leg verified: a stray invalid file no longer makes boot-migrate fail exit-1 into restart churn (the exit-20-only 144 branch didn't cover it)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-08 21:30
---
FIX-SHAPE RULING (architect, 2026-07-08; both readers verified in code, severity re-verified under the shipped 145).

THE EXACT DIVERGENCE — threefold, one divergent caller: service.go's latestDiskMigrationVersion (:2540-2564, sole call site verifyUpgradeObservedStateEx :2520) vs migrate's listMigrationFiles→parseMigrationFile (migrate.go:593+). (1) VALIDITY: ground truth accepts ANY numeric prefix via strconv.ParseInt (:2555 — 99999999999999 passes); migrate validates the prefix as a real timestamp (time.Parse "20060102150405" — month 99 fails) and REFUSES THE WHOLE RUN on one bad file (listMigrationFiles returns nil,err). Exactly r17. (2) EXTENSIONS: ground truth globs .up.sql ONLY (:2548); migrate also applies .up.psql — the INVERSE hazard: a pending .up.psql is invisible to the comparator → false AtNew → recovery goes forward/completes on a genuinely-behind box. (3) FAILURE SEMANTICS: migrate hard-errors, ground truth silently skips-or-counts — the two readers cannot even fail the same way.

SEVERITY UNDER 145, CONFIRMED + ONE NEW CONSEQUENCE: (a) FLAGGED box: Behind is now the atomicity flip's trigger at THREE sites (recoverFromFlag Resuming arm :1045-1052, postSwapFailure :5025-5027, parkForDeterministicFailure :5044-5048) — an inflated diskMax on a healthy box drives an AUTOMATIC data-safe restore, and the false Behind survives the restore, so every subsequent flag-driven recovery re-fires it. The foreman's severity-raise claim HOLDS. (b) NEW, FLAGLESS box: the stray file makes boot-migrate fail with a NON-ExitError (parseMigrationFile error → ClassifyUpErr → ExitUnclassified 1, NOT exit 20) — so the 144 alive-idle branch does NOT catch it and the flagless boot takes the transient refuse-and-exit arm (:2014-2018) → restart churn → StartLimit death. The stray-file hazard is BOTH a false-rollback driver (flagged) and a 144-class churn driver (flagless). One fix cures both.

THE SINGLE-SOURCE SHAPE (lego): ONE predicate + ONE lister in the migrate package. (i) Extract the version-validity check (filename regex + timestamp parse) as the shared predicate. (ii) listMigrationFiles: an INVALID-VERSION file is SKIPPED with a LOUD warn naming the file (two-tier: a file failing the naming contract is NOT a migration — warn, not fail-fast; a hard error on an editor-backup stray violates the Albania frame and is what churns the flagless box today). Valid-version files with OTHER defects (unreadable, duplicate version) still hard-error — that arm is unchanged. (iii) Export the max (migrate.MaxDiskVersion or equivalent on the shared lister); DELETE latestDiskMigrationVersion from service.go (clean break, one caller to convert at :2520); the comparator now cannot disagree with the applier BY CONSTRUCTION. (iv) Extension unification rides for free (shared lister already globs both).

145 FLOOR MACHINERY: needs NO separate fix — HasPending/HasPendingAbove/the bump-guard scan already sit on listMigrationFiles, so they converge in the same commit by construction. NOTE the semantics change they inherit: an invalid-named file no longer errors those paths either — it warns. One consistency test pins lister/max/bump-guard agreement on the same fixture.

PINNING TESTS (the ACs, now added): the r17 fixture (one valid + 99999999999999_stray.up.sql) → identical sets from both readers, warn names the stray, migrate.Up applies the valid file, comparator NEVER reads Behind from a refused file; a .up.psql counted by BOTH; flagless boot with the stray does not churn.

BUILDER: engineer (cross-package clean-break + the skip-vs-refuse semantics change is design-sensitive); architect reviews the diff before commit. The r17 warn line should also be greppable as a stable marker — arcs may key on it later.
---

author: foreman
created: 2026-07-11 20:20
---
STATUS SYNC (foreman, 2026-07-11): the fix SHIPPED overnight 2026-07-08 in dff5231de ('migrate: one definition of a pending migration for applier and observer') — shared lister + validity predicate, invalid-named files skipped with a loud warn naming the file, MaxDiskVersion exported, latestDiskMigrationVersion DELETED from service.go (clean break), .up.psql unified, migration_validity_test.go (182 lines) pinning both-readers agreement per the ruling; architect-reviewed pre-commit. ACs #1-#4 checked on that evidence. AC#5 (the flagless churn leg verified LIVE — a stray invalid file no longer restart-churns a flagless box) has no dedicated run on record — it is the one open criterion; candidate vehicle: a small variant leg on an existing arc or a targeted VM check whenever convenient. Status corrected To Do → In Progress (was never moved when the code landed).
---
<!-- COMMENTS:END -->
