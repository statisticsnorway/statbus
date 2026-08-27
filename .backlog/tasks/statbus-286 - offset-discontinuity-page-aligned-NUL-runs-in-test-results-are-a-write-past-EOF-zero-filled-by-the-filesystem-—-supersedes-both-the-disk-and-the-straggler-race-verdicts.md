---
id: STATBUS-286
title: >-
  offset-discontinuity: page-aligned NUL runs in test results are a write past
  EOF zero-filled by the filesystem — supersedes both the disk and the
  straggler-race verdicts
status: To Do
assignee: []
created_date: '2026-08-27 17:14'
updated_date: '2026-08-27 22:39'
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
Architect's ruling (2026-08-27, adversarial verification of the day's second corruption instance, REVISED same evening after the SEEK_HOLE probe and cross-checks), superseding both prior verdicts on the NUL-corrupted test/results class (May's 105/straggler case and tonight's 110/301 case). Status: a gap of KNOWN GEOMETRY, TWO live mechanisms, and the experiment that separates them — NOT a confirmed mechanism.

WHAT IS ESTABLISHED (read off the bytes, no storage reasoning): data for [16384, 593114) in 110's result (and [4096, 5960) in 301's) NEVER ARRIVED, while correct data before and after did. The zero runs START page-aligned (stdio 4096-byte flush boundaries) but END at arbitrary offsets. Files fully allocated (110: size 1,175,693 / blocks 2304, ratio 1.00; 301: 68,397 / 136) — verified on the ORIGINALS by foreman and engineer independently.

RULED OUT: storage/disk corruption and VirtioFS whole-page substitution (both produce runs page-aligned at BOTH ends; ours end mid-page); sparse holes (SEEK_HOLE/SEEK_DATA on the originals: contiguous DATA, no holes).

THE TWO LIVE HYPOTHESES, no longer separable on current evidence:
1. OFFSET DISCONTINUITY — a writer's position was at the gap's end while the gap was never written (two processes racing OR one process with a stale second handle: identical signatures; the process count is a detail beneath the property).
2. RANGE LOSS — everything was written sequentially and the storage path dropped the range, leaving allocated zeros.
The geometry MILDLY favours discontinuity: an arbitrary end offset is natural there (a position in an output stream), while range loss needs a partially-lost page (zeros in a page's head, content in its tail) — possible, but a coincidence the other story does not need. Mild, not decisive.

EVIDENCE STATUS NOTES (kept so nobody re-litigates): the SEEK_HOLE no-hole result is UNINFORMATIVE, not refuting — these writes cross VirtioFS, whose past-EOF gap handling (hole vs daemon-materialized zeros) is Docker Desktop's implementation choice, so the probe cannot answer what it was posed for. The exposure-window/victim-profile hypothesis (big slow files get hit) is REFUTED by this run's own data: 107 larger and clean, 305/307 slower and clean, victim 301 middling, prior victim 105 clean today — selection looks arbitrary; do not rebuild a time-dependent shape on it. "Single writer" claims are unprovable by pgrep (point-in-time sampling; container-side pgrep is blind to host-side holders of the bind mount). pg_regress writes DIRECTLY to the bind mount (--outputdir=/statbus/test, /Users/jhf/ssb/statbus -> /statbus) — no copy step exists between writer and artifact. Forensic captures of suspected-sparse files must record SEEK_HOLE geometry BEFORE copying (cp materializes holes). May's straggler remains an INSTANCE consistent with hypothesis 1, not a separate mechanism; the afternoon verdict's error was certainty.

THE DISCRIMINATING EXPERIMENT (deliverable #1 — settles the two hypotheses in ONE run, no need to catch the event in the act): run pg_regress with --outputdir on a CONTAINER-LOCAL path (not the bind mount), copy results out at the end, compare. Container-local clean + bind-mounted corrupt = the storage path is the mechanism. Both corrupt = the writer is the mechanism and VirtioFS is exonerated.

THE INSTRUMENT (deliverable #2, revised — POSITIONS, not identities, are the discriminator): extend dev.sh check_results_for_nul_corruption so that at fire time, before anything else runs, it records (1) inside the container, /proc/*/fdinfo/* for every fd resolving to the results file — the pos: field gives each holder's exact offset; two positions settles discontinuity instantly, one position with a gap behind it points at loss; (2) host-side lsof on the file for holder IDENTITY (fdinfo unavailable on macOS); (3) the file's stat and SEEK_HOLE map at capture time.

Standing discipline unchanged: victims restore via git checkout when surroundings match HEAD; never update baselines from corrupted output; report-and-wait on stragglers (STATBUS-188); CI remains the reference oracle. Why CI never shows it stays OPEN with two candidates (bind-mount path; template reuse/retry behaviour) that CI-absence cannot discriminate — and CI's executed sample is smaller than its green count (stamp-rides). Cross-references: STATBUS-282 (host-death gap — one producer of stale writers), STATBUS-158 (the tripwire this extends).

WHAT IS ACHIEVED: the damage has an exact known shape, one changed setting on a future run proves which of two causes it is, and the next occurrence records every holder's write position — no future session re-litigates disk-vs-Docker-vs-straggler on signature alone.
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
<!-- COMMENTS:END -->
