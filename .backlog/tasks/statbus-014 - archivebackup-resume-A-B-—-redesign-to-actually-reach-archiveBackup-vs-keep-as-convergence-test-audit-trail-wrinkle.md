---
id: STATBUS-014
title: >-
  archivebackup-resume: A/B — redesign to actually reach archiveBackup vs keep
  as convergence test (+ audit-trail wrinkle)
status: To Do
assignee: []
created_date: '2026-06-08 02:11'
labels:
  - install-recovery
  - recovery
  - needs-king-decision
dependencies: []
references:
  - test/install-recovery/scenarios/3-postswap-archivebackup-resume.sh
  - cli/internal/upgrade/service.go
priority: medium
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Surfaced during the archivebackup-resume diagnosis (architect). rec-2 (commit 4f6f48f14) makes the scenario PASS by relaxing the strict NRestarts=0 to a bounded check (delta>=3 = real restart loop → fail; the verified delta=1 rollback-then-recomplete → pass) with the final-state contract still asserted (row=completed sh:464, data intact sh:470). So archivebackup-resume is GREEN as a convergence test. Two deeper items for the King:

1. A/B STRUCTURAL — the scenario's INTENDED coverage was the watchdog keeping the unit alive DURING a stalled archiveBackup tar. But the kill-mid-applyPostSwap + resume path does rollback-then-recomplete, and the row reaches 'completed' BEFORE the (still-stalled) archiveBackup — so the tar's watchdog coverage isn't actually exercised.
   - Option A (architect's rec): redesign so the scenario genuinely reaches + stalls archiveBackup with the row still in-progress (tests watchdog-during-tar as intended).
   - Option B: accept it as a convergence test (current rec-2 state) and reframe its intent narrative (title, EXPECTED-BEHAVIOR, Phase-6 / GREEN-check comments) to match.
   The architect deliberately LEFT the intent-narrative untouched (with breadcrumbs to tmp/architect-archivebackup-resume-diagnosis.md) pending this decision — to avoid throwaway work + pre-empting the call.

2. MINOR PRODUCT WRINKLE — markCurrentVersionCompleted flips a rolled_back row → completed, clearing the audit trail of the intermediate rollback. Guarded by ground-truth (self-upgrade artifact); NOT a wedge or data loss. But the rollback→recomplete cycle ends up looking like a clean completion (the rollback audit trail is lost). Decide: preserve the rollback audit trail, or accept the flip.

Full diagnosis: tmp/architect-archivebackup-resume-diagnosis.md. Neither item blocks the scenario going green via rec-2.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 King decides A (redesign to reach archiveBackup) vs B (convergence test + reframe narrative)
- [ ] #2 If A: scenario reworked to stall archiveBackup with row in-progress + watchdog-during-tar asserted
- [ ] #3 If B: scenario title/EXPECTED-BEHAVIOR/Phase-6 comments reframed to convergence (remove the misleading watchdog-during-tar intent)
- [ ] #4 Decide whether markCurrentVersionCompleted should preserve the rolled_back audit trail
<!-- AC:END -->
