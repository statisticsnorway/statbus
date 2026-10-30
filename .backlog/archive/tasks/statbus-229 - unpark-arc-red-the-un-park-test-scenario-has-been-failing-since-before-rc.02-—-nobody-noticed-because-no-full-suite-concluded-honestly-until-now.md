---
id: STATBUS-229
title: >-
  unpark-arc-red: the un-park test scenario has been failing since before rc.02
  — nobody noticed because no full suite concluded honestly until now
status: Done
assignee: []
created_date: '2026-08-18 10:37'
updated_date: '2026-08-19 00:02'
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
- [x] #1 Trace AFTER the 228 fix lands: reproduce at the fixed code, then root-cause with file:line — product refusal wrong vs scenario assertion stale
- [x] #2 Fix or ruled scenario correction landed via the standard review gates
- [x] #3 Scenario green at a full suite
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

author: engineer
created: 2026-08-18 12:06
---
**BUILT to the ruling, FROZEN for review (no commit).** Files: `cli/internal/upgrade/service.go`, `cli/cmd/install_upgrade.go`, new `cli/cmd/unpark_retreat_test.go`, plus three amended test files (all listed below). AC#2's code is here; AC#3 rides the next suite.

**(1) 210 STOPS BLANKING THE PHASE.** New field `UpgradeFlag.RetreatedToSourceAt *time.Time` (service.go, struct + `HasRetreatedToSource()` helper). `parkServiceRecovery`'s success arm now records the retreat there and leaves Phase alone. Its comment carries the ruling's reasoning verbatim: the phase vocabulary describes POSITIONS INSIDE an in-flight upgrade, so after a completed retreat every value is a lie, and 210 borrowed one that already meant "died before the swap" — two states on one wire value, with the unconditional rollback at :1341 arriving on schedule.

