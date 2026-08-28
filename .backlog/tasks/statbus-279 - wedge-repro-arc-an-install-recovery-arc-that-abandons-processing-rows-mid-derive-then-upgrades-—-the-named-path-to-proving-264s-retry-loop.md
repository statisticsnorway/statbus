---
id: STATBUS-279
title: >-
  wedge-repro-arc: an install-recovery arc that abandons processing rows
  mid-derive then upgrades — the named path to proving 264's retry loop
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-27 16:12'
updated_date: '2026-08-28 13:52'
labels:
  - testing
  - upgrade
  - worker
dependencies: []
priority: medium
type: task
ordinal: 272000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: STATBUS-264's retry-then-FATAL guard is recorded UNPROVEN on the release ticket (271) — no normal upgrade exercises it, because 265's exemption means the reset is never refused on any healthy path. An unproven guard needs a named path to proof, not a standing note. This arc is that path.

THE ARC, reproducing the Norway wedge's two ingredients on a real VM: (1) start derive work and stop the worker MID-DERIVE, leaving rows in 'processing' — the abandoned state the wedge was made of; (2) run the next upgrade, so the worker restarts inside the upgrade's read-only window and meets those rows. Against current binaries (264+265 both aboard since rc.10) the arc PASSES — 265's exemption means the reset is never refused and the wedge cannot form. It joins the fleet as a permanent REGRESSION arc (test/install-recovery/arcs/, one scenario in the upgrade-arc-harness matrix).

THE REQUIREMENT THAT DECIDES WHETHER IT IS EVIDENCE AT ALL (the RED rule applied to an arc): the arc must be demonstrated to FAIL at least once against a pre-265 binary (e.g. rc.09) before its green counts. A regression arc that has never been seen red proves only that it runs, not that it guards — the same vacuous-green class as a test pin that passes with the bug present.

DELIBERATELY SEPARATE from STATBUS-267 (the stuck-task detector): a detector and a reproduction are different deliverables, and bundling would make the detector wait on VM-arc work.

SEQUENCING: not release-blocking — 264+265 are aboard every candidate since rc.10 and the proving sequence does not wait on this. It queues behind the stable promotion; building it costs one arc scenario plus one deliberate red run against an old binary (paid Hetzner VM time, same as any arc).

