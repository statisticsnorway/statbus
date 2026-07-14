---
id: STATBUS-181
title: >-
  attempts-survive-restore: re-impose recovery_attempts onto the terminal row
  after a volume-rewind restore
status: Done
assignee: []
created_date: '2026-07-14 13:15'
updated_date: '2026-07-14 15:40'
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
- [x] #1 Pre-stop row read captures recovery_attempts on both rollback and re-attempt paths; writeRollbackTerminal re-imposes it
- [x] #2 The restore-broke-reattempt arc re-adds the final-row attempts assert (=3) and goes green on a real VM run (shared run with 180's oracle)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-14 14:02
---
PHASE (ii) CONSTRUCTION RULED (architect, 2026-07-14; recorded here because the arc under extension is this ticket's — foreman may relocate). The foreman's reframe was the right move and it goes one step further than his (B): the ruled construction is (C) — V_fail × C9 × branch-deletion — which reaches the git-corrupt ABORT through the DIRECT rollback arm, uses only run-proven machinery, and needs neither the mid-tx stall nor the unexplained phase timing.

THE CONSTRUCTION (every leg verified in code this session):
1. Target = commit B (failing delta; already in the arc lineage). Arm C9 (`inject.KillHere("killed-by-system-during-builtin-rollback")`, service.go:7177, registered inject.go:162, proven by scenario 4-rollback-kill) before dispatching.
2. Deterministic natural sequence: swap → exit-42 → resumeNewSb stamps new-sb-upgrading (:6635) → delta runs → V_fail RAISEs → observed state = POSITIVELY-Behind (DB up, migrations short of on-disk max) → rollback. Classification ambiguity is immaterial: BOTH handlers route positively-Behind identically — newSbUpgradingFailure (obsState==CannotReachNew → d.rollback, verified) and parkForDeterministicFailure ("positively-Behind → data-safe rollback", park only on at-target/unverifiable).
3. First rollback: restoreGitState SUCCEEDS (branch alive) → restoreDatabase restores the old volume → C9 kills the PARENT. Dead window achieved: flag present (phase=new-sb-upgrading, Step frozen=StepRollback), parent dead, db container stopped, volume=old — C9's own header documents exactly this recovery contract.
4. In the window: the arc DISARMS C9 (one-shot hygiene; even armed, the ABORT pass exits at restoreGitState before reaching C9) and DELETES the branch.
5. Next dispatch (./sb install): crashed-upgrade → runCrashRecovery → EnsureDBReachable fails → StartDBForRecovery (existing container, install_upgrade.go:262-269) → RecoverFromFlag → upgrading branch → observed state on the restored OLD volume = confirmed-behind → recoveryRollback → rollbackResumeIsTerminal(Step=StepRollback, PriorDeathStep=earlier) = FALSE ("the first rollback resume stays free by construction") → d.rollback → restoreGitState → branch GONE → ABORT: LabelFailedAbort terminal.
6. ORACLE: state=failed + the ABORT label/log + bundle emitted + flag disposition per the ABORT branch + read-only/maintenance left ON per F1(i) — AND recovery_attempts on the ABORT row per THIS ticket's fresh machinery (the ABORT write now carries the re-imposed value; asserting it gives 181's second consumer its run-proof for free).

THE FOREMAN'S THREE QUESTIONS:
Q1 (does the mid-tx stall engage on V_fail): MOOT — the ruled path uses no mid-tx machinery. For the record, (B)'s two latent hazards: the stall RE-ENGAGES on the resume pass unless disarmed mid-arc, and stall-before-RAISE ordering inside one delta needs guaranteed migration timestamps. Resolvable, but pure liability next to (C).
(Q2) map-row intent: dissolved — (C) exercises the DIRECT arm (upgrading + Behind → recoveryRollback → rollback), so we never have to settle for (B)'s forward-resume-fails story.
(Q3) the swapped-pre-delta mystery: dissolved as load-bearing. Plausible-UNVERIFIED explanation for the record: the r12 boot-window hoist — on run 28980487041's transport the delta likely ran in the BOOT catch-up BEFORE recoverFromFlag dispatched resumeNewSb, so the kill predated the upgrading stamp. Post-145 the boot catch-up is floor-bounded, so the target delta can no longer run there — meaning that construction's observed behavior may not even reproduce on HEAD: a third independent reason not to build on it. Not a product bug either way (a swapped-armed resume forward-re-runs the delta; restart-safe, arc-proven). If the mystery ever needs settling, it is one HEAD re-run of the postswap-mid-tx arc reading the flag phase — file only if someone needs it.

POST-SHIP AMENDMENT to e269b39a1 (one comment line, rides the mechanic's next service.go touch): the new rollback() capture comment says "restoreDatabase below (via restoreAndFinalize, or directly in the ABORT branch)" — the ABORT branch runs NO restoreDatabase (it fires on restoreGitState failure, BEFORE any DB restore; verified — no restore call in that branch). The ABORT site re-imposes attempts as a same-value no-op for SQL-shape uniformity, not for rewind protection; the clause should say so, or a future reader will believe the ABORT path rewinds the DB.
---

author: architect
created: 2026-07-14 14:16
---
CORRECTIONS to comment #1 (architect, 2026-07-14; both premises refuted by the mechanic's pre-build verification, confirmed by my own re-read — the ruled construction, oracle, and terminals are UNCHANGED):

1. The POST-SHIP AMENDMENT paragraph is WITHDRAWN. The ABORT branch DOES call restoreDatabase directly (service.go:7479-7482, commit 7c86b383e: restore the DB first so on-disk state is consistent — old DB + old code is recoverable, new code + old DB is not — then ABORT before compose up). The shipped comment was correct as written. My absence claim came from a span grep anchored on guessed line offsets that started BELOW the call — my error. Consequence is positive: the ABORT-site attempts re-impose is genuinely REWIND-PROTECTIVE, so all four writeRollbackTerminal sites are load-bearing.

2. Step-3/5 intermediates corrected: recordRollbackCommit fires only on the recoveryRollback path (:2751), never on the direct d.rollback call sites (:5127/:5149/:5182) — so after the C9 kill, flag.Step is the frozen migrate-up step, NOT StepRollback. Dispatch-2 route (per foreman/mechanic, code-confirmed): RecoveryBudgetGuard (no StepRollback defer) → resumeEscalation → recoveryContinue → boot-migrate no-op beat → confirmed-Behind → recoveryRollback → rollbackResumeIsTerminal trivially false → recordRollbackCommit NOW stamps rollback → d.rollback → branch gone → ABORT. Same terminal; recovery_attempts on the ABORT row = 1 (one counted recovery pass, re-imposed across the ABORT's own rewind) — the arc's attempts assert should expect 1.

The mechanic builds on the corrected intermediates; run 3 is the oracle.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
recovery_attempts now survives the volume-rewind restore on every terminal-write path: writeRollbackTerminal re-imposes the pre-stop-captured value alongside state/error at all four call sites (both restore paths capture before any destructive step; commit e269b39a1). Run-proven on a real VM in arc run 29344519124: phase (i) final row attempts=3 after the re-attempt's rewind, phase (ii) ABORT row attempts=1 across the ABORT's own restore — both consumers of the fix asserted in one run. Root cause was the architect's volume-rewind trace (the value was never UPDATEd away; the snapshot restore physically reverted it and the terminal UPDATE re-imposed only state/error). En route the same arc proved the whole STATBUS-111 re-attempt story: pair-terminal + immediate in-dispatch re-attempt to a byte-identical rolled_back, and the still-corrupt-git refusal before any destructive step.
<!-- SECTION:FINAL_SUMMARY:END -->
