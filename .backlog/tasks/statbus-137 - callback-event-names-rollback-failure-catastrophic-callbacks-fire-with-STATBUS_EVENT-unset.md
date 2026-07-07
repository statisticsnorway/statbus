---
id: STATBUS-137
title: >-
  callback-event-names: rollback-failure/catastrophic callbacks fire with
  STATBUS_EVENT unset
status: To Do
assignee: []
created_date: '2026-07-04 22:32'
updated_date: '2026-07-07 03:46'
labels:
  - upgrade
  - operator-ux
  - product
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/cmd/install.go
  - ops/notify-slack.sh
  - STATBUS-131
ordinal: 138000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every operator callback carries a named event.
> BENEFIT: the only structured signal a headless African box emits stops arriving blank — an event stream keyed on STATBUS_EVENT (the documented integration surface) sees rollback_failed/restore_broke instead of unnamed noise it can't route or alert on.
> STAGE: Stage 1 (r17 live finding).
> COMPLEXITY: mechanic-simple — audit runCallback call sites, add the missing names, one structural test pinning "every call site passes STATBUS_EVENT".
> DEPENDS ON: nothing.

---

FOUND live in r17 (2026-07-05): the catastrophic/rollback-failure path invoked UPGRADE_CALLBACK three times with STATBUS_EVENT empty (callback log lines ' 2026-07-04T22:19:22Z' — leading space where the event name should be). The park siren correctly sets STATBUS_EVENT=parked; the rollback-failed sites set STATBUS_ROLLBACK_FAILED=1/STATBUS_ROLLBACK_ERROR/STATBUS_RECOVERY_CMD but no STATBUS_EVENT — so any operator event stream keyed on the event name (the documented integration surface, ops/notify-slack.sh) sees unnamed events. FIX SHAPE: every runCallback invocation carries a named STATBUS_EVENT — audit all call sites (grep runCallback in service.go + install.go's runInstallCallback) and add the missing names (e.g. rollback_failed, restore_broke, completed/failed as appropriate for their sites); keep the existing legacy vars for compat. Small, mechanical; a unit/structural test asserting every runCallback call site passes a STATBUS_EVENT key would pin it. Classification: operator-UX / product, medium — the siren-class alerts are the operator's only structured signal on headless boxes (see the Africa-deployment posture).
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-07 03:46
---
RIDER for this string pass (architect, pair-terminal autopsy 2026-07-07, cosmetic — not its own ticket): recoveryRollback deliberately passes restoreTargetSHA='' (STATBUS-077: the pinned pre-upgrade branch is the single source of truth, service.go:2605), and restoreGitState then logs the awkward empty-name lines 'Restoring git state to ...' and 'Ref  does not resolve, falling back to pre-upgrade'. Mechanically correct, textually confusing on every rollback log. One-liner: when the target is empty, say 'no explicit target — using the pinned pre-upgrade branch' instead of interpolating the empty string. Ride it with this ticket's callback-event-name pass.
---
<!-- COMMENTS:END -->