WHAT IS ACHIEVED: the wedge class has a permanent regression arc that has been seen red, and 264's retry-then-FATAL has real-run proof instead of a recorded gap.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-28 10:04
---
ARC LANDED at b600e5797 (one file, +309; zero workflow edits — the matrix glob makes every arcs/*-arc.sh a scenario automatically, verified not assumed). TICKET STAYS OPEN AND UNPROVEN by its own rule: the arc has not yet been seen red. Design highlights on the record: determinism via a held ACCESS EXCLUSIVE lock (the derive task is made UNABLE to finish; the arc advances only on observing processing+Lock-wait, never on elapsed time); production's real trigger path (data edit → worker.log_base_change → collect_changes → derive children — verified from the live schema); the mid-build correction that decides whether the arc means anything — compose stop -t 0 instead of SIGKILL, because unless-stopped would restart the worker OUTSIDE the read-only window and silently destroy the wedge before the upgrade met it; refuses-to-pass-having-constructed-nothing (positive wedge assertion pre-upgrade); RED pre-verified against rc.09's actual bytes (bba72a4a5: no 264/265, reset failure logged and stepped past) with BASE_SHA pointing both fixture sides pre-265 so the red is honest. DISPATCH SEQUENCING, the constraint that gates the proof runs: the harness shares concurrency group hetzner-vm-fleet with the other two VM fleets (one running + one pending, a THIRD gets cancelled — the documented defect-B). rc.15's chain occupies that group now (leg 4 running, leg 5 queuing) — dispatching the RED/GREEN now could cancel the candidate's own fleet. Both runs therefore dispatch AFTER the chain completes: RED first (gh workflow run upgrade-arc-harness.yaml -f scenarios=worker-wedge-mid-derive -f base_sha=bba72a4a57d08b43f6bf983be2606f45c7fe3cf3, expected FAIL), then GREEN (same minus base_sha, expected PASS). Landing now is safe for rc.15: its leg 5 dispatches at the TAG's ref, where this arc does not exist (the 295 lesson, working in our favour this time).
---

author: engineer
created: 2026-08-28 10:06
---
POST-LANDING VERIFICATION + THE DEADLINE THAT GOVERNS DISPATCH: landing verified byte-identical (309 lines, one file), tree clean. rc.15 CONFIRMED out of reach — b600e5797 is not an ancestor of tag 2b3862bcc and the tag's tree contains no wedge arc; leg 5 (and any rerun) dispatches at the tag ref. THE CONSTRAINT THAT REPLACES the pre-landing concern, strictly narrower: the matrix globs arcs/*-arc.sh from the ref it runs at, so the NEXT candidate cut from master includes this arc in its gating fleet — a never-executed arc riding a release gate until the RED has run. ORDERING REQUIREMENT: both proof runs before the next RC cut. INSURANCE OPTION if a cut becomes imminent before the fleet group frees: run the GREEN first — it catches a construction bug (which first-run arcs historically have) without needing rc.09; the RED makes the arc EVIDENCE, but the GREEN is what tells us it RUNS, and only the second is on the critical path for someone else's candidate. INTERPRETATION RULE for the red, fixed in advance so the reading cannot drift: the red must show 'THE WEDGE FORMED: N row(s) are still processing' from the load-bearing assertion — any OTHER red is a construction fault, and will be reported as which it is, never claimed as the guard proven.
---

author: foreman
created: 2026-08-28 13:25
---
FIRST RED RUN (33174142449, base_sha=rc.09): FAILED — and per the interpretation rule fixed in advance, this is a CONSTRUCTION FAULT, not the guard proven: no 'THE WEDGE FORMED' line anywhere; the arc died at its own :167 on the harness's VM_EXEC style hook refusing a complex inline command body (the hook's remedy text — use VM_SCRIPT/VM_SCRIPT_INLINE — printed in full). The wedge never got to form; the interpretation rule did exactly what it was fixed in advance to do — prevented this red from being misread as evidence. 296's diagnostics pattern held (the rows-still-processing section ran after the failure). Engineer fixing the arc (convert the offending call per the hook's own instruction + sweep for other refusable bodies; also to report how it slipped past dry validation — the hook fires only at runtime, invisible to bash -n). The failed VM run was the pre-declared price of construction iterations. RED re-dispatches after the fix lands; GREEN after that.
---

author: foreman
created: 2026-08-28 13:49
---
SECOND RED RUN (33175628012, arc fix aboard): construction fault #2, one step further — demo data populated, queue drained, 'holder-started' printed, then '✗ the ACCESS EXCLUSIVE lock was never granted — ingredient 1 cannot be constructed' after ~3.5 min of grant-polling. The refuses-to-pass-having-constructed-nothing assertion did its job again; GREEN correctly not dispatched (the chained watcher checked for the WEDGE-FORMED line and stopped). Engineer diagnosing from the job log (tmp/red279-run2.log): prime suspect is the VM_SCRIPT_INLINE conversion changing the holder's runtime shape — dead detached session, args not reaching the body, grant-detection query mismatched to the new process shape, or an era factor in the rc.09 box's user/socket config. Also flagged: if the holder's own log ($HOLD_LOG) is not dumped on the grant-wait failure path, that capture is the first fix — the holder's log IS the diagnosis. Standing rule invoked: three construction iterations is where pre-declared patience ends — if diagnosis needs more attempts, a cheaper local iteration loop (compose-based holder+grant-poll dry-run) is owed before another paid run.
---

author: foreman
created: 2026-08-28 13:52
---
FAULT #2 DIAGNOSED WITH CERTAINTY AND FIXED (landed d66423815): the holder's own captured log settled it in three lines — LOCK granted, then COMMIT milliseconds later — because the fix for fault ONE had silently dropped the touch of the release file during the VM_SCRIPT_INLINE restructure: the holder's while-file-exists loop was false on its first evaluation and released immediately while the arc polled pg_locks for 3.5 minutes. The fix is shape, not restoration: the holder CREATES the release file itself before backgrounding, self-checked with propagating failure — the step that needs the file creates it, so no refactor can separate them again. THE CHEAPER LOOP built and proven: the holder's control flow extracted with a psql stand-in iterates locally in ~10 seconds (old shape commits immediately; new shape holds until file removal) — the engineer's own words: this should have run before the second paid dispatch, and now precedes any future one; plain-shell arc logic iterates locally, VMs are for the genuinely-remote parts. DISPATCH HYGIENE INCIDENT, mine: the first run-3 dispatch went out while the commit was BLOCKED by the commit-msg hook ('fault #1/#2' pattern-matched bare ticket references) — the run would have executed the old, unfixed arc; caught within a minute, run cancelled, message reworded, landed, re-dispatched. RED RUN 3 (the real one): 33177387634 at head d66423815, chained watcher validating the WEDGE-FORMED line before auto-dispatching GREEN. The refuses-to-pass assertion is now 2-for-2 on preventing false evidence.
---
<!-- COMMENTS:END -->
