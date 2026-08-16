---
id: STATBUS-210
title: >-
  unpark-rollback-collision: the un-park grants a fresh attempt, then flag-based
  recovery classifies the same row cannot-reach-new and rolls it back
status: In Progress
assignee:
  - engineer
created_date: '2026-08-16 22:29'
updated_date: '2026-08-16 22:59'
labels:
  - upgrade-recovery
  - release
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/cmd/install.go
  - test/install-recovery/arcs/un-park-to-completion-arc.sh
  - doc/upgrade-recovery-model.md
priority: high
ordinal: 210000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: `./sb install` on a parked row un-parks it for ONE fresh attempt that runs to completion (STATBUS-159/111 contract); recovery never destroys the attempt it just granted.
> FOUND: overnight arc triage 2026-08-17, v2026.08.0-rc.01 arc run 31970534502, un-park-to-completion (job 95222618650) — genuine product failure, ran post-stampede (17 min real execution, codeonly fixture lineage — NOT the crollback-image defect).

SEQUENCE (from the arc's captured install output, timestamps 22:22-22:23): row id=2 parked on disk-full ("4 GB free < 5 GB needed before image-pull"); the arc frees the disk (30 GB), operator-triggers `./sb install`. Install detects crashed-upgrade (flag present, flock free), quiesces the unit SIGKILL-class, then: "crash recovery: UN-PARKED upgrade id=2 — ./sb install grants ONE fresh attempt with a reset budget" — CORRECT so far. Then immediately: "Recovering an interrupted upgrade — found a service marker for ca74bb57" → resume classifier: "binary commit 5d141d3c != row target ca74bb57 and is not its descendant (upgrade crashed before binary swap)" → observed-state=cannot-reach-new → "UPGRADE_DIED_DURING_RESUME ... rolling back" → full rollback with DB restore, exit 75. The arc expected exit 0 (the fresh attempt completes with the disk freed).

THE DEFECT SHAPE: after un-parking, the row (in_progress, service flag marker still naming target ca74bb57) is indistinguishable to the flag-based recovery classifier from a crashed mid-flight upgrade — so instead of DISPATCHING the granted fresh attempt, RecoverFromFlag's classification rolls the row back and destroys the un-park's intent. Open design questions for the architect (recovery-semantics core — his ruling, possibly the King's morning word if it touches the ratified park/un-park contract): should the un-park clear/rewrite the flag phase marker so recovery re-dispatches instead of classifying? Should the un-park path bypass the resume classifier entirely and go straight to executeUpgrade for the row? Is cannot-reach-new even correct here (the binary at 5d141d3c is the SOURCE, the row target ca74bb57 is a FIXTURE branch commit — descendant checks can't apply to fixture lineages, but that's the arc's realism, not an excuse)?

This is also STATBUS-200's AC#2 observation arc — that criterion stays open pending this fix.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling on the un-park→dispatch path: how the granted fresh attempt survives the flag-based recovery classifier (clear/rewrite marker, bypass classifier, or reclassify) — within or explicitly escalating the ratified park contract
- [ ] #2 Fix landed: un-park → the SAME row runs its fresh attempt to completion; recovery never rolls back a row it just un-parked
- [ ] #3 un-park-to-completion green at an RC tag (also closes STATBUS-200 AC#2)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-16 22:33
---
RULING (architect, overnight; recovery-semantics core — ruled within ratified doctrine, flagged in the King's morning brief with his veto open). ROOT CAUSE NAMED: this is an INTERACTION REGRESSION from STATBUS-200's own restoration, caught by exactly the arc that guards this contract. parkServiceRecovery now returns a permitted parked box to its PRE-SWAP reality — source git, source binary (restoreBinary), source config — so the box serves while parked. But the service marker still records the DEAD attempt's post-swap phase. The marker lies about the box. The classifier then read the lying marker's world honestly (binary 5d141d3c ≠ target ca74bb57 → cannot-reach-new) and rolled back the row the operator had just deliberately un-parked — the exact opposite of the un-park contract's 'one fresh attempt'.

THE FIX — TRUTH-RESTORATION AT THE WRITER, not special-casing the readers: on SUCCESSFUL source-service restoration (the era-permitted arm only), parkServiceRecovery updates the held flag via mutateHeldFlag: Phase → PhaseOldSbUpgrading, BackupPath KEPT (it is the same attempt's snapshot identity — 197's key still holds). The marker then describes the box again — died-before-swap semantics — and every existing reader works unchanged: the un-park fresh attempt re-runs from the swap forward (checkout → swap → resume → completion — exactly the contract's promise), crash recovery classifies truthfully, the parked-skip invariant is untouched.

REJECTED: (i) classifier bypass for a just-un-parked row — patches a reader to tolerate a lying writer; every OTHER reader (crash recovery on a parked box, the flagless belt after flag loss) would still be lied to. (ii) Reclassification — the classifier was RIGHT about the world it was shown. CONSISTENCY CHECK, all arms: era-REFUSED parks (delta applied, at-target health parks) get no restoration → no rewrite → marker already truthful → behavior unchanged. Restoration FAILURE → no rewrite (box state unproven — the marker must not claim pre-swap reality that wasn't achieved); narrative already records the failure per 200 Q3.

ORACLES: RED-first unit — successful restoration ⇒ flag phase rewritten to old-sb-upgrading with BackupPath preserved; refusal and failure arms ⇒ flag byte-untouched; the un-park-to-completion arc UNCHANGED green at rc.02 (this is also 200 AC#2's observation arm). DOCTRINE STATUS: the marker-describes-the-box rule is ratified (recoverFromFlag's phase dispatch depends on it); 200 broke compliance, this restores it — no contract text changes.
---

author: engineer
created: 2026-08-16 22:59
---
BUILT per comment #1 (truth-restoration at the writer), FROZEN for review. Files: cli/internal/upgrade/service.go + cli/internal/upgrade/park_service_recovery_test.go — both primary lane, built on 209's landed baseline (8b58e533c).

THE EDIT (parkServiceRecovery, on the era-permitted SUCCESS arm only, right after restoreSourceServices returns nil): `d.mutateHeldFlag(func(f *UpgradeFlag) { f.Phase = PhaseOldSbUpgrading })` — rewrites the held flag's Phase to old-sb-upgrading (died-before-swap semantics) with BackupPath KEPT (only Phase is assigned; 197's snapshot-identity key holds). Best-effort: a mutateHeldFlag failure logs a Warning (a stale marker is reconciled by the next re-trigger), never fails the restoration. The two OTHER arms are untouched by construction — the era-refuse arm (appendParkNarrative(id, refusal) → return) and the restoration-failure arm (appendParkNarrative(...) → return) both return BEFORE this rewrite, so the flag is byte-untouched: a refused park's marker is already truthful, and a failed restoration must not claim a pre-swap reality it didn't achieve.

WHY THIS FIXES THE COLLISION: after 200's restoration the box is at pre-swap reality (source git+binary+config) but the marker still said post-swap → the classifier honestly read binary(source) != row-target → cannot-reach-new → rolled back the just-un-parked row. The rewrite makes the marker DESCRIBE THE BOX again → recovery re-runs the fresh attempt from the swap forward (checkout → swap → resume → completion, the un-park contract's promise), and every reader works unchanged. No reader patched, no reclassification (both rejected on this ticket).

FLOCK NOTE (recorded, not a blocker): the arc's path is the disk-full StepImagePull park → parkForDeterministicFailure, reached from applyNewSbUpgrading which holds the flock throughout (precondition service.go:~5840), so mutateHeldFlag succeeds there. At the budget-park sites (204: RecoveryBudgetGuard releases the flock before calling parkServiceRecovery; resumeNewSb) the rewrite is best-effort — mutateHeldFlag returns 'no flag file held' → the Warning fires. Those sites are not the arc's path and the ruling scopes the rewrite to 'the held flag'; flagging for awareness, not expanding scope.

ORACLE (RED-first, structural): TestParkServiceRecovery_TruthRestoresFlag_STATBUS210 — the rewrite (a) exists via mutateHeldFlag setting Phase=PhaseOldSbUpgrading, (b) KEEPS BackupPath (asserts f.BackupPath is never assigned), (c) is on the SUCCESS arm (follows restoreSourceServices AND the era-refuse return), so refusal/failure arms leave the flag untouched. PASS. The un-park-to-completion arc UNCHANGED is the live proof at rc.02 (also closes STATBUS-200 AC#2).

VERIFY: go build ./internal/upgrade OK; vet OK; gofmt clean (both files); the 210 oracle + the full park/rollback/recovery/209/204/197/read-only structural sweep PASS. No commit — frozen for the architect's frozen-diff review. AC#3 = un-park-to-completion green at rc.02 (VM, post-commit).
---
<!-- COMMENTS:END -->
