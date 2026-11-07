---
id: STATBUS-591
title: >-
  A full register import uses the machine's cores, and the power-group analysis
  scales with the relationships it reads
status: In Progress
assignee: []
created_date: '2026-11-07T12:31:00Z'
updated_date: '2026-11-07T20:44:00Z'
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
A full register imports faster by using the machine's cores without changing the resulting business data. This iteration must improve the measured rune baseline while preserving business data and temporal power-group membership. Automatic roots follow insertion order and may differ, but must be valid and preserve explicit custom overrides. It does not assume an unmeasured one-hour target.

### Zoom out
Import jobs remain serial because one job can depend on another. Analysis identifies the row dependencies that determine which processing batches of one job can run concurrently.

### Zoom in
Rune run A (November 7, 2026, rc.18, full BRREG, 62 GB RAM): legal-unit analysis 816 s and processing 2,184 s, establishment analysis 745 s and processing 1,670 s. Relationship analysis 1,147 s includes a 1,024 s holistic power_group_link call. Import queue span 6,625 s, task time 6,539 s, full load to idle 10,240 s. Evidence: tmp/rune-measure/A/summary.md.

### Closing review
- Documentation: dependency/concurrency design, doc/import-system.md, measured performance evidence.
- Verification: exact serial-domain parity, failure/replay/barrier behavior, full fast suite, real worker measurements and rune acceptance.
- Cleanup: retain diagnostic scripts and logs in tmp/. Do not delete benchmark databases or production data automatically.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One import job processes its analyzed dependency-safe batches concurrently, and the full BRREG downloads import on rune matches its serial reference's business data, parent links and exact temporal power-group memberships
- [ ] #2 The full BRREG downloads import on rune has a measured load-to-idle span below run A's 10,240 seconds (rc.18, 2026-11-07), using the same installation and input files with a comparable declared validity date
- [ ] #3 Power-group analysis preserves the reference relationships and temporal group memberships, with valid algorithm-derived roots and preserved custom overrides, on graph-size scaling fixtures and rune's 33,710-row BRREG file; recorded scaling measurements and rune runtime improve on the 1,024-second rc.18 baseline
- [ ] #4 [Owner] Choose the job-provided valid_from policy: start-of-year means January 1 of the declared file/snapshot year, allowing validity from that year start; file-date means the declared file/snapshot calendar date, allowing validity only from that snapshot date. Record the choice and resulting date in this ticket and doc/import-system.md, and verify that it sets job-provided valid_from instead of the execution day
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
All STATBUS-591 runtime work remains local on statbus-591-import-speed, with owner review and explicit push authorization outstanding. All four acceptance criteria remain open. Queue default remains one. Rune validation of591 is separate from rabbit's history-release upgrade U and clean run B. Design and detailed evidence: doc/import-concurrent-batches-design.md, tmp/journal.md and tmp/591/. Historical investigation notes remain in Git and in tmp/591/ticket-591-before-saga-review-cleanup.md.

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

### Insertion-order roots and exact group membership
Owner clarification at2026-11-07 19:56UTC: insertion order is intentionally part of the automatic root algorithm. A different automatically selected logical root is not by itself a regression. Exact temporal power-group membership is the primary parity requirement, with the same relationships, group attributes and parent links, valid graph-derived roots/levels and preserved explicit custom overrides. Do not require deterministic LU allocation or introduce a business-key root policy.

The retained six-run serial packing comparison found two automatic root differences on both repeats, but exact domain rows, graph memberships and BFS levels. Earlier parallel-LU probes found the same kind of allocation-dependent choice. These are now reported as permitted algorithm outcomes rather than adoption blockers. Evidence remains tmp/591/serial-packing-20261107_185223_3402-results.json and serial-packing-root-parity.log.

