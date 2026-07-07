---
id: STATBUS-095
title: 'migration-timeout: kill any migration that runs longer than 12 hours'
status: To Do
assignee: []
created_date: '2026-06-18 21:18'
updated_date: '2026-07-07 04:27'
labels:
  - upgrade
  - migration
  - product-requirement
dependencies: []
ordinal: 95000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: no migration runs forever on an unattended box — a 12-hour ceiling kills the runaway and the box recovers by the normal path.
> BENEFIT: a stuck or runaway migration (the class heavy Norway-size rewrites can produce) can no longer hold a box hostage indefinitely with nobody there to notice; the configurable-short threshold makes the same kill path testable in seconds.
> STAGE: Stage 1 (King requirement 2026-06-18; fills a TODO row in 071's coverage map).
> COMPLEXITY: engineer-substantial, design-first (reconcile with the existing 60min-CLI/5min-boot/30min-resume bounds; King nod on the reconciliation before code).
> DEPENDS ON: nothing.

---

NEW REQUIREMENT (King, 2026-06-18). A migration that runs longer than 12 hours must be killed by the system. A stuck or runaway migration cannot be allowed to run forever — especially on an unattended standalone box (Albania) with no remote rescue.

WHAT TO BUILD:
- Enforce a maximum migration runtime of 12 hours on the upgrade path; kill the migration when it is exceeded.
- The kill is INTERNAL: our own code's timeout fires and kills the migration. (This is a DIFFERENT kill source from an external OOM-kill of PostgreSQL — see the kill-recovery test task.)
- The 12-hour threshold MUST be configurable to a short value, so a test can trigger the exact same kill path in seconds instead of waiting 12 hours.
- After the kill, the box must recover correctly via the upgrade's normal rollback/recovery path.

RECONCILE WITH EXISTING TIMEOUTS (design step): today migrate.go has shorter bounds — a 60-min context ceiling on the direct CLI path (migrate.go:420) and outer upgrade-path bounds (~5 min boot / ~30 min resume). A big, legitimate migration may need up to 12 hours, so the allowed runtime likely needs RAISING to 12h with a hard kill at the ceiling. Confirm the exact reconciliation (which path, which bound) in design before implementing.

Source: King, 2026-06-18.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A migration exceeding the 12-hour ceiling is killed by the system's own internal timeout
- [ ] #2 The 12h threshold is configurable to a short value so a test triggers the same kill path in seconds
- [ ] #3 After the timeout-kill the box recovers correctly (rollback/recovery)
- [x] #4 Reconciled with the existing migrate.go timeouts (60-min CLI / 5-min boot / 30-min resume) — documented which bound changed and why
<!-- AC:END -->



## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OWNERSHIP (foreman, 2026-06-18): build = engineer; review = architect (this is product upgrade-path code — review carefully) then foreman (diff); commit = foreman.

DESIGN-FIRST: before implementing, reconcile the new 12-hour ceiling against the existing migrate.go bounds (60-min CLI backstop at :420, ~5-min boot, ~30-min resume) and propose which bound changes — present that to the foreman for the King's nod before touching product code (it changes how long a real upgrade is allowed to run).

CLARITY ON SUCCESS: the load-bearing criterion is the CONFIGURABLE short threshold — that is exactly what lets STATBUS-096 scenario 2 exercise the real timeout-kill path in seconds instead of waiting 12 hours. The kill here is INTERNAL (our code's timeout fires); contrast STATBUS-096's OOM, which is an EXTERNAL kill of Postgres.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-07 04:09
---
CONSTRUCTION RULING (architect, 2026-07-07 — the artifact the King's approval and the build key on). PRODUCT FIRST, THEN ARC — two separately reviewed pieces.

PIECE 1 — THE PRODUCT KNOB (engineer, reviewed diff BEFORE any arc work). The ceiling mechanism ALREADY EXISTS and is reused, not rebuilt: MigrateUpTimeout (watchdog.go:153, today 30 minutes) bounds every `sb migrate up` subprocess the upgrade system runs (boot-migrate, the applyPostSwap migrate step at service.go:5337, and the inline install's crash-recovery boot-migrate), and the #14 orphan-terminate (migrate_orphan machinery, noted at service.go:1884) already terminates the in-DB backend the killed subprocess leaves behind — the exact runaway-SQL problem a naive subprocess-kill would miss. The change: (a) RAISE the constant to the King's 12-hour allowance (a genuinely big Norway migration may legitimately need it; 30 minutes now that boot-migrate applies real deltas is too tight — this IS the ticket's reconciliation item AC#4); (b) make it ENV-OVERRIDABLE (e.g. STATBUS_MIGRATE_UP_TIMEOUT, parsed as a Go duration, default 12h, floor-guarded at something sane like 5s) so the arc can set seconds — the load-bearing criterion AC#2; (c) verify BOTH migrate sites (boot + applyPostSwap) run the orphan-terminate on timeout, not just boot — if the applyPostSwap site lacks it, add it in the same diff; (d) the timeout failure keeps its existing routing: step fails → observed state reads Behind (the killed migration is unrecorded) → in-process rollback → rolled_back — no new classification needed, and a NAMED log marker ('migration exceeded the ceiling (<duration>) — killed; rolling back') so the arc has a greppable observable. The 60-minute direct-CLI bound (migrate.go:503) is a DIFFERENT surface (developer terminal) and stays as-is — note that in the diff so AC#4's 'documented which bound changed and why' is discharged.

PIECE 2 — THE ARC (mechanic, after piece 1 merges + its images build). postswap-migration-ceiling-arc, modeled on the proven V_fail lineage: construct B = A + V_sleep (fixture body `SELECT pg_sleep(3600);` — hand-authored WITHOUT its own BEGIN/END) via the 118 constructor; a dropin arms STATBUS_MIGRATE_UP_TIMEOUT=20s in the daemon env (the stall-dropin pattern, restart-for-env); real register → schedule → the daemon dispatches. OBSERVABLE CHAIN, in order: row in_progress → swap (exit-42 handoff, NRestarts +1) → migrate step starts V_sleep → MIDPOINT ANTI-VACUITY: poll pg_stat_activity for the active pg_sleep backend (the proven park/mid-tx pattern) — proves the migration genuinely ran INTO the ceiling rather than failing early → ceiling fires at ~20s: the named marker in the dispatch/progress log + subprocess killed + orphan backend terminated (assert the pg_sleep backend GONE within a short poll — the #14 leg observed live) → step fails → Behind → in-process rollback → TERMINAL: rolled_back. ASSERTION SPEC (the proven-arc discipline): midpoint pg_sleep-active; ceiling marker present; orphan backend gone; terminal rolled_back (completed/failed → hard fail); V unrecorded (db.migration max == baseline); clean-slate fingerprint == post-A baseline (this arc's rollback RESTORES the snapshot — the failing-arc apparatus verbatim); demo data intact; flag absent; NRestarts == the failing-arc's proven bound (the handoff bump only — the daemon survives the in-process rollback).

SEQUENCING: piece 1 is a small, safety-relevant product diff → architect review before commit; the arc follows on its images. STATBUS-096's scenario 2 (internal timeout kill) IS this arc — it folds here and 096 keeps only the OOM scenario.
---

author: foreman
created: 2026-07-07 04:27
---
PIECE 1 SHIPPED c500efc9d (2026-07-07), dual-reviewed (architect ship, both flags ruled; foreman first-hand): MigrateUpTimeout 30m→12h default; STATBUS_MIGRATE_UP_TIMEOUT env override (Go duration, 5s floor + WARN — the arc's seconds-scale knob); resolved ONCE at package init (architect: per-call env reads could change the ceiling MID-UPGRADE — the ambient-state class rejected in the 116 flag-retirement ruling; one process, one ceiling); const→var with identifier unchanged (call sites + structure guards untouched); both migrate sites verified orphan-terminate on timeout (no code needed); NAMED ceiling marker at the applyPostSwap timeout branch, emitted before orphan-reap+rollback — deliberately asymmetric (the flagless boot-migrate timeout REFUSES, so 'rolling back' would lie there; a ceiling-length migration reaches the marker site from both directions via the 017 defer→resume). AC#4 reconciliation documented at the const: 60-min direct-CLI bound is a different surface, unchanged. Resolver table test (10 cases) + 12h-default pin. NEXT: piece 2 — the ceiling arc (mechanic) once c500efc9d's images publish; V_sleep + 20s override dropin + the full proven-arc assertion discipline including the orphan-backend-gone leg.
---
<!-- COMMENTS:END -->
