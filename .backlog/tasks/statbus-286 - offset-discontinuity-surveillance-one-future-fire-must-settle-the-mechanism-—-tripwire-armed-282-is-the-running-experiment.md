---
id: STATBUS-286
title: >-
  offset-discontinuity surveillance: one future fire must settle the mechanism —
  tripwire armed, 282 is the running experiment
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-27 17:14'
updated_date: '2026-09-01 07:17'
labels:
  - testing
  - tooling
dependencies: []
priority: medium
type: bug
ordinal: 279000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: when this corruption fires again, the capture must settle the mechanism on the FIRST fire. At the observed rate (~2 episodes in 6 weeks) we may get one chance, possibly months out — so the instrument must provably yield, and it now does. This ticket is the surveillance record: the phenomenon's exact shape, the governing hypothesis, the armed tripwire, and what closes it.

THE SIGNATURE, six preserved victims in two episodes: 2026-07-13 (403_cross_border_power_group), 2026-07-14 (314_consecutive_demo_loads), and four on 2026-08-27 (105, 110, 301 twice, 307). All six identical in shape: a run of NUL bytes starting on an exact page boundary, ending at an arbitrary offset, file fully allocated, no holes. Data for the gap never arrived while data after it did.

GOVERNING HYPOTHESIS (architect, revised after the July instances surfaced): both episodes coincide with DOCUMENTED killed runs (2026-07-14 is recorded contemporaneously in dev.sh:482 and :733; 2026-08-27 is the killed suite that stranded six clone databases, STATBUS-282). The load correlation is real but INDIRECT — load produces kills, kills produce stragglers, stragglers produce a second writer. Falsifiable in the passive posture: one strike with no killed run in evidence breaks it.

TWO MECHANISMS REMAIN LIVE, and geometry alone cannot separate them: an OFFSET DISCONTINUITY (a writer positioned past the gap — two racing processes or one stale second handle look identical) or a storage-path RANGE LOSS. Geometry mildly favours the first.

WHY SURVEILLANCE IS THE ONLY INSTRUMENT, not the patient option: at this base rate a paired-suite experiment is structurally incapable of discriminating (the 20/20 quiet-machine series returned a clean, honest null — protocol pre-registered before the runs so it could not be reinterpreted). STATBUS-282's single-writer machinery, now landed, IS the running experiment: recurrence with the guard verified-consulted is evidence against the second-writer branch; a long clean period is evidence 282 was the fix.

THE INSTRUMENT (landed c10a1f983 + 119e83fc8, exercised 6/6 with a planted holder at a non-zero offset): at fire time, BEFORE any preserving copy, the tripwire captures SEEK_HOLE/stat on the ORIGINAL, host lsof holders WITH offsets (-o — macOS has no /proc, and the offset is the entire discriminator), and container-side fdinfo write positions (deliberately matched on sibling results files too — a holder on a sibling is the discontinuity story in miniature).

STANDING DISCIPLINE: victims restore via git checkout when surroundings match HEAD; never update baselines from corrupted output; report-and-wait on stragglers (STATBUS-188); CI remains the reference oracle; synthetic exercise artifacts live quarantined under tmp/forensics-286/synthetic/ with a planted-data README so the genuine count (7 artifacts) stays honest.

EVIDENCE-STATUS, kept so nobody re-litigates: the SEEK_HOLE no-hole result is uninformative (VirtioFS's past-EOF handling is Docker Desktop's choice); the victim-profile refutation (WHICH file gets hit within a run) stands and is distinct from load-dependence (WHETHER it fires at all), which stays a live hypothesis pulled at from both sides; single-writer claims are unprovable by pgrep; comments #5/#6 and #10/#12 are each ONE report recorded twice, not corroboration.

CLOSES WHEN: (a) a recurrence is captured with holders and positions and the mechanism is settled; or (b) a long clean period under real full-suite load lets the architect declare 282's producer-closure the fix.

