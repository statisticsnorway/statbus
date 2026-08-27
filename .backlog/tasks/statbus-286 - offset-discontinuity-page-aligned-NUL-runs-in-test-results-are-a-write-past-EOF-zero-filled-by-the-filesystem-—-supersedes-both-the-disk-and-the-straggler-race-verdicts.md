---
id: STATBUS-286
title: >-
  offset-discontinuity: page-aligned NUL runs in test results are a write past
  EOF zero-filled by the filesystem — supersedes both the disk and the
  straggler-race verdicts
status: To Do
assignee: []
created_date: '2026-08-27 17:14'
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
Architect's ruling (2026-08-27, adversarial verification of the day's second corruption instance), superseding both prior verdicts on the NUL-corrupted test/results class (May's 105/straggler case and tonight's 110/301 case).

THE DECISIVE GEOMETRY (measured from primary artifacts, foreman-verified): the zero runs START page-aligned (110 at 16384 = exactly 4 pages; 301 at 4096 = exactly 1 page) but END at arbitrary byte offsets (593,114 = 144.80 pages; 5,960 = 1.46 pages). Both files fully allocated (110: size 1,175,693 / blocks 2304; 301: 68,397 / 136) — materialized zeros, no sparse hole.

WHAT THAT RULES OUT: storage/disk corruption (does not start on page boundaries and resume cleanly); VirtioFS/page-cache substitution (whole stale pages give runs that are 4096-multiples aligned at BOTH ends — ours end mid-page); sparseness (measured full allocation).

THE MECHANISM: an OFFSET DISCONTINUITY — something wrote at a position beyond the file's current end and the filesystem zero-filled the gap. The asymmetry is explained exactly: the run starts where the sequential writer's last stdio flush ended (4096-byte buffers — hence page-aligned), and ends at whatever arbitrary offset the far-ahead writer held (a position in a different output stream). Two processes racing and one process holding a stale second file handle produce IDENTICAL signatures — the process count is a detail beneath the property.

ON "SINGLE WRITER": unproven and unprovable by pgrep — point-in-time sampling cannot establish absence (a 200ms psql is invisible), and container-side pgrep is structurally blind to host-side holders of the bind-mounted files. May's straggler was an INSTANCE of offset discontinuity, not a coincidental separate mechanism; the earlier verdict's error was certainty — naming the straggler it happened to find rather than the property that produced the damage.

WHY CI NEVER SHOWS IT: the local runner REUSES the test template where CI builds fresh — template reuse and retry paths are precisely the conditions that leave a stale handle or short-lived second writer around. (CI executed 110 green at 4a3609ede in run 33080040848, 62,685 ms.)

THE INSTRUMENT (Agent Tooling Protocol — the tripwire detects but does not capture WHO): extend dev.sh check_results_for_nul_corruption so that, at the instant it fires and before anything else runs, it records (1) `lsof` on the offending file — names every holder INCLUDING host-side processes, the question every hypothesis has been guessing at; (2) the full process table, host AND container; (3) the file's stat (size, blocks) so sparseness is settled at capture time. Converts "we found zeros afterwards" into "here is who had it open".

Standing discipline unchanged: victims restore via git checkout when surroundings match HEAD; never update baselines from corrupted output; report-and-wait on stragglers (STATBUS-188); CI remains the reference oracle. Cross-references: STATBUS-282 (host-death gap — a producer of stale writers, one instance class), STATBUS-158 (the tripwire this extends).

VICTIM PROFILE (observational): both tonight's victims and the afternoon's are among the longer-writing/larger-output tests — widest exposure window for a mid-write strike.

WHAT IS ACHIEVED: the next occurrence names its culprit exactly, and no future session re-litigates disk-vs-Docker-vs-straggler on signature alone.
<!-- SECTION:DESCRIPTION:END -->
