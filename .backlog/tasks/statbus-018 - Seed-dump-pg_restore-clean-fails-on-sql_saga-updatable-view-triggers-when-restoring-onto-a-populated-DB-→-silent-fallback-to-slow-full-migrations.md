---
id: STATBUS-018
title: >-
  Seed dump pg_restore --clean fails on sql_saga updatable-view triggers when
  restoring onto a populated DB → silent fallback to slow full-migrations
status: To Do
assignee: []
created_date: '2026-06-08 23:35'
updated_date: '2026-06-12 07:52'
labels:
  - install-recovery
  - seed
  - product
  - needs-king-decision
  - operator-ux
dependencies: []
references:
  - cli/cmd/seed.go
  - cli/cmd/install.go
  - test/install-recovery/scenarios/4-rollback-kill.sh
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: re-running the installer on a populated box is calm and safe.
> BENEFIT: the operator's only trained action stops printing a scary pg_restore ERROR on every routine refresh (which trains them to ignore errors), and re-installs stop silently falling back to the slow full-migrations path — calmer operators, faster refreshes, one less masked failure mode.
> STAGE: Stage 1 → Stage 3 operator UX.
> COMPLEXITY: engineer-substantial (fix the checkSeedRestored/R5 gate so Seed is quietly skipped — direction (c), architect-recommended; answers the 50fd4325f regression question en route).
> DEPENDS ON: nothing.

---

FOUND overnight 2026-06-09 (foreman + engineer, run 27167617557 / 4-rollback-kill). NOT data-loss (atomic), but an operator-facing robustness + suite-wide reliability/speed issue.

== SYMPTOM ==
On an install / idempotent step-table refresh onto an ALREADY-POPULATED DB, the Seed step runs pg_restore of the db-seed dump and fails:
  `pg_restore: error: could not execute query: ERROR: cannot drop trigger "for_portion_of_valid" on view "stat_for_unit__for_portion_of_valid" because it is part of an updatable view for era "valid" on table "stat_for_unit"`
  `Error: seed restore: pg_restore reported errors (transaction rolled back; database unchanged): exit status 1`
  `Seed restore failed — will run all migrations`

== ROOT CAUSE ==
The seed restore uses pg_restore with --if-exists/--clean (cli/cmd/seed.go: "n --if-exists to drop existing objects first"). On a populated DB, --clean tries to DROP the sql_saga-managed `for_portion_of_valid` trigger, but sql_saga owns that trigger as part of the updatable view for era "valid" → DROP TRIGGER is refused → the whole restore tx rolls back (atomic; DB unchanged). The harness then falls back to "run all migrations".

== IMPACT ==
- NOT data loss (pg_restore --single-transaction → atomic rollback → DB unchanged).
- Operator-facing: a scary pg_restore ERROR appears on EVERY install/refresh of a populated box. The sole operator action on the NO standalone box is the installer — so operators would see this alarming error routinely (bad UX; looks like a failure though it's tolerated).
- Suite-wide: any re-install onto a populated DB silently falls back to SLOW full-migrations instead of fast seed-restore (campaign reliability/speed hit; can mask other issues).
- The diagram (upgrade-timeline.plantuml § Fresh install) says checkSeedRestored "gates the Seed step OFF when the DB holds user data or applied migrations" — but the Seed step RAN here (gate did not skip). Needs verification: did the R5/checkSeedRestored gate fail to fire, or does this path bypass it? Possibly regressed by commit 50fd4325f (seed-sync-and-pin-gate rework).

== CANDIDATE FIX DIRECTIONS (King/architect call) ==
a. Make the seed dump / pg_restore --clean skip sql_saga-managed triggers (they're recreated by sql_saga, not by raw DDL).
b. Restore WITHOUT --clean onto a known-empty DB only (and rely on the R5 gate to skip on populated).
c. Fix the gate so the Seed step is correctly skipped on a populated DB (no restore attempt at all) — quiet, no error.
d. sql_saga DROP-ordering: drop the era/view via sql_saga functions before the trigger.

Distinct from STATBUS-017 (the rune wedge). Related to the R5 seed-on-populated pre-scan concern (engineer-2) — but mitigated to non-data-loss by pg_restore atomicity.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Decide the fix approach (skip sql_saga-managed triggers in --clean / restore without --clean / fix sql_saga DROP-ordering)
- [ ] #2 A re-install / idempotent refresh onto a populated DB restores the seed cleanly OR is correctly gated OFF (R5) — no pg_restore ERROR in operator-facing output
- [ ] #3 No silent fallback to full-migrations on a populated DB (or the fallback is intentional + quiet + documented)
- [ ] #4 Verify checkSeedRestored / R5 gate behavior on a populated DB; confirm whether 50fd4325f seed-sync-and-pin-gate regressed it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ARCHITECT RECOMMENDATION (2026-06-12, for the King's AC#1 call): direction (c) — fix the checkSeedRestored/R5 gate so the Seed step is correctly SKIPPED, quietly, on a populated DB. Why (c) over (a)/(b)/(d): the operator's sole action is the installer, and re-running it must always be safe and calm — a scary pg_restore ERROR on every routine refresh is an operator-UX defect, not cosmetics; (c) removes both the error AND the silent slow full-migrations fallback in one move, with no pg_restore/sql_saga surgery. AC#4 (did 50fd4325f regress the gate?) gets answered en route. Bonus: likely clears STATBUS-029 (stage-a red) with it. Not gate-blocking but cheap; can ride the gate-maker batch if capacity allows.
<!-- SECTION:NOTES:END -->
