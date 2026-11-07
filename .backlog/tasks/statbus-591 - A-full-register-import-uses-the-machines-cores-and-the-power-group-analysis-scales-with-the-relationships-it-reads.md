---
id: STATBUS-591
title: >-
  A full register import uses the machine's cores, and the power-group analysis
  scales with the relationships it reads
status: In Progress
assignee: []
created_date: '2026-11-07T12:31:00Z'
updated_date: '2026-11-07T19:52:00Z'
labels:
  - import
  - performance
dependencies: []
type: enhancement
ordinal: 499204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A full register imports faster by using the machine's cores without changing the resulting business data. This iteration must improve the measured rune baseline while preserving exact row and chosen-root parity; it does not assume an unmeasured one-hour target.

### Zoom out
Import jobs remain serial because one job can depend on another. Analysis identifies the row dependencies that determine which processing batches of one job can run concurrently.

### Zoom in
Rune run A (November 7, 2026, rc.18, full BRREG, 62 GB RAM): legal-unit analysis 816 s and processing 2,184 s, establishment analysis 745 s and processing 1,670 s. Relationship analysis 1,147 s includes a 1,024 s holistic power_group_link call. Import queue span 6,625 s, task time 6,539 s, full load to idle 10,240 s. Evidence: tmp/rune-measure/A/summary.md.

Implementation design and measured local evidence: doc/import-concurrent-batches-design.md and the notes below. Local import-speed work stays on statbus-591-import-speed until owner review. Rune validation is separate from rabbit's history-release upgrade U and clean run B.

### Closing review
- Documentation: dependency/concurrency design, doc/import-system.md, measured performance evidence.
- Verification: exact serial-domain parity, failure/replay/barrier behavior, full fast suite, real worker measurements and rune acceptance.
- Cleanup: retain diagnostic scripts and logs in tmp/. Do not delete benchmark databases or production data automatically.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One import job processes its batched steps concurrently while respecting analysed row dependencies; the full BRREG downloads import on rune produces exactly the same business rows, parents and chosen power-group roots as its matched serial reference
- [ ] #2 The full BRREG downloads import on rune has a measured load-to-idle span below run A's 10,240 seconds (rc.18, 2026-11-07), using the same installation and input files with a comparable declared validity date
- [ ] #3 Power-group analysis produces the exact reference relationship/root/group mappings on graph-size scaling fixtures and on rune's 33,710-row BRREG file, with scaling measurements and a rune runtime faster than the recorded 1,024-second rc.18 baseline
- [ ] #4 [Owner] Choose the job-provided valid_from policy: start-of-year means January 1 of the declared file/snapshot year, allowing validity from that year start; file-date means the declared file/snapshot calendar date, allowing validity only from that snapshot date. Record the choice and resulting date in this ticket and doc/import-system.md, and verify that it sets job-provided valid_from instead of the execution day
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Current verified checkpoint (2026-11-07)

All STATBUS-591 runtime work remains local on statbus-591-import-speed, with owner review and explicit push authorization outstanding. All four acceptance criteria remain open. Queue default remains one. Design and detailed evidence: doc/import-concurrent-batches-design.md, tmp/journal.md and tmp/591/. Historical investigation notes remain in Git and in tmp/591/ticket-591-before-saga-review-cleanup.md.

### Full-register reference, not a claimed result
Rune run A used rc.18 and the full BRREG downloads on 2026-11-07: legal-unit analysis/processing 816/2,184 s; establishment 745/1,670 s; relationship analysis 1,147 s including the 1,024-second holistic power_group_link call. Import span 6,625 s, task time 6,539 s, load-to-idle 10,240 s. Source: tmp/rune-measure/A/summary.md. Rabbit's history-release run B does not contain the local 591 prototypes.

### Power-group SQL improvements
Analysis migration 20261107133923 replaces either-end OR joins with equality joins and grouped deterministic matches. Local full-file fresh analysis 264 s -> 0.66 s, reload 171 s -> 2.0 s, with the same 69,089 distinct row/root/existing-group triples. Regression372 detects the old runtime and passes after the fix. This analysis is already implemented and is not being redone.

Processing commit1caea283a removes a redundant merge-candidate nonnull filter that distorted first-load cardinality, then replaces repeated BFS seed anti-lookups with equivalent EXCEPT. The predicate fix alone takes the 6,000-group fixture31.535 -> 4.463 s. The additional BFS change takes a retained29,503-edge replay51.576 -> 13.863 s after that predicate fix, with all29,503 relationship and444root rows byte-identical. This uses synthetic referenced LU metadata, not a full production import. Final current-procedure replay17.732 s again matches those exact outputs. Sources: tmp/591/pg-process-journal.md, pg-process-regress-suite/ and pg-process-brreg-final-private-key.log. Cycle-tail correctness repair68559913a chooses a valid influencing member, preserves previously valid roots/custom overrides, and passes SQL378 plus normal graph regressions.