WHAT IS ACHIEVED: the one future fire will carry holders and write offsets; no future session re-litigates disk-vs-Docker-vs-straggler on signature alone.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 17:18
---
REVISION APPLIED (2026-08-27 evening): the description above replaces the original confirmed-mechanism wording after the architect's closure. The revision's drivers, each verified rather than asserted: (a) the SEEK_HOLE probe (foreman-run, all four artifacts) found NO holes — but the architect's own discriminator was ruled uninformative because VirtioFS's past-EOF gap handling is untested; (b) the victim-profile/exposure-window datum was refuted by the engineer against this run's own data and is struck; (c) the blocks=4104 reading was a bad measurement (engineer re-measured, owned it, recorded in tmp/forensics-263/notes.md); the architect's cp-destroys-sparseness self-correction was itself premised on that bad number — the PRINCIPLE (record SEEK_HOLE geometry before copying) is kept, the instance was fictional. Verdict now: two live hypotheses (offset discontinuity, mildly favoured by geometry; range loss), one discriminating experiment (container-local outputdir + copy-out compare), instrument revised to fdinfo write-POSITIONS + host lsof identity. Both deliverables queue behind STATBUS-263 — not tonight's work.
---

author: foreman
created: 2026-08-27 17:26
---
STRONGEST EVIDENCE YET (2026-08-27 ~17:25Z, engineer): 301_test_custom_happy_path corrupted AGAIN in a SINGLE-TEST run — the only test running, fresh clone DB (test_shared_53331), nothing else on the machine's test path. That removes suite concurrency, test ordering, and long-run duration from the candidate causes in one shot. Geometry across the two instances is the tell: identical deterministic total size (68,397 bytes both times) but DIFFERENT zeroed regions — instance 1: 1,864 NULs starting at 4096 (1 page); instance 2: 2,705 NULs starting at 49,152 (exactly 12 pages); both starts page-aligned, neither run length a page multiple. The damage location moves between runs of identical content — consistent with a nondeterministic mid-write event, not with anything content-derived. Also: 110 re-ran GREEN individually (69,594 ms), closing its attribution as corruption-victim-not-failure. Forensic copies of both 301 instances preserved in tmp/forensics-263/. With a same-day reproducer in hand, the discriminating experiment (container-local --outputdir) is now runnable as a cheap one-off diagnostic instead of waiting for the next accidental occurrence.
---

author: foreman
created: 2026-08-27 17:28
---
DESIGN CONSTRAINT on deliverable #1, learned from tonight's attempts (2026-08-27): the reproducer is INTERMITTENT — 301 corrupted twice (suite run, then single-test run) and then passed clean on the next single-test attempt. Therefore the discriminating experiment cannot be a one-off: a single clean container-local run discriminates nothing (the bind-mount arm also produces clean runs). The experiment must be a SERIES — several runs per arm (container-local --outputdir vs bind mount), and a clean container-local result is only meaningful against a bind-mount arm that corrupts within the same window. Foreman's ruling tonight: NOT run during the 263 endgame (the conditional pre-authorization lapsed when 301 passed on its first retry); it executes as part of this ticket's implementation, designed as the paired series above. Tonight's tally for the record: 301 corrupted 2 of 3 runs — the highest observed local incidence of this class in one day.
---

