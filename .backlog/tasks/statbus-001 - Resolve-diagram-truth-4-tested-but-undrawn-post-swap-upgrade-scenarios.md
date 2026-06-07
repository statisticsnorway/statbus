---
id: STATBUS-001
title: >-
  Refine grouped post-swap TEST-notes in upgrade-timeline.plantuml (sharpen
  invariants; fix watchdog-reconnect note)
status: Done
assignee:
  - architect
created_date: '2026-06-07 11:24'
updated_date: '2026-06-07 14:49'
labels:
  - install-recovery
  - diagrams
  - upgrade
dependencies: []
references:
  - test/install-recovery/scenarios/3-postswap-archivebackup-resume.sh
  - test/install-recovery/scenarios/3-postswap-between-migrations-kill.sh
  - test/install-recovery/scenarios/3-postswap-migrate-killed-after-commit.sh
  - test/install-recovery/scenarios/3-postswap-watchdog-reconnect.sh
documentation:
  - doc/diagrams/upgrade-timeline.plantuml
  - doc/diagrams/install-recovery.plantuml
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architect analysis (tmp/architect-001-diagram-truth.md) corrected the premise: all four post-swap scenarios are DISTINCT and already drawn — grouped into shared TEST-notes in upgrade-timeline.plantuml (~lines 139-147), correctly absent from install-recovery.plantuml. NONE redundant; none retire/merge. The migrate-loop trio (mid-migration-kill / between-migrations-kill / migrate-killed-after-commit) are the 3 cells of the commit-vs-record atomicity boundary — distinct recoveries (migrate-killed-after-commit is the real rune wedge: forward fails 'relation already exists' -> restore -> rolled_back).

So this is NOT coverage-addition — it's note CLARITY + CORRECTNESS. Keep scenarios grouped by shared code anchor; sharpen per-scenario invariant lines rather than splitting into more notes. Proposed replacement text in tmp/architect-001-diagram-truth.md §1-4.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 watchdog-reconnect note corrected to match landed code (service.go:3801-3821): the WATCHDOG ticker keeps the unit alive; a true >5min hang is reaped by connect()'s ctx, NOT the watchdog. The misleading 'watchdog fires on a hung reconnect' framing is removed
- [x] #2 archivebackup-resume note states the invariant it actually proves (exit-42 RESUME path + READY=1-before-recoverFromFlag + UPDATE-before-tar), no longer assuming the resume is active-phase
- [x] #3 migrate-loop trio shared note makes each of the 3 commit-vs-record cells' distinct invariant legible
- [x] #4 happy spine stamped with a baseline coverage note: 0-happy-install (install-recovery.plantuml spine) and 0-happy-upgrade (upgrade-timeline spine)
- [x] #5 upgrade-timeline.plantuml re-rendered to SVG; architect reviews the final notes for correctness before commit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Premise corrected (2026-06-07): the 4 are NOT undrawn. In upgrade-timeline.plantuml they appear GROUPED into shared TEST notes with siblings (~lines 139/144/146); they are correctly absent from install-recovery.plantuml (upgrade-sequence events, not install-state events). Real question per scenario: DISTINCT interaction point (deserves its own note) vs REDUNDANT (merges into a drawn sibling → retire/merge the test). Architect investigating; will report findings + a recommended re-scope of this task.

Architect verdict (2026-06-07, tmp/architect-001-diagram-truth.md): all 4 DISTINCT, none retire. Found a diagram-truth BUG in the watchdog-reconnect note (states a failure the landed code doesn't have). Re-scoped from 'add undrawn/retire' to 'refine grouped notes'. Engineer to apply the proposed note text (working tree, no commit); architect to review; King sees the diff before commit.

Execution churn (2026-06-07): engineer applied + code-verified the notes well, but a crossed foreman stand-down reverted them (tree clean again). Re-dispatched to ARCHITECT to apply its own findings directly (per King's no-relay principle), folding in the engineer's 2 verified sharpenings. No commit; King reviews diff before commit.

Committed as 3da43c3d3 (2026-06-07): 4 files (+33/-9), SVGs re-rendered by the pre-commit hook. Architect authored the notes directly, verified against landed code (corroborated by the engineer's earlier independent code-check + foreman diff review). Old buggy watchdog text confirmed gone from source + SVG. Done.
<!-- SECTION:NOTES:END -->
