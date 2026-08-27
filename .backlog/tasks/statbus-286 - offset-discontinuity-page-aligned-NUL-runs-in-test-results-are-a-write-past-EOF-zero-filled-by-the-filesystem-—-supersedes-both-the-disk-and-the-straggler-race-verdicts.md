---
id: STATBUS-286
title: >-
  offset-discontinuity: page-aligned NUL runs in test results are a write past
  EOF zero-filled by the filesystem — supersedes both the disk and the
  straggler-race verdicts
status: To Do
assignee: []
created_date: '2026-08-27 17:14'
updated_date: '2026-08-27 17:26'
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
<!-- COMMENTS:END -->
