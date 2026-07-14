---
id: STATBUS-187
title: >-
  silent-error-catalog: fifteen silently-ignored errors in the upgrade/migrate
  core, ranked (from the 176 burn-down)
status: To Do
assignee: []
created_date: '2026-07-14 19:23'
labels:
  - fail-fast
  - upgrade
  - defect
  - install-recovery
dependencies: []
priority: medium
ordinal: 188000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: no error in the upgrade/migrate core is silently dropped where its failure changes what the operator or the recovery machinery believes. The 176 errcheck burn-down made every ignore EXPLICIT with an inline concern-comment; this ticket is the catalog of the fifteen whose proper handling is a behavior change needing individual rulings — the 185 pattern, second wave.
> ORIGIN: STATBUS-176 batch 2 (mechanic, 2026-07-14); each site carries its concern inline in code. Architect severity review pending on the top three.

RANKED (mechanic's ordering, architect to confirm/amend):
TOP — masks a second failure or risks live-service consistency:
1. service.go rollback() ABORT branch: restoreDatabase error dropped — DB volume can be left inconsistent while the terminal reports only ROLLBACK_FAILED_GIT_CORRUPT.
2. service.go ReattemptRestore + rollback() normal path: pre-restore `docker compose stop` ignored — the volume rsync can proceed against live services.
3. service.go executeUpgrade CI-not-ready unschedule: returns nil regardless of whether the row-reset UPDATE landed — silent failure leaves the row wedged/unclaimable.
STALE-FLAG CLASS (failed unlink → a later boot misreads crashed/in-progress): 4. removeUpgradeFlag (both sites); 5. ReleaseInstallFlag; 6. post-swap self-heal completion flag Remove.
ONE-SHOT AT BOOT: 7. cleanStaleMaintenance Remove — failure leaves the site in maintenance (Caddy 503) until the next daemon restart.
LEDGER DIVERGENCE (migrations): 8. migrate.go two `DELETE FROM db.migration` in the down path; 9. full-rollback DROP TABLE/SCHEMA leftover.
BOUNDED/SELF-RETRYING: 10. recoverFromFlag corrupt-flag + stale-install-flag removes (retry next boot).
COSMETIC/SELF-CORRECTING: 11. exec.go backup/log prune RemoveAlls; 12. periodic-poll UPDATEs + PostgREST NOTIFYs (self-correct next cycle).

SHAPE: fix in ranked waves (top-3 first, as their own reviewed unit with arc/regression coverage where the paths are arc-covered — #1 and #2 sit exactly on restore paths the restore-broke-reattempt arc exercises); stale-flag class as one uniform treatment; tail may be accepted-and-documented. Every fix replaces its explicit-ignore marker.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect confirms/amends the ranking and rules the handling per tier (hard-fail / loud-warn / accept-documented)
- [ ] #2 Top-3 fixed as their own reviewed unit, proven by the arcs that cover those paths
- [ ] #3 Stale-flag class gets one uniform ruled treatment
- [ ] #4 Every fixed site's explicit-ignore marker is replaced; accepted sites keep a ruling-citing comment
<!-- AC:END -->
