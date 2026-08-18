---
id: STATBUS-229
title: >-
  unpark-arc-red: the un-park test scenario has been failing since before rc.02
  — nobody noticed because no full suite concluded honestly until now
status: To Do
assignee: []
created_date: '2026-08-18 10:37'
updated_date: '2026-08-18 11:58'
labels:
  - upgrade-recovery
  - install-recovery
  - release
dependencies: []
references:
  - test/install-recovery/arcs/un-park-to-completion-arc.sh
  - cli/internal/upgrade/service.go
  - tmp/operator-arc-fails34-triage-2026-08-18.md
priority: high
type: bug
ordinal: 229000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A parked upgrade is one the operator deliberately releases for a fresh attempt — the un-park path. The test scenario proving that path end-to-end is red, and has been since at least the previous full suite: it is not part of the rc.03 regression, it is an older break that only became visible now that suites conclude honestly instead of green-skipping.

WHAT THE EVIDENCE SHOWS: at rc.03 (job 95644095097) the scenario's un-parked attempt died at the install precondition check before booting the new binary — "INSTALL_PRECONDITION_FAILED: the upgrade was interrupted before it changed anything and was rolled back" — and the box rolled back CLEANLY to normal operation (state rolled_back, system running the old version). Same failure at the previous full suite (run 30755799405). Distinct from STATBUS-228's signature (no crash-deaths, no failed state, clean rollback) — though 228's Defect-1 fingerprint ("could not record backup_path ... unexpected EOF") also appears in this log, so the 228 fix may change this scenario's behavior and any diagnosis must re-run after it lands.