### Scheduler, grouping and current real-worker evidence
Whole-slot packing keeps dependency groups indivisible. Regression373 caught numeric rounding/split-slot assignment; ef810daba uses floor boundaries. e25728465 refreshes action statistics once after analysis: a24k-row reproducer changes from a10-second timeout to0.267 s. Scheduler5fcf8c4b2 adds replay-safe batch children, atomic counters, serial job/holistic barriers and a failure after-hook outside the handler savepoint. SQL375 proves failed leaf/job/wrapper propagation and zero residual domain writes after an injected failure.

The initial parallel real-worker sweep gave no accepted overall gain because the first domain write locked worker.base_change_log_has_pending until commit (tmp/591/selection-v2-results.json and selection-v2-n4-live-blockers.txt). It is superseded for performance by the following paired measurements, but remains the contention reproduction.

Batch-tail wakeup commit1d610f509 retains immediate change-log appends/integrity checks and publishes the durable flag, collector task and notification at the same transaction tail. All producers participate; the collector locks the flag before taking its drain snapshot. SQL377 and independent two-connection acceptance preserve exact changed IDs, notifications, rollback and the durable witness under the forced collector-after-DELETE race. Sources: tmp/591/wakeup-frozen-20261107-1756/, deferred-change-wakeup-acceptance-w20261107_1757frozen-after.json and wakeup-migration-roundtrip.log.

Two fresh actual Crystal-worker selection pairs, with reversed order, give import73.087 -> 46.348 s and102.785 -> 66.357 s; worker wall84.899 -> 73.124 s and117.041 -> 92.566 s. Within-pair import is35-37% shorter, worker wall14-21% shorter. Exact12canonical domain tables, parent/root fields, counters and historyA/B/C match all four runs. Same hashed inputs4924LU/24027ES/2relationships,24026ES imported and the same one input error; four ES leaves, only one LU batch and no ambiguous roots. Shared-host timings and6.0-6.6GiB shared-container samples are not production predictions or isolated RSS. Both sides use the new packing. Sources: tmp/591/wakeup-selection-v1-results.json, wakeup-selection-v2-reversed-results.json, wakeup-selection-paired-summary.log and wakeup-selection-inputs.sha256.

### Exact root compatibility remains an adoption gate
Parallel new-LU allocation changes chosen logical roots because the current policy uses surrogate IDs. A six-run serial-only controlled comparison also proves that whole-slot packing alone changes two chosen logical roots on both repeats, while released packing and released packing plus action ANALYZE match. Domain rows, graph memberships and BFS levels otherwise agree. Queue concurrency one does not resolve this. Source: tmp/591/serial-packing-20261107_185223_3402-results.json and serial-packing-root-parity.log; documentation233c82c8d.

A PRIVATE narrower candidate keeps exact released singleton-new-LU packing/allocation serial and only parallelizes eligible formal ES batches. Two reversed pairs match all12domain tables, graph/root rows and exact LU allocation, with four ES leaves. Small SQL-stage ES times11.555 -> 3.563 s and11.938 -> 3.808 s are not real-worker/full-register claims. Source: tmp/591/singleton-lu-safe-20261107_185624_43321-results.json and frozen definitions. This candidate is not integrated or covered by the complete suite, and needs owner scope approval plus mixed/history and real-worker validation.

### Complete verification and separate recovery work
At unchanged runtime e9927efc9487217c8da2dd198fcbdeb3c1d2b726/source20261107180400, the complete fast suite passed132shared+2isolated in463 s, and clean post-commit doc/db regeneration left no changes/deletions. Logs: tmp/591/test-final-fast-verified.log and doc-db-final-after-commit.log. Generated explain/performance outputs restored. Tests314/321/344 now positively assert captured business identities, exact errors/counters and transitions, with preserved failing evidence and independent mutation checks, rather than accepting allocation/stack-sensitive snapshots (d86033bc4,3fe5b77b9,e9927efc9).

Rabbit owns the separately reproduced pre-existing startup recovery defect as STATBUS-589. Our rollback-state probe is not a host-crash test. No 591 adoption or release-readiness claim follows from the local suite or benchmarks.

### SQL Saga branch verification authorized at19:46UTC
Owner19:51: power-group inputs are small relative to LU/ES, so do not add power-group concurrency. Keep holistic graph analysis/processing serial and retain the measured SQL improvements. SQL Saga experiments target independent legal-unit/establishment batches, not parallel graph computation.

Branch prototype/defer-temporal-checks is frozen at953617761d31c7f27ac12a32acb5fe3f01bbb51f. Read-only preflight confirms PostgreSQL18.6/sql_saga1.4 and only three runtime SQL files differ from releasedv1.4, with no C/native changes. An OpenAI6.1 implementation worker owns tmp/591/sql-saga/ and unique private clones only. Compare current ordinary checks, branch ordinary checks and explicit transaction-end FK deferral on clean inserts and genuine mixed/history imports. Include COMMIT and exact parent/root/counter/integrity/rollback assertions. No adoption, host-wide installation, shared-library/database change, Norway operation or push. Results are not yet available. This experiment does not settle root/allocation or valid_from policy.
<!-- SECTION:NOTES:END -->