author: foreman
created: 2026-08-27 18:42
---
FIFTH VICTIM / THIRD 301-ADJACENT INSTANCE tonight (2026-08-27 ~18:30Z): 307_test_lu_enterprise_link corrupted during the stamp-minting suite attempt — size 151,448, NULs 67,233, run starts at 36,864 = exactly 9 pages. 307 was CLEAN in the earlier step-b suite, making four distinct victim files today (105, 110, 301, 307) — further undercutting any content- or test-specific selection story. Incidence tonight: corruption in 3 of the last 4 full-suite runs. Forensics preserved to tmp/forensics-263/ when the run ends. Consequence already absorbed: the release gate no longer depends on local suite runs (STATBUS-288's fast-tests escape landed at 85b692a3c), so this ticket's experiment + instrument can proceed without cut pressure — but the incidence rate argues for scheduling it soon; the local suite is currently unusable for stamp-minting.
---

author: engineer (pinned by foreman)
created: 2026-08-27 22:31
---
DELIVERABLE #1 EXECUTED (2026-08-28 night): the paired series ran 20 runs — 10 container-local --outputdir, 10 bind-mount, alternating, strictly serial, single-writer enforced by the new 282 machinery — and produced ZERO corruption in either arm (every artifact the known-good 68,397 bytes, 0 NULs, sparse=False). Protocol and discrimination rule written to tmp/forensics-286/README.md BEFORE the runs. RESULT: NO DISCRIMINATION — neither branch fires, and the bind mount is NOT exonerated (a test that never reproduces the phenomenon cannot attribute it). THE FINDING THE NULL DOES CARRY: 20 quiet single-test runs = zero corruption where the same host corrupted 2 of 3 FULL SUITES the same day — the shape of a LOAD-DEPENDENT mechanism, partially reviving the exposure-window family (the earlier victim-profile refutation was sound about which file gets hit WITHIN a run, not about WHETHER corruption occurs as a function of load — the engineer states this against his own earlier conclusion). Confounds named: suite runs carry seed rebuilds/worker traffic/89 tests; and the host has since gained 282's single-writer machinery, so some quiet may be that fix working. NEXT EXPERIMENT if wanted is at SUITE scale — architect deciding. DELIVERABLE #2 BUILT (dev.sh, frozen separately, review pending): the tripwire captures at fire time before any copy — SEEK_HOLE/stat on the ORIGINAL, host lsof holders, container fdinfo pos: (the write offset, catching a discontinuity in the act) — honestly flagged UNEXERCISED; synthetic-firing verification suggested for its review.
---

author: engineer
created: 2026-08-27 22:32
---
**DELIVERABLE #1 COMPLETE — the series does NOT discriminate. Reported as a null, not as an exoneration.**

| arm | `--outputdir` | runs | corrupted |
|---|---|---|---|
| **A** | `/tmp/regress-local` (container-local) | 10 | **0** |
| **B** | `/statbus/test` (bind mount) | 10 | **0** |

Alternating, strictly serial, single-writer enforced (STATBUS-282's machinery). Every artifact: size **68,397** — the known-good size, so the test genuinely ran in both arms — **0 NULs**, `sparse=False`, `rc=0`.

Artifacts, per-run geometry records and the protocol are in `tmp/forensics-286/`. **The discrimination rule was written into `README.md` BEFORE the runs**, precisely so a null could not be reinterpreted afterwards.

## What it licenses

**Neither branch fires.** The bind mount is NOT exonerated: that verdict required arm B to corrupt while A stayed clean, and B produced no corruption at all. A test that never reproduces the phenomenon cannot attribute it.

The honest headline is about the phenomenon rather than the arms: **20 single-test runs on a quiet machine produced zero corruption, where the same host produced it in 2 of 3 full suites on 2026-08-27.**

## This cuts against my own earlier reporting, and I would rather say so

That contrast is what a **load-dependent** mechanism looks like. I previously argued AGAINST an exposure-window story, on the grounds that neither output size nor duration predicted the victims. That argument was sound about WHICH FILE gets hit within a run; it is silent on whether corruption occurs AT ALL as a function of machine load. So this series partially revives a hypothesis I helped refute.

**A confound in the other direction, stated for balance:** the machine has since gained STATBUS-282's single-writer authority and orphan sweep. Some of tonight's quiet may be that fix working rather than ambient luck — which would mean the null is partly *our own doing*, and that possibility cannot be separated from load by this data.

## What the null points at

Two differences from the corrupting runs, neither controlled for here: those were **89-test full suites** with seed rebuilds, worker traffic and concurrent harness activity; this was **one test at a time on an idle machine**.

So the informative next experiment is a paired series at **SUITE scale**, not more repetitions of a single test. NOT started — it is a multi-hour commitment on shared infrastructure and a scope decision for the architect.

## Deliverable #2 — built, frozen separately in `dev.sh`

The tripwire now captures **at fire time, before the preserving copy**: `SEEK_HOLE`/`stat` on the ORIGINAL (sparseness measured on a copy answers a different question — copying can materialise a hole), host `lsof` holders, and container-side **`fdinfo pos:`** — the write offset, which would catch the offset discontinuity IN THE ACT rather than inferred from the geometry it leaves. Written to `<preserved>.evidence.txt`. `bash -n` clean.

**It is UNEXERCISED**: nothing corrupted tonight, so its firing path has never run. Flagged rather than left to read as verified.
---

author: architect (pinned by foreman)
created: 2026-08-27 22:32
---
RULINGS ON BOTH DELIVERABLES (2026-08-28 night). CALL #1: HOLD the suite-scale experiment — 282's landing IS that experiment, running free on every future full suite (the 282 ruling pre-registered the inference: corruption recurring with the guard VERIFIED CONSULTED is evidence against the second-writer branch and would make the paired-suite hours worth spending; never recurring means 282 fixed it). A paired run NOW would most likely buy an uninterpretable null at multi-hour cost, since 282 removed the leading second-writer candidate between the corrupted suites and the quiet series. LOAD-DEPENDENCE is recorded as a LIVE HYPOTHESIS, not a finding — one afternoon's support, and the null is equally consistent with 282 working; the engineer's distinction against his own earlier refutation stands (which-file-within-a-run was refuted; whether-at-all-under-load was not). The pre-registered README protocol is what made the null honest. CALL #2: LAND the instrument WITH ONE AMENDMENT — host lsof gains -o (offsets): macOS has no /proc, so without it the only platform where the phenomenon occurs captures identities but never offsets, and THE OFFSET IS THE ENTIRE DISCRIMINATOR. Synthetic exercise UPGRADED: plant a HOLDER (background exec 3<>) then the NUL — 'fired, found no holders' is otherwise indistinguishable from 'lsof invocation broken', the zero-scope green one level down, inside the instrument built to investigate it; assert the evidence names the PID and shows its offset. THE COUPLING: the hold is authorized ONLY on the exercise's success — passive gathering is a plan only when the instrument provably yields; otherwise we are not gathering, we are just not looking.
---

author: foreman
created: 2026-08-27 22:33
---
DESCRIPTION QUALIFICATION (housekeeping, so the description stops contradicting the rulings that now govern): the evidence-status note 'do not rebuild a time-dependent shape on it' is QUALIFIED by comment #7's ruling — the refutation covered WHICH FILE gets hit within a run (victim profile: larger and slower files clean, victims middling) and that refutation STANDS; it never covered WHETHER corruption occurs at all as a function of system load, which is now a LIVE HYPOTHESIS with one afternoon's support (comment #7). The two claims are different shapes and only the first is closed. Also for the record: comments #5 and #6 are ONE report recorded twice (foreman's pin crossed the engineer's own) — not independent corroboration. The fdinfo match-breadth choice (fds whose target contains 'results' rather than the exact victim path, deliberately — a second holder on a SIBLING results file would itself be informative) rides the instrument's landing review.
---

author: foreman
created: 2026-08-27 22:37
---
INSTRUMENT LANDED at c10a1f983 (dev.sh, +58) on the architect's standing LAND-with-amendment — the amendment (lsof -o) and the upgraded exercise both succeeded exactly as prescribed, and the coupling is satisfied: THE HOLD IS NOW ACTIVE. Exercise 6/6 with the transcript on record: planted holder parked at a NON-ZERO offset (34 — deliberately, so a captured 0 could not masquerade as no-capture), the evidence names its pid and shows the position; the dead /proc loop (which could never yield on macOS, the only platform where the phenomenon occurs) is replaced by lsof -o with the offset-is-the-discriminator reason at the line. THE EXERCISE EARNED ITS UPGRADE IMMEDIATELY: it caught the container probe MATCHING ITSELF (the sh -c wrapper contained the pgrep pattern and was reported as a holder) — noise at precisely the moment the holder count is the discriminator, invisible to a NUL-only test; guarded, and the section is now correctly empty absent real holders. Engineer's checking-failures five and six for the night, both self-caught and both in the safe direction, with the habit named: when a check disagrees with the artifact, read the artifact. TICKET STATE: both deliverables done; the phenomenon is under passive surveillance by an instrument proven to yield, with 282's machinery as the running experiment. The ticket STAYS OPEN as the surveillance record — it closes when either (a) a recurrence is captured with positions and the mechanism is settled, or (b) a long clean period under full-suite load lets the architect declare 282 the fix.
---

author: engineer (pinned by foreman)
created: 2026-08-27 22:38
---
RECORD WIDENED: TWO JULY INSTANCES FOUND (2026-08-28 night, surfaced by tidying the forensics namespace, measured read-only with the series' own measure.py, artifacts untouched where the tripwire preserved them): corrupted-314_consecutive_demo_loads-20260714123030.out (size 56,023, NULs 2,253, run starts 8,192 = exactly 2 pages, run 0.55 pages, sparse=false) and corrupted-403_cross_border_power_group-20260713150821.out (size 29,580, NULs 13,045, run starts 12,288 = exactly 3 pages, run 3.185 pages, sparse=false) — the 286 signature exactly, on two previously unassociated tests, dated 2026-07-13/14. CONSEQUENCES, argued by the engineer against his own hypothesis: (1) six victims across six weeks, not four in one day — the description's one-day-cluster frame is wrong; (2) LOAD-DEPENDENCE WEAKENS — two isolated instances six weeks earlier look like a LOW BACKGROUND RATE, and a rare event clusters by chance exactly where a busy afternoon makes it noticed; (3) the HOLD's passive wait may be LONG, which raises the instrument's importance rather than questioning the hold — the one future fire must be interpretable; (4) the July instances must NOT be silently attributed to 282's host-death producer (that requires a killed run; whether those runs were killed is not in evidence). Also: the synthetic exercise artifacts were moved out of the corrupted-* namespace into tmp/forensics-286/synthetic/ with a planted-data README, precisely so nobody reads one as a seventh instance. Description revision is the architect's frame to make — requested.
---

author: foreman
created: 2026-08-27 22:39
---
Addendum landed at 119e83fc8: the fdinfo match-breadth reasoning is now AT THE LINE (a holder on a sibling results file is the discontinuity story in miniature — the writer moved on while something still held the old file; exact-path narrowing would discard that for tidiness). Comment-only; the exercise re-ran 6/6 after the edit rather than assuming a comment cannot break anything. Forensics-namespace hygiene on the record: 7 real artifacts in tmp/ root, 5 synthetic quarantined under tmp/forensics-286/synthetic/ with a planted-data README — the genuine-instance count stays honest by construction.
---

author: engineer
created: 2026-08-27 22:39
---
**TWO EARLIER INSTANCES FOUND — 2026-07-13 and 2026-07-14. The record is six victims across six weeks, not four in one day.**

Found while quarantining my synthetic exercise artifacts out of `tmp/`'s `corrupted-*` namespace, not by looking for them. Measured read-only with the same `measure.py` as the series; **neither file was moved or touched** — both sit where the tripwire preserved them.

```
corrupted-314_consecutive_demo_loads-20260714123030.out
  size=56,023   NULs=2,253    start 8,192  = 2.000 x 4096 (ALIGNED)   run 0.55 pages (NOT a multiple)   sparse=false
corrupted-403_cross_border_power_group-20260713150821.out
  size=29,580   NULs=13,045   start 12,288 = 3.000 x 4096 (ALIGNED)   run 3.185 pages (NOT a multiple)  sparse=false
```

**Page-aligned start, arbitrary end, fully allocated, no holes — the 286 signature exactly**, on two tests never previously associated with it.

## Three consequences, and the first is against my own hypothesis

**1. It WEAKENS the load-dependence hypothesis I raised in #6.** I offered it because a quiet machine gave 0/20 where 2026-08-27 gave 2-of-3 suites. Two isolated instances six weeks earlier look more like a **low background rate** than a load threshold — a rare event clusters by chance, and a busy afternoon is exactly where one would notice it. Load-dependence should stay a live hypothesis, but this datum pulls against it, and it would be easy to omit because it is mine.

**2. It bears on the HOLD, in favour of the instrument.** If the true rate is a couple of instances per six weeks, the passive wait may be LONG. That is not an argument against the hold — it is an argument that the fire-time capture is the whole value of waiting, because when it finally fires it is the only thing that will make the occurrence interpretable.

**3. It should not be silently attributed to STATBUS-282's host-death gap.** That producer requires a killed run leaving a straggler. Whether those July runs were killed is not checkable from anything I hold — I am not claiming they were not, only that the assumption must not be inherited by default.

## Note on the artifact namespace

My synthetic exercise writes `corrupted-286_synthetic_holder-*` files. They are quarantined in `tmp/forensics-286/synthetic/` with a README stating plainly that the NUL was planted — a file named `corrupted-<test>-<timestamp>.out` sitting beside real ones is exactly what a future investigator would pick up as an instance. Current count: **7 genuine artifacts in `tmp/` root, 5 synthetic quarantined.**

I have NOT edited the description's incidence history — that frame is the architect's to revise.
---

author: architect (pinned by foreman)
created: 2026-08-27 22:40
---
FRAME REVISED (2026-08-28, applied to the description above) — and one of the engineer's three readings was TOO CONSERVATIVE: the July pair is NOT unattributed. dev.sh names 2026-07-14 TWICE, written at the time (:482 the 401 chain-starter external-kill incident; :733 the crash-recovery cycles, STATBUS-188) — contemporaneous documentation of a killed-run day, not an inference. BOTH episodes now coincide with documented killed runs. AND THE CLUSTERING SURVIVES: two victims on adjacent days is a second CLUSTER, not a uniform background — the record is two episodes six weeks apart. THE RECONCILING HYPOTHESIS, sharper than either prior reading: the clustering tracks KILLED RUNS; killed runs are more frequent on busy days; so the load correlation is real but INDIRECT (load → kills → stragglers → corruption) — falsifiable in the passive posture by one strike with no kill in evidence. CONSEQUENCE FOR THE HOLD: at ~2 episodes/6 weeks, a paired-suite experiment is not merely likely-null but STRUCTURALLY INCAPABLE of discriminating — surveillance is not the patient option, it is the only viable instrument, which raises the amended tripwire (lsof -o offsets + proven-to-yield exercise) from valuable to LOAD-BEARING: we may get ONE fire, possibly months out, and it must yield the first time.
---

author: foreman
created: 2026-08-27 22:42
---
RECORD HYGIENE: comments #10 and #12 are ONE report recorded twice (the foreman's pin crossed the engineer's own, same as #5/#6) — not independent corroboration. A future reader counting instances or witnesses reads one finding here, not two. Behaviour change adopted by the engineer: check the ticket before pinning; reporting by message and pinning are different acts.
---

author: foreman
created: 2026-08-28 09:44
---
SCHEDULED (King-directed): @engineer owns the surveillance — he built and exercised the instrument, and on the next tripwire fire he reads the evidence (holders, offsets, fdinfo positions) and reports the mechanism verdict to the foreman. Status In Progress: the surveillance IS the active work — 282's machinery runs as the standing experiment on every full suite, and the tripwire is armed on every run. No dispatch needed until a fire or until the architect judges a clean period long enough to declare 282 the fix (closure condition b); the foreman raises that question to the architect if the record stays clean through the next several full-suite weeks.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSED BY THE KING'S RULING (2026-09-01): the root cause is judged to be RANGE LOSS IN THE STORAGE PATH (Docker's VirtioFS on macOS) — the second of the two live hypotheses — supported by evidence the surveillance never held: the King tried different Docker storage modes, and the corruption frequency DROPPED after switching to Docker VMM. His verdict on the chase, near verbatim: trying to find and fix the root cause while we don't have access to the source code is a project in vain. THE POSTURE THAT REPLACES IT, and it is already built: (1) DETECT AND ABORT — check_results_for_nul_corruption (dev.sh:894) preserves the corrupted bytes, captures fire-time evidence (holders, write offsets, SEEK_HOLE on the original), and fails with a verdict DISTINCT from an ordinary test diff, so the sporadic error can never masquerade as a test failure or trigger the no-flaky-tests rule falsely; it stays as standing equipment, not as an experiment. (2) TRUST CI — the error has never occurred on remote builds (no Docker-on-Mac in the loop), so GitHub-run jobs remain the reference oracle, which was already doctrine and is now the recorded reason. The mechanism-settling surveillance (closure conditions a/b) is moot: even a perfect fire-capture would only name a fault in closed-source software we cannot fix. The killed-run/straggler correlation stands in the record as observed but likely confounded with the storage mode. The tripwire, the straggler guard (158/282), and the quarantined forensics under tmp/forensics-286/ remain in place; victims restore via git checkout; never update baselines from corrupted output.
<!-- SECTION:FINAL_SUMMARY:END -->