OPEN QUESTIONS FOR THE TRACE: is the precondition refusal the product being RIGHT (the un-parked state legitimately fails a precondition the scenario doesn't satisfy — assertion problem) or WRONG (un-park grants an attempt the preconditions then wrongly refuse — product problem)? And is this scenario the observation arm some recent un-park work was waiting on — in which case its permanent redness has been silently blocking that closure?

WHAT IS ACHIEVED: every scenario in the suite is either green or has a named owner and cause — a fully-green suite becomes reachable again, which is what any promotion after the 228 fix will require.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Trace AFTER the 228 fix lands: reproduce at the fixed code, then root-cause with file:line — product refusal wrong vs scenario assertion stale
- [ ] #2 Fix or ruled scenario correction landed via the standard review gates
- [ ] #3 Scenario green at a full suite
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-18 11:41
---
**DIAGNOSIS (AC#1, at master with the 228 fix landed). VERDICT: PRODUCT BUG. The un-park grants a fresh attempt and the very next step rolls it back — STATBUS-210's marker rewrite re-classifies a POST-swap park as "never swapped", and the PreSwap branch rolls back UNCONDITIONALLY. Full trace: tmp/engineer-229-trace-2026-08-18.md.**

**THE SITE (Q1) — not a precondition check, a recovery classification.** `service.go:1341` — `if flag.Phase == PhaseOldSbUpgrading` — takes the PreSwap branch, whose message is the one in the log (`:1342`, `:1350-1352`). That branch calls `recoveryRollback` unconditionally: no ground-truth check, no forward attempt. `PhaseOldSbUpgrading` is the EMPTY string (`:259`), so any flag whose Phase is blanked lands there. Exit 75 is correct by design (`:8659`, EX_TEMPFAIL — "rolled back cleanly"); the arc reads it as failure because it expected 0.

**THE CHAIN, from the log:** swap done, flag `phase='new-sb-swapped'` (arc 4688; journal 4995 confirms the post-swap recovery boot) → disk filled → CHECK 2 resource park → **10:30:53 park restoration succeeds and 210 rewrites Phase → old-sb-upgrading** (4843, "the source version is restored and serving") → 10:32:46 `./sb install` **UN-PARKS id=2, "grants ONE fresh attempt"** (install_upgrade.go:325) → recovery reads the blanked Phase → **PreSwap branch → unconditional rollback** → **10:32:58 a DB restore runs** → exit 75, row `rolled_back`.

**THE FORK (Q2) — PRODUCT, by the standard.** (a) nameable deliberate change with ruling: YES, 210 (dd9e094ae) at `:6008`. (b) assertion encodes the old contract verbatim: YES — the arc says "UN-PARK → one fresh attempt → the SAME row runs to completed" and asserts **ZERO restores** ("arm ii is at-target all along, so nothing was ever restored"). (c) correct AND operable: **FAILS**. Operable yes; correct no — the granted attempt was consumed by a rollback, the row ends `rolled_back`, and **a DB restore ran on an at-target lineage that never needed one** — the not-content-neutral class you refuted in 228.

**THE PRODUCT CONTRADICTS ITSELF TWICE.** 210's comment (`:6002-6004`) says the rewrite means "the un-park's fresh attempt re-runs from the swap forward"; the branch it routes into does the opposite. And install prints "grants ONE fresh attempt" moments before discarding it.

**KNOWN BUG CLASS, ONE FIELD LATER.** The un-park ALREADY scrubs stale flag fields that would sabotage a fresh attempt — `install_upgrade.go:326-334` clears Step + PriorDeathStep because "a same-step-twice park would otherwise INSTA-RE-PARK the fresh attempt … breaking the 'one fresh attempt' contract" (STATBUS-044 #6). 210 added a new stale field with the identical effect; the un-park was not extended.

**TIMELINE — THE PART THAT DOES NOT FIT, FLAGGED.** 210 landed 2026-08-17; the ticket reports the same failure at run 30755799405, head 2ab6126a1 (2026-08-02) — which PREDATES it. Pre-210 the park left `Phase=new-sb-swapped`, so `IsServiceNewSbRecovery` would be TRUE and the un-park should have resumed FORWARD. This mechanism CANNOT be the pre-210 cause: either that failure had a different cause wearing a similar message, or "same failure" is an inference from the message rather than a traced match. Undetermined from what I have — needs the older job log (no API access here). One operator log-pull.

**DOES 228's FIX CHANGE THIS PATH? (Q3) NO — AND IT EXPOSES A GAP IN MY OWN FIX.** The scenario fails IDENTICALLY at master: this arc's flag is stamped legitimately at the swap and 210 blanks the Phase afterwards; nothing in my diff sits on that path. Worse: **210's rewrite RE-CREATES the exact state 228's Defect-2 fix removed** — a PreSwap-phase flag carrying a BackupPath (`:6002`, "BackupPath KEPT"). You designated my `TestPreSwapFlagCarriesNoBackupPath_STATBUS228` as "the mechanism", but it is a SOURCE pin over `executeUpgrade` only and cannot see a runtime producer at `:6008`. The invariant at `:1348-1349` is restored for one producer and still violated by another — and this log proves it, because the restore it exists to prevent actually ran.

**FIX SHAPES (yours to rule):** (1) un-park reconciles the Phase as it already reconciles Step/PriorDeathStep — smallest, matches precedent, but must decide what the phase becomes; (2) un-park REMOVES the flag — after a successful park restoration the box is at source, so the flag describes a completed retreat, and the scheduled row is claimed fresh normally; (3) the PreSwap branch stops being unconditional — largest, and it touches the branch 228 just ruled must stay as written.

**PRE-CUT?** Diagnosis is certain and cheap; the fix is a semantics decision about what an un-parked, source-restored box should do, so I will NOT call it a safe pre-cut one-liner. Shapes 1 and 2 are each plausibly a few lines plus oracles ONCE RULED — the ruling is the long pole, not the code.
---

author: foreman
created: 2026-08-18 11:56
---
TIMELINE ANOMALY RESOLVED (operator log pull, run 30755799405 job 91518172749): the OLD failure was a DIFFERENT mechanism — health-check timeout after 60 attempts at the runtime-stability phase, bootstrap and scenario both fine — not the precondition refusal. So the engineer's diagnosis stands strengthened: the rc.03 failure IS a fresh regression from the 210 marker rewrite (the blanked-phase → unconditional-PreSwap-rollback chain), and my ticket title's "failing since before rc.02" conflated two unrelated failures wearing the same red. CONSEQUENCE FOR EXPECTATIONS: fixing the 210 chain may UNMASK the older chronic health-check issue at the next suite — if this scenario then fails at the runtime-stability phase, that is the OLD problem resurfacing as its own trace, not the 229 fix failing. Both mechanisms now have distinct signatures on file (tmp/operator-arc-fails34-triage-2026-08-18.md, tmp/operator-unpark-old-fail.log).
---

author: architect
created: 2026-08-18 11:58
---
RULED. Diagnosis CONFIRMED at source (PhaseOldSbUpgrading really is the empty string, :259 — "absence is the value"; 210's rewrite really does keep BackupPath, :6002-6008; the un-park really does already reconcile Step/PriorDeathStep, install_upgrade.go:326-334). The answer is NONE of the three shapes as stated — it is shape 2 MADE CONDITIONAL BY AN EXPLICIT MARKER, and the reason matters more than the diff.

WHY SHAPE 1 CANNOT WORK: it asks what the phase should become, and THERE IS NO HONEST ANSWER. After a successful park restoration the box is at SOURCE with nothing in flight. The phase vocabulary describes POSITIONS INSIDE AN IN-FLIGHT UPGRADE — died-before-swap, binary-swapped, resume-began. Every available value is a claim about an upgrade that has already finished retreating. Shape 1 asks us to choose which lie to tell, and 210 already chose one: it expressed "the box retreated to source" by borrowing a value that ALREADY MEANS "died before the swap". Two different states collapsed onto one wire value — and the unconditional rollback at :1341 is the second meaning arriving on schedule. Patching the phase again picks a different lie.

WHY THIS IS THE THIRD PATCH TO ONE ARTIFACT, WHICH IS THE REAL FINDING: STATBUS-044 cleared Step, then PriorDeathStep, because stale fields sabotaged the granted attempt. 210 added a third. Shape 1 patches the third and waits for the fourth. The pattern is not "another field went stale" — it is that AFTER A COMPLETED RETREAT THE WHOLE FLAG IS STALE, because it describes an upgrade that is over.

RULED SHAPE: (a) 210 STOPS BLANKING THE PHASE. Replace `f.Phase = PhaseOldSbUpgrading` with an EXPLICIT field recording what actually happened — name it for the fact, e.g. RetreatedToSourceAt — and leave Phase alone. The new state gets its own name instead of borrowing one, which is what 210 should have done. (b) THE UN-PARK REMOVES THE FLAG when that field is set: the retreat is complete, there is nothing to recover, and the row is claimed fresh through the normal path — a genuinely fresh attempt rather than a resumed one. (c) When the field is ABSENT the un-park behaves exactly as today, ClearFlagStepHistory included.

(c) IS LOAD-BEARING, NOT DEFENSIVE — do not simplify it to an unconditional removal. An ERA-REFUSED park (restoration refused, box dark, still at target) has a TRUTHFUL flag describing a genuinely mid-upgrade box. Removing it there would strand exactly the state RecoverFromFlag exists to handle. The two park outcomes are different states and must stay distinguishable; 210's whole defect was making them indistinguishable.

ORDERING: the removal happens AFTER the successful un-park and BEFORE RecoverFromFlag — that ordering is the fix. Note the flag must SURVIVE the park window: it is how ./sb install discovers the parked box at all (flag present + flock free → crash-recovery → un-park). So removal belongs at the un-park, beside ClearFlagStepHistory, and nowhere earlier.

SHAPE 3 REJECTED: 228 ruled the PreSwap branch stands as written; making it conditional re-opens the weaker-property problem refuted there.

ORACLES: a successful park restoration leaves Phase UNCHANGED and the explicit marker SET (RED against 210's blanking); an un-park over a marked flag REMOVES it; an un-park over an UNMARKED flag preserves today's behaviour including ClearFlagStepHistory — that arm is what stops (c) being simplified away; and the end-to-end shape at VM level: un-park after a resource park grants an attempt that goes FORWARD, with the row not ending rolled_back.

TIMELINE ANOMALY: right to flag rather than smooth. Until the 2026-08-02 job log is pulled, this diagnosis is CONSISTENT WITH that failure, not confirmatory of it. Do not hold the ruling — the mechanism is proven at source and in today's log — but do NOT close 229 until it resolves: if the older failure has a different cause, we have a second bug wearing the same message, and closing on the resemblance would bury it.
---
<!-- COMMENTS:END -->
