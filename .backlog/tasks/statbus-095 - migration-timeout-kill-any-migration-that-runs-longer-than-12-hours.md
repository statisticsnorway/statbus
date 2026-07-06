---
id: STATBUS-095
title: 'migration-timeout: kill any migration that runs longer than 12 hours'
status: To Do
assignee: []
created_date: '2026-06-18 21:18'
updated_date: '2026-06-18 21:36'
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
- [ ] #4 Reconciled with the existing migrate.go timeouts (60-min CLI / 5-min boot / 30-min resume) — documented which bound changed and why
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OWNERSHIP (foreman, 2026-06-18): build = engineer; review = architect (this is product upgrade-path code — review carefully) then foreman (diff); commit = foreman.

DESIGN-FIRST: before implementing, reconcile the new 12-hour ceiling against the existing migrate.go bounds (60-min CLI backstop at :420, ~5-min boot, ~30-min resume) and propose which bound changes — present that to the foreman for the King's nod before touching product code (it changes how long a real upgrade is allowed to run).

CLARITY ON SUCCESS: the load-bearing criterion is the CONFIGURABLE short threshold — that is exactly what lets STATBUS-096 scenario 2 exercise the real timeout-kill path in seconds instead of waiting 12 hours. The kill here is INTERNAL (our code's timeout fires); contrast STATBUS-096's OOM, which is an EXTERNAL kill of Postgres.
<!-- SECTION:NOTES:END -->
