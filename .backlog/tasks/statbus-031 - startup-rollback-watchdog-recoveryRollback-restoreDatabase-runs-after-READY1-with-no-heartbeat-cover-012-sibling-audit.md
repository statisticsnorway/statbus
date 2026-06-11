---
id: STATBUS-031
title: >-
  startup-rollback-watchdog: recoveryRollback/restoreDatabase runs after READY=1
  with no heartbeat cover (012 sibling audit)
status: To Do
assignee: []
created_date: '2026-06-11 13:39'
labels:
  - upgrade
  - recovery
  - product
  - audit
dependencies: []
priority: medium
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from STATBUS-012 (AC#6; flagged in doc-005, not yet traced to ground). The 012 fix established the invariant "every DB-size-scaled subprocess the service runs in the active phase executes under an explicit, bounded, always-ping watchdog cover" — boot-migrate is now covered. The suspected remaining violation: `recoverFromFlag` → `recoveryRollback` → restoreDatabase. A Norway-size pg_restore during Run() startup executes after READY=1 (watchdog armed) with, as far as inspected, no ticker armed: rollback call sites pass onAdvance=nil (service.go:4738/:4780/:4958-region) and `progress.File()` writes bypass ProgressLog.Write's heartbeat. If confirmed, a multi-minute silent restore during startup recovery is watchdog-killed mid-rollback — 012's sibling. Same fix primitive applies (runGatedWatchdogTicker, nil progress, bounded).

Scope: (1) trace every Run()-startup-reachable DB-size-scaled step before any ticker arms; (2) confirm or refute the recoveryRollback gap with line evidence; (3) if confirmed: RED scenario design (stall/large-restore inject during startup recovery) + fix per the 012 pattern. Product/recovery code — King-gated for the fix; the audit itself is read-only.
<!-- SECTION:DESCRIPTION:END -->
