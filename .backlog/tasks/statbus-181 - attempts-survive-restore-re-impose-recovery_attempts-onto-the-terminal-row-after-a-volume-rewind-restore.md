---
id: STATBUS-181
title: >-
  attempts-survive-restore: re-impose recovery_attempts onto the terminal row
  after a volume-rewind restore
status: To Do
assignee: []
created_date: '2026-07-14 13:15'
labels:
  - upgrade
  - install-recovery
  - audit-trail
  - low-severity
dependencies: []
priority: low
ordinal: 182000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the recovery-attempts ledger survives the restore that concludes the story it counts — no audit-trail value is silently erased by the volume rewind.
> FOUND: arc run 29325230294 (restore-broke-reattempt run 1): B's row showed recovery_attempts=3 at the pair-terminal write, final value 0 after the re-attempt. ROOT CAUSE (architect trace, 2026-07-14, STATBUS-180 thread): not an UPDATE — restoreAndFinalize → restoreDatabase (service.go:7133, reached from ReattemptRestore ~:7386) replaces the DB volume with the pre-upgrade snapshot where attempts was 0; writeRollbackTerminal (service.go:7078) re-imposes ONLY state/timestamps/error onto the restored row. The mechanism is the 154 doctrine working (restore rewinds, terminal fact re-imposed); the CONSEQUENCE is accidental — attempts simply isn't in the re-imposed column set.
> SEVERITY: low, operationally harmless (the budget only governs in_progress rows; reschedules reset it explicitly via recoveryBudgetResetCols; the story survives in progress log + journal) — but it is audit-trail erosion, same family as the 014 self-heal error-NULLing.

FIX (architect-specified): extend the pre-stop row read ReattemptRestore already does (service.go:7332, and the original rollback path's equivalent) to capture recovery_attempts, and re-impose it in the writeRollbackTerminal UPDATE. Closes the erosion on BOTH the original-rollback and re-attempt paths.

ORACLE: the restore-broke-reattempt arc regains a final-row attempts assert (=3) alongside its existing dispatch-log "after 3 attempt(s)" check — one arc re-run proves this together with STATBUS-180's reorder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pre-stop row read captures recovery_attempts on both rollback and re-attempt paths; writeRollbackTerminal re-imposes it
- [ ] #2 The restore-broke-reattempt arc re-adds the final-row attempts assert (=3) and goes green on a real VM run (shared run with 180's oracle)
<!-- AC:END -->