**(2) THE UN-PARK REMOVES THE FLAG when the marker is set** — `cmd/install_upgrade.go`, beside `ClearFlagStepHistory`, AFTER the successful un-park and BEFORE `RecoverFromFlag`. New `(*Service).RemoveFlagAfterRetreat()` acquires the flock before unlinking (the caller's quiesced-unit contract is proven, not assumed) and **REFUSES a flag without the marker**, so the decision cannot be made accidentally by a caller that skipped the check.

**(3) FIELD-ABSENT BEHAVIOUR UNCHANGED**, including `ClearFlagStepHistory`. The comment says why in the imperative — "CONDITIONAL, AND THE CONDITION IS LOAD-BEARING — DO NOT SIMPLIFY THIS TO AN UNCONDITIONAL REMOVE" — with the era-refused park spelled out.

**(4) THE 228 PIN EXTENSION — AND IT FOUND SOMETHING.** New `TestEveryBackupPathWriterIsAccountedFor_STATBUS229` enumerates EVERY writer of `flag.BackupPath` in production sources and requires each to be a known one with a stated reason, so a new writer fails until justified. Running it surfaced a **third** PreSwap+BackupPath pairing I had not seen: `completeInProgressUpgrade`'s flagless-recovery synthesis (:3183). It is legal — the record goes straight to `recoveryRollback` and is never persisted, so `recoverFromFlag`'s classifier never sees it — and the pin now asserts exactly that property, so persisting it later fires the alarm. A fourth site (`parkAtTarget`, :3235) pairs BackupPath with `PhaseNewSbSwapped` and IS persisted: legal, because the invariant only forbids the PRE-SWAP pairing.

**I had to correct my own pin mid-build, which is worth recording:** its first version asserted the SHAPE ("every synthesized flag must be handed to recoveryRollback") and wrongly flagged `parkAtTarget`. The invariant is about the PHASE, so the pin now reads each literal's Phase field and only demands in-memory-only treatment for the PreSwap ones. A pin that fires on a legal shape would have been argued away within a week.

**ORACLE ARMS — status per arm:**
- `TestUnparkRemovesFlagOnlyWhenRetreated_STATBUS229` (call site: conditional, ordering, ClearFlagStepHistory preserved): **RED-verified** — reverting the un-park block fails it.
- `TestParkServiceRecovery_TruthRestoresFlag_STATBUS210` (amended): **RED-verified** — restoring 210's `f.Phase = PhaseOldSbUpgrading` fails it, and it now also asserts `f.Phase` is NOT written at all.
- `TestRemoveFlagAfterRetreat_RemovesOnlyAMarkedFlag_STATBUS229` (behavioural, both outcomes on a real on-disk flag): RED-by-nonexistence against pre-229 code — the method does not exist, so the package would not compile. Strongest possible RED, but it cannot be demonstrated as a test failure; stating that rather than claiming a clean red.
- The extended BackupPath pin: not RED against today's tree by construction — it is the "no further producer" proof, and its value is the next writer, not this one.

**AMENDED PINS/COMMENTS, listed explicitly as required:**
- `park_service_recovery_test.go` — `TestParkServiceRecovery_TruthRestoresFlag_STATBUS210` re-pointed at the marker; header states 210's SURVIVING invariants (success-arm only, BackupPath kept, refusal/failure arms untouched) and what 229 changed.
- `park_flag_hold_test.go` — **two of MY OWN 212 arms were still passing while asserting a rewrite production no longer performs.** Re-pointed at `RetreatedToSourceAt`, renamed `..._RewritesPhaseOnDisk_...` → `..._RecordsRetreatOnDisk_...`, and they now additionally assert Phase is UNCHANGED. That is the same stale-claim class this whole day has been about, in my own tests.
- `service.go:6023+` — 210's rewrite comment fully replaced with the truthful account.

**Verification:** `go test ./...` in cli/ — 12 packages ok, 0 failures. `golangci-lint` 2.12.2 — 0 issues. `gofmt -l` — clean (it flagged my new pin once; fixed before freezing, the third time this week gofmt caught what lint did not).

**Nothing in the ruling was ambiguous enough to need a judgment call I did not report above.**
---

author: foreman
created: 2026-08-18 12:10
---
LANDED at 32e1b33b1, architect-approved with no amendment (his verdict message; both design additions judged improvements — including a THIRD guard nobody flagged: RemoveFlagAfterRetreat refuses a flag whose Holder != HolderService, so a mis-sequenced call can never delete install's own mutex). AC#1 (trace) and AC#2 (fix landed via the gates) closed. AC#3 (scenario green at a full suite) rides the King's cut — with the standing expectation that a runtime-stability health-check failure there is the OLD chronic issue surfacing as its own ticket, not this fix failing. The pin's one remaining door (Phase-writer coverage) is STATBUS-232, Low, architect-filed.
---

author: architect (relayed by foreman)
created: 2026-08-18 14:46
---
PRE-VERDICT CALIBRATION, pinned before the rc.04 chain concludes so it is not worked out at 3am: if this scenario fails at runtime-stability, the known-old-cause diagnosis decides WHICH TICKET gets the failure — it does NOT make the suite pass. A red arc means the arc gate refuses and there is no promotion by default. A KNOWN CAUSE IS NOT A PASS; never promote over a SKIP (SKIP_UPGRADE_ARCS exists for provider outages, not for a red we have grown used to). Honest paths on that failure: diagnose and fix the chronic issue then re-cut, OR the King rules explicitly — knowingly, scenario named, risk stated, reasoning recorded here — that this specific failure does not block THIS promotion. His call, never inherited from a sweep. And no coin-toss re-runs: a chronic issue without a root cause is a bug with a low reproduction rate; a second run's green is not evidence.
---

author: foreman
created: 2026-08-18 20:17
---
Status corrected To Do → In Progress (King's catch): the fix landed at 32e1b33b1 and is on the rc.05 tag under test right now — observation phase, not untouched work. AC#3 closes on the running suite's verdict.
---

author: foreman
created: 2026-08-19 00:02
---
AC#3 CLOSED at rc.05 (arc run 32187511838, engineer-verified in the logs): un-park-to-completion GREEN on the first live execution of the fix — real disk-shortfall park (row id=2, exactly one parked siren, zero rollbacks, daemon alive-idle), real un-park, the SAME row ran forward to completed, ZERO restores, data intact. The 210 blanked-phase → unconditional-rollback chain is dead; the granted fresh attempt is genuinely consumed going FORWARD. The timeline-anomaly condition from the ruling (comment #3) is also satisfied: the old 2026-08-02 failure was resolved as a DIFFERENT mechanism (health-check timeout, foreman comment #2, operator log on file) — no second bug wearing this message is being buried by this closure. The pre-verdict calibration (comment #6) was not needed: the scenario did not fail at runtime-stability; it passed outright.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The un-park path — an operator deliberately releasing a parked upgrade for one fresh attempt — was being sabotaged by the product itself: STATBUS-210's park restoration expressed "retreated to source" by blanking the flag's Phase to a value that already meant "died before the swap", so recovery routed the granted attempt into an unconditional rollback and a DB restore that rewound the recovery budget. The ruled fix gave the state its own name (RetreatedToSourceAt) instead of a borrowed one, made the un-park remove the flag only when that marker is set (the era-refused park keeps its truthful flag — load-bearing conditionality), and extended the BackupPath-writer pin to every producer. Proven live at rc.05: a real resource park, a real un-park, the same row run forward to completed with zero restores and data intact. The old 2026-08-02 failure was separately resolved as a different mechanism (health-check timeout), so no second bug is buried by this closure. Diagnosed and built by engineer, ruled and reviewed by architect, landed as 32e1b33b1.
<!-- SECTION:FINAL_SUMMARY:END -->
