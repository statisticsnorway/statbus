---
id: STATBUS-031
title: >-
  startup-rollback-watchdog: recoveryRollback/restoreDatabase runs after READY=1
  with no heartbeat cover (012 sibling audit)
status: To Do
assignee: []
created_date: '2026-06-11 13:39'
updated_date: '2026-06-11 15:43'
labels:
  - upgrade
  - recovery
  - product
  - audit
dependencies: []
documentation:
  - >-
    doc-007 -
    Roadmap-completing-install-upgrade-robustness-—-Norway-rollout-then-external-standalone.md
priority: medium
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from STATBUS-012 (AC#6; flagged in doc-005, not yet traced to ground). The 012 fix established the invariant "every DB-size-scaled subprocess the service runs in the active phase executes under an explicit, bounded, always-ping watchdog cover" — boot-migrate is now covered. The suspected remaining violation: `recoverFromFlag` → `recoveryRollback` → restoreDatabase. A Norway-size pg_restore during Run() startup executes after READY=1 (watchdog armed) with, as far as inspected, no ticker armed: rollback call sites pass onAdvance=nil (service.go:4738/:4780/:4958-region) and `progress.File()` writes bypass ProgressLog.Write's heartbeat. If confirmed, a multi-minute silent restore during startup recovery is watchdog-killed mid-rollback — 012's sibling. Same fix primitive applies (runGatedWatchdogTicker, nil progress, bounded).

Scope: (1) trace every Run()-startup-reachable DB-size-scaled step before any ticker arms; (2) confirm or refute the recoveryRollback gap with line evidence; (3) if confirmed: RED scenario design (stall/large-restore inject during startup recovery) + fix per the 012 pattern. Product/recovery code — King-gated for the fix; the audit itself is read-only.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ROADMAP + SWEEP RESULT (architect, 2026-06-11, doc-007 Track A1): the Run()-startup sweep is COMPLETE — this task is the LAST uncovered DB-size-scaled step (017 ✓, 012 ✓, 031 last); King settled at the rc.01 cut that it gates the STABLE/Norway promotion. Sharpened scope: (1) FOUR startup entries funnel into the uncovered rollback chain — Resuming/PreSwap latch (service.go:762/:829), recoverFromFlag ground-truth-failure branches (:889/:908/:922/:1042), completeInProgressUpgrade ground-truth failure (:2271), resumePostSwap stale-flag binary-skew branch — all via recoveryRollback (:2135) → rollback (:4649); ONE chokepoint ticker wrapping rollback() covers everything. (2) The cover must wrap ALL of rollback(), not just restoreDatabase (exec.go:695-714, rsync, 10m cap, onAdvance=nil): the tail's rollback-docker-up (5m, onAdvance=nil) is image-scaled and equally silent. (3) Execute path is ALSO exposed: the applyPostSwap gated ticker closes at the 3-min stall threshold (watchdog.go:134) during a silent restore. (4) Secondary: raise the 10-min rsync cap to a shared generous constant (MigrateUpTimeout philosophy). Startup-tail clearance (scope item 1) is DONE — all other steps cleared with line evidence; three LOW non-wedge liveness nits folded here: N1 initial-discover network blackhole (git fetch 5m cap, kill-retry converges when network returns), N2 wedged-dockerd resume probes (2m caps), N3 pruneBackups RemoveAll on the rare belt path (filesystem-scaled). Fix+proof per doc-007: 012 pattern at the chokepoint, RED stall-restore scenario → King ratifies → fix → GREEN, ~2 VM-hours.
<!-- SECTION:NOTES:END -->
