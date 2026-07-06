---
id: STATBUS-138
title: >-
  migration-validity-split: ground truth counts migration files migrate refuses
  to apply — permanent false Behind
status: To Do
assignee: []
created_date: '2026-07-04 22:32'
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
> COMPLEXITY: engineer-substantial (shared lister/validity predicate across migrate.go + the ground-truth diskMax; unit-tested).
> DEPENDS ON: nothing.

---

FOUND live in r17 (2026-07-05) and MORE SERIOUS than it first looks: the synthetic stall migration named 99999999999999_*.up.sql was REJECTED by migrate's version parser ('parsing time: month out of range' — the version must parse as a timestamp), so `sb migrate up` failed cleanly every pass — but verifyUpgradeGroundTruthEx's on-disk max computation happily COUNTED the same file (disk max 99999999999999 > db max) → GroundTruthBehind, permanently, on a box whose applied schema was actually current. In r17 that false Behind drove the recoveryRollback crash loop. GENERALIZED HAZARD: any stray invalid-named *.up.sql landing in migrations/ (operator copy, partial rsync, editor backup with a mangled prefix) makes ground truth read Behind FOREVER while migrate can never fix it — and during any flag-driven recovery that false Behind routes to an automatic restore of a healthy box. The two readers disagree on what a migration IS. FIX SHAPE (lego principle — one source of truth): a single shared lister/validity predicate used by BOTH migrate.Up's listMigrationFiles and the ground-truth diskMax computation — a file the applier would reject must be INVISIBLE to the comparator (and loudly logged as ignored-invalid so the operator hears about the stray file rather than silence). Verification: unit test — directory containing one valid + one invalid-version migration → ground truth diskMax == the valid one AND a warn line names the ignored file; migrate up applies the valid one and errors/skips-loudly on nothing.
<!-- SECTION:DESCRIPTION:END -->