The private ES-only/serial-LU alternative remains a useful strict-order control: two reversed pairs match all12domain tables, roots and LU allocation, with four ES leaves and small SQL-stage ES times11.555 -> 3.563s and11.938 -> 3.808s. It is not an integrated or full-register result and is no longer required merely to preserve automatic root identity. Source: tmp/591/singleton-lu-safe-20261107_185624_43321-results.json.

### Complete verification and separate recovery work
At unchanged runtime e9927efc9487217c8da2dd198fcbdeb3c1d2b726/source20261107180400, the complete fast suite passed132shared+2isolated in463 s, and clean post-commit doc/db regeneration left no changes/deletions. Logs: tmp/591/test-final-fast-verified.log and doc-db-final-after-commit.log. Generated explain/performance outputs restored. Tests314/321/344 now positively assert captured business identities, exact errors/counters and transitions, with preserved failing evidence and independent mutation checks, rather than accepting allocation/stack-sensitive snapshots (d86033bc4,3fe5b77b9,e9927efc9).

Rabbit owns the separately reproduced pre-existing startup recovery defect as STATBUS-589. Our rollback-state probe is not a host-crash test. No 591 adoption or release-readiness claim follows from the local suite or benchmarks.

### SQL Saga branch verification authorized at19:46UTC
Owner19:51: power-group inputs are small relative to LU/ES, so do not add power-group concurrency. Keep holistic graph analysis/processing serial and retain the measured SQL improvements. SQL Saga experiments target independent legal-unit/establishment batches, not parallel graph computation.

Branch prototype/defer-temporal-checks is frozen at953617761d31c7f27ac12a32acb5fe3f01bbb51f. Read-only preflight confirms PostgreSQL18.6/sql_saga1.4 and only three runtime SQL files differ from releasedv1.4, with no C/native changes. All candidate SQL overlays and import probes use fresh uniquely named private clones. No adoption, host-wide installation, shared-library/database change, Norway operation or push. The owner root-policy clarification above applies. The separate valid_from decision remains open.

### SQL Saga comparison observed at20:20UTC
Twelve clean and sixteen genuine historical-update trials pass exact12business-table parity, parent coverage, valid graph membership/root checks, real custom override replay, counters and historyA/B/C. Clean ES medians installed/candidate-ordinary/deferred:4.186/4.073/4.320s in block1,17.280/14.534/6.829s in block2. Block2 hostload is severe, so no reproducible extra clean-insert deferral gain is established.

Historical800-update processing medians including COMMIT: serial trigger-toggle13.620/11.325s, four-client toggle12.236/13.923s, candidate ordinary-enabled2.192/2.356s, candidate deferred1.901/3.095s across the two reversed blocks. The large gain is avoiding trigger-toggle table locks, not a consistent additional deferral gain. This input has zero insert operations, and mixed scheduling uses bounded direct batch calls rather than an adopted application dispatch path. A true analyzed insert+update fixture and installed-v1.4 enabled/no-toggle control remain in progress. Evidence: tmp/591/sql-saga/REPORT.md and root independent verify-saga-{clean-update,second-block}-observations.log. All source fingerprints remain unchanged.

Root actual SQL-worker adoption probe1107_201950_23714 reproduces a required integration boundary: deferred FK23503 at worker COMMIT rolls back exact domain/counters but leaves the committed leaf claim processing and job processing_data. A private API-selected FK IMMEDIATE flush inside process_batch's existing error boundary, before common progress/wakeup locks, produces failed leaf/job/parent and exact rollback for the same actual invalid-parent write. Valid8newES completes4leaves/job8of8 with exact expected names/dates/parents. Source fixture initially lacked the current failure-hook command metadata, so the first failed probe is retained and current seed registration is copied only to new clones. The current-metadata reproduction and both private fixed controls pass. No Crystal-client, crash-recovery or adoption claim. Evidence: tmp/591/saga-worker/README.md, acceptance-current-metadata.log and1107_201950_23714-results.json.

All four acceptance criteria remain unchecked. Local data and SQL-worker verification do not establish full-register throughput, broad existing-unit dependency safety or release readiness.

