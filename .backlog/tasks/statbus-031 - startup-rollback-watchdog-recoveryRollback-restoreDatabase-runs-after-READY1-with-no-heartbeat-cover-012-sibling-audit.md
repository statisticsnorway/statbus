---
id: STATBUS-031
title: >-
  rollback-watchdog-cover: restoreDatabase/rollback() has no effective
  WATCHDOG=1 source on any path — wrap the rollback chokepoint (012 pattern)
status: To Do
assignee: []
created_date: '2026-06-11 13:39'
updated_date: '2026-06-12 09:04'
labels:
  - upgrade
  - recovery
  - product
  - audit
dependencies: []
references:
  - STATBUS-039
documentation:
  - >-
    doc-007 -
    Roadmap-completing-install-upgrade-robustness-—-Norway-rollout-then-external-standalone.md
priority: high
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CONFIRMED (architect sweep, 2026-06-11 — supersedes the original "suspected" framing). The LAST uncovered DB-size-scaled step in service startup; wedge list is bounded: 017 done, 012 done, 031 last. KING DECISION at the rc.01 cut: this gates the STABLE/Norway promotion, not the prerelease.

THE GAP: restoreDatabase (exec.go:695-714) restores the DB volume via a docker-run rsync of the WHOLE volume — onAdvance=nil, output to progress.File() which bypasses the heartbeat; the last WATCHDOG=1 ping is one progress.Write BEFORE the rsync (exec.go:703). Startup path (recoverFromFlag service.go:1720 → recoveryRollback :2135 → rollback :4649 → restoreDatabase :4777) has ZERO ticker → watchdog kills ~120s into the restore. Execute path (postSwapFailure :3675 → rollback, gated ticker still armed) closes its gate after 3 min of rsync silence (watchdog.go:134) → killed too. The flag is removed only AFTER the restore completes, so a mid-restore kill → next boot → restore FROM SCRATCH → killed again = indefinite restore loop (the rune-wedge shape) on the recovery path itself. Norway 32 GB: a >120s restore is essentially guaranteed.

FOUR startup entries funnel into the same chokepoint: the Resuming/PreSwap latch (:762/:829), recoverFromFlag ground-truth failures (:889/:908/:922/:1042), completeInProgressUpgrade ground-truth failure (:2271), resumePostSwap stale-flag binary-skew. One fix covers all.

THE FIX: an always-ping watchdog ticker (runGatedWatchdogTicker, nil progress — the exact 012 primitive) wrapping the BODY of rollback() — covers the restore AND the equally-silent rollback-docker-up (5m, onAdvance=nil); raise the 10-min rsync timeout (exec.go:704) to a shared generous constant (the MigrateUpTimeout=30m philosophy); repair the comments in the same commit; add a source-order guard test (TestBootMigrateWatchdogCover_SourceOrder style).

THE PROOF: the 012 protocol — RED scenario (stall/slow the restore during startup recovery) on unfixed code → King ratifies → fix → GREEN. ~2 VM-hours, ~€0.015.

ALSO CLEARED BY THE SWEEP (no work, recorded for honesty): every other step from process start to the first main-loop heartbeat is covered or bounded. Three LOW non-wedge liveness nits (initial-discover network blackhole ≤5m cap; wedged-dockerd resume probes ≤2m caps; pruneBackups RemoveAll on a rare path) — environmental, self-healing, no destructive rework; fix only if the King asks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 King ratifies the fix design in this description (ticker wrap at rollback(), shared restore timeout, comments, guard test)
- [ ] #2 RED observed on a real VM: restore stalled during startup recovery → watchdog kill on unfixed code (NRestarts delta ≥1 from post-stall baseline / Result=watchdog)
- [ ] #3 Fix landed: always-ping ticker wraps rollback(); restore timeout raised to the shared constant; comments repaired; source-order guard test added
- [ ] #4 GREEN on a real VM: same stall, NRestarts delta=0, rollback completes, data intact, flag absent
- [ ] #5 RED→GREEN pair recorded here with run IDs/VM names
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Design + sweep ledger deep-reference: STATBUS-036 (the campaign roadmap, Track A1/A2 — doc-007 was folded into it); this ticket is self-sufficient. Status: awaiting King ratification of the fix design, then RED→fix→GREEN per the 012 protocol.

⚠️ CRITICAL COUPLING — 031 MUST NOT LAND WITHOUT THE STALE-BACKUP GUARD (architect, 2026-06-12, from the rune wedge → STATBUS-039). 031's always-ping ticker lets a slow restore COMPLETE instead of dying mid-rsync. For a CURRENT backup that is exactly the goal. But if the backup is STALE (older than live data — e.g. rune's May-25 backup vs ~2.5 weeks of live data): HEAD-as-is kills the uncovered restore mid-rsync = a DETECTABLE corrupted volume; 031's ticker ALONE would let the stale restore COMPLETE = a CONFIDENT, silent ~2.5-week data loss with a green rolled_back row. So the stale-backup guard at rollback() (refuse to restore a backup older than live data) is a PRECONDITION of 031's cover, not an extension. SEQUENCING: 031 ships TOGETHER with the stale-backup guard (designed under STATBUS-039); it must not be merged/deployed alone. The gate-batch (STATBUS-036) reflects this coupling.
<!-- SECTION:NOTES:END -->