### Genuine insert/update mixture verified at2026-11-07 20:35UTC
Real upload/analysis produces400inserts+800updates,400wholeLUparentgroups and20batches each containing both actions. Twenty fresh-clone cases in two forward/reversed five-control blocks pass exact2000ESversions/1200identities,3200statpayloadversions, names/dates/parents/primary flags,12business-table parity, temporal coverage, exact graph memberships/valid roots/custom override replay,1200/1200finished counters and historyA/B/C. Helpers/input/evidence and six branch/releaseSQLfiles are frozen before execution; current seed command/queue metadata, including the batch failure after-hook, is copied only to new clones. Source fingerprints remain unchanged.

Processing medians including body+explicitCOMMIT and client scheduling, excluding setup/finalization/analytics: installed-v1.4 serialtoggle11.262s, four-client toggle10.717s, INSTALLED enabled/no-toggle1.990s, candidate enabled2.083s, candidate explicitdeferral2.266s. The installed release already achieves the fast no-toggle path in this fixture. Concurrent toggles have7015sampled ungranted establishment ShareRowExclusiveLock rows. Deferral has no demonstrated additional gain, and median batchCOMMIT34.285ms versus15.887ms for installed-enabled. Shared-host load18.6-28.7 limits small-effect causal claims. A separate serial-enabled versus four-client enabled control remains in progress to isolate concurrency from toggle removal.

Root independent verifier recomputes all expected ES/stat eras and payloads, every batch timed exactly once, full12table parity and graph/history/counter checks from retained observations. Evidence: tmp/591/sql-saga/FOLLOWUP-REPORT.md, followup-f1107_202817_2402/, tmp/591/verify-saga-mixture.mjs and verify-saga-mixture-balanced.log. The initial failed smoke is retained; all timed controls use the same explicit import-aware client search path. Fresh-upload/default-worker context diagnosis remains separate from this direct-client adaptation.

No tracked runtime adoption, mixed scheduler broadening, Crystal/Go benchmark, Norway operation or591push. Parent moves/cross-enterprise dependency safety, safe worker error-boundary integration, production throughput, owner datepolicy and explicit push approval remain open. All four acceptance criteria remain unchecked.

### Final attribution and default-context checks, November 7, 2026 at 20:42 UTC
With checks enabled on installed SQL Saga 1.4, four separately frozen controls isolate concurrency: one client takes 7.401/7.972 s, four clients 2.513/2.771 s. Medians are 7.686 versus 2.642 s, an observed 2.91x ratio on this small fixture, not a full-register prediction. All four pass the same genuine 400-insert/800-update, exact histories/payloads/parents, twelve-table, graph/override/history/counter checks, including explicit COMMIT.

A fresh default-path upload creates schema-qualified procedure snapshots. The actual default SQL worker then finishes all 1,200 rows with the expected 2,000 ES versions and 3,200 statistic versions, parents and history A/B/C, retaining current serial mixed-job dispatch. The prior unqualified-snapshot failure uses the reused creator context, not this tested default upload/worker path. Before landing, a narrow followup will reproduce and fix the current 591 handler allowlist's search-path-sensitive text comparison using procedure identity. Mixed eligibility and SQL Saga adoption remain unchanged.

Root independent verification passes. Evidence: tmp/591/sql-saga/short-n1107_203900_99673/, short-controls.py/.log, and tmp/591/verify-saga-mixture-serial-enabled-final.log. Sources are unchanged, with zero retained Saga database sessions at audit. The comparison is complete: leaving checks enabled removes the trigger-toggle bottleneck, concurrency gives a separate measured gain, and experimental deferral has no demonstrated additional speed advantage. Any later deferral adoption still needs the separately prototyped safe failure boundary. No runtime adoption, 591 push or Norway operations. All four acceptance criteria remain open.
<!-- SECTION:NOTES:END -->
