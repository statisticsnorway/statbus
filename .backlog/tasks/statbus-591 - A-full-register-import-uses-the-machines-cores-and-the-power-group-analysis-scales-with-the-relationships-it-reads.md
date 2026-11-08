---
id: STATBUS-591
title: >-
  A full register import uses the machine's cores, and the power-group analysis
  scales with the relationships it reads
status: In Progress
assignee: []
created_date: '2026-11-07T12:31:00Z'
updated_date: '2026-11-08T10:40:00Z'
labels:
  - import
  - performance
dependencies: []
documentation:
  - doc/performance/2026-11-combined-import-review.md
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Rebase the bounded import prototype on current master and preserve released recovery/progress fixes.
2. Implement and maintain the complete owner-review guide. Delegate release/CLI/date forwarding to rabbit and scoped documentation to a6.1worker.
3. Verify the combined schema and runtime with local migrations, full fast suite, frontend checks and complete schema-doc generation. Diagnose every failure and add failing regressions for newly discovered defects.
4. Commit explicit owned paths, coordinate the FF push with rabbit, inspect exact-SHA CI, and deliver a named release candidate through all real gates.
5. Record matched full-register import measurements, parity, errors, memory, queue concurrency and declared snapshot date. Prior B is only the history-release reference.
6. Keep all four criteria open until satisfied. The owner's validity-date choice and personal review checklist remain required.
7. HARD HOLD: do not promote the next stable release until the owner explicitly approves the reviews. RC authorization does not authorize final stable or destructive Norway work.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Current checkpoint and remaining gates
All STATBUS-591 runtime work is local on statbus-591-import-speed. Validated code checkpoint: 34555acdcb5c333fa99ad98754e8648b93be9a36. No591code has been pushed or installed on Norway. All four acceptance criteria remain unchecked. Queue default remains one. Owner review, approved eligibility scope, declared valid_from policy, explicit push authorization, rebased integration/CI, named candidate and full-register acceptance remain outstanding. The validity-date policy is real remaining implementation, not a completed prototype claim.

The owner requested the morning recap and an explicit execution plan on November8,2026. Todos now separate release/Reports handover, owner decisions, ticket/docs updates, rebase/validation/commit/push/CI, full-register acceptance and parked topics. Todos are the execution plan, this ticket retains scope and evidence. Preserve tmp diagnostics and databases until authorized cleanup. Source guides: doc/import-concurrent-batches-design.md, doc/import-system.md, tmp/journal.md and tmp/591/. Prior notes remain in Git history and tmp/591/ticket-591-before-saga-review-cleanup.md.

### Full-register reference, not a591result
Run A on Norway rc.18, November7,2026,62GB host RAM: LU analysis/processing816/2184s, ES745/1670s; relationship analysis1147s includes1024s holistic power_group_link. Import span6625s, task time6539s, load-to-idle10240s. Source: tmp/rune-measure/A/summary.md.
Rabbit's history-release upgrade U and clean run B contain no591code. Matched-input B reduced load-to-idle10240->7325s but import span6625->6717s, so it is not an import-step speedup or591acceptance. U/B documentation is landed separately at b9c254647 and85e35e613. Overnight saved rc04 acceptance verifies Norway upgrade completed November7 23:46:03UTC with stocks/history preserved;579Done. Reports577actual running/idle browser acceptance remains open. These separate release outcomes do not waive any591criterion.

### Power-group SQL improvements
Analysis migration20261107133923 replaces either-end OR joins with equality joins and grouped deterministic matches. Local full-file fresh analysis264->0.66s, reload171->2.0s, same69089distinct row/root/existing-group triples. Regression372 detects old behavior and passes after. This analysis is already implemented and is not being redone.
Processing1caea283a removes a redundant merge-candidate nonnull filter that distorted first-load cardinality:6000-group fixture31.535->4.463s. Replacing repeated BFS seed anti-lookups with equivalent EXCEPT then takes a retained29503-edge replay51.576->13.863s after that predicate fix, with all29503relationship and444root rows byte-identical. Final current-procedure replay17.732s matches again. Referenced LU metadata is synthetic, not a full production import. Evidence: tmp/591/pg-process-journal.md, pg-process-regress-suite/ and pg-process-brreg-final-private-key.log. Cycle-tail repair68559913a chooses a valid influencing member, preserves valid roots/custom overrides and passes378plus normal graph regressions.
Owner19:51UTC: keep holistic power-group graph analysis/processing serial. SQL Saga and concurrency experiments target LU/ES batches, not parallel graph computation.

### Dependency grouping, scheduler and wakeup
Whole-slot packing keeps analyzed dependency groups indivisible. Regression373 caught rounding/split-slot assignment, ef810daba uses floor boundaries. e25728465 refreshes action statistics once after analysis:24k-row fixture10s timeout->0.267s. Scheduler5fcf8c4b2 adds replay-safe batch children, atomic counters, serial job/holistic barriers and a failure after-hook outside the handler savepoint.375proves failed leaf/job/wrapper propagation and zero residual domain writes after injected failure. Integrated eligibility remains dependency-safe clean insert jobs, mixed/existing/informal jobs retain serial fallback.
Initial real-worker parallel trials gave no accepted overall gain because first domain write held worker.base_change_log_has_pending until commit. Evidence: selection-v2-results.json and selection-v2-n4-live-blockers.txt under tmp/591/. This remains the contention reproduction, not the final gain claim.
Batch-tail wakeup1d610f509 retains immediate change-log appends/integrity checks and publishes durable flag, collector task and notification at transaction tail. All producers participate, collector locks flag before drain snapshot.377and independent two-connection acceptance preserve exact changed IDs, notification, rollback and durable pending state under forced collector-after-DELETE race. Evidence: tmp/591/wakeup-frozen-20261107-1756/, deferred-change-wakeup-acceptance-w20261107_1757frozen-after.json and wakeup-migration-roundtrip.log.

### Actual Crystal-worker selection measurements
Two fresh paired runs with reversed order: import73.087->46.348s and102.785->66.357s, worker wall84.899->73.124s and117.041->92.566s. Within-pair import35-37%shorter, worker wall14-21%shorter. Exact12canonical domain tables, parent/root fields, counters and historyA/B/C match all four runs. Inputs4924LU/24027ES/2relationships,24026ESaccepted and same one input error, four ESleaves, only one LUbatch and no ambiguous roots. Both sides use new packing. Shared-host timing and6.0-6.6GiB shared-container samples are not production predictions or isolated RSS. Evidence: tmp/591/wakeup-selection-v1-results.json, wakeup-selection-v2-reversed-results.json, wakeup-selection-paired-summary.log and wakeup-selection-inputs.sha256.

### Insertion-order roots and parity contract
Owner clarification November7 19:56UTC: insertion order intentionally affects automatic root selection. A different automatic logical root alone is not regression. Require exact temporal group membership, relationships, group attributes and parent links, valid graph-derived roots/levels, preserved explicit custom overrides. Do not impose deterministic LU allocation or a new business-key root policy.
Retained six-run serial packing comparison found two automatic root differences on both repeats, with exact domain rows, memberships and BFS levels. Earlier parallel-LU probes show the same allowed allocation-dependent choice. Evidence: tmp/591/serial-packing-20261107_185223_3402-results.json and serial-packing-root-parity.log.
Private ES-only/serial-LU strict-order control matches all12tables/roots/LUallocation in two reversed pairs, four ESleaves, ESstage11.555->3.563s and11.938->3.808s. Not integrated/full-register evidence and not required merely to preserve automatic root identity. Source: tmp/591/singleton-lu-safe-20261107_185624_43321-results.json.

### SQL Saga comparison, completed without adoption
Owner authorized private comparison19:46UTC. Candidate prototype/defer-temporal-checks frozen953617761d31c7f27ac12a32acb5fe3f01bbb51f versus installed1.4 release3d4059f6153c2994231b6e1d4580ab6bf7c488ac, PostgreSQL18.6. Only three runtime SQL files differ, no C/native changes. Uniquely named private clones only, no host-wide install/shared extension change/Norway action/push. Frozen source/helper audits unchanged.
Initial12clean+16historical-update real-import comparisons pass exact12tables, parents/coverage, membership/valid roots/custom overrides, counters/historyA/B/C. Clean installed/candidate-enabled/deferred medians4.186/4.073/4.320s in block1 and17.280/14.534/6.829s in block2. Historical800-update medians serialtoggle13.620/11.325s, four-client toggle12.236/13.923s, candidate enabled2.192/2.356s and deferred1.901/3.095s across reversed blocks. Severe shared-host load prevents an extra deferral-gain claim. Sources: tmp/591/sql-saga/REPORT.md and verify-saga-{clean-update,second-block}-observations.log.
True analyzed mixture400inserts+800updates,400whole LUparentgroups,20batches each with both actions.20fresh-clone cases in reversed five-control blocks pass exact2000ESversions/1200identities,3200statpayloadversions, names/dates/parents/primary flags,12table parity, temporal coverage, graph/roots/overrides,1200/1200finished and historyA/B/C. Current seed command/queue/failure-hook metadata is copied only to new clones. Body+explicitCOMMIT/scheduling medians: installed serialtoggle11.262s, concurrenttoggle10.717s, INSTALLED enabled/no-toggle1.990s, candidate enabled2.083s, candidate defer2.266s.7015sampled ungranted establishment ShareRowExclusiveLock rows with toggles. COMMIT median34.285ms defer versus15.887ms installed enabled. Shared-host load18.6-28.7limits small-effect claims. Evidence: tmp/591/sql-saga/FOLLOWUP-REPORT.md, followup-f1107_202817_2402/, verify-saga-mixture.mjs and verify-saga-mixture-balanced.log.
Separate frozen installed-enabled controls isolate parallelism: one client7.401/7.972s, four clients2.513/2.771s, medians7.686->2.642s, observed2.91x on this small mixed fixture. All four pass same full parity and explicitCOMMIT checks. Direct real-batch clients, not adopted mixed application dispatch or Crystal/Go/full-register benchmark. Sources: tmp/591/sql-saga/short-n1107_203900_99673/, short-controls.py/.log and verify-saga-mixture-serial-enabled-final.log.
Conclusion: avoiding toggle locks supplies the large gain, installed1.4already supports fast enabled checks, concurrency has a separate measured gain, experimental deferral has no demonstrated additional advantage. No SQL Saga branch adoption. Parent moves/cross-enterprise dependency safety remains required if later broadening eligibility.

### Deferred-COMMIT failure boundary, private proof only
Actual SQL-worker probe1107_201950_23714 reproduces deferredFK23503atCOMMIT: domain/counters roll back but committed leaf claim remains processing and job processing_data. Private selected-FK IMMEDIATE flush inside process_batch error boundary, before common progress/wakeup locks, produces failed leaf/job/parent and exact rollback for same invalid-parent write. Valid8newESfinishes4leaves and job8/8with exact expected names/dates/parents. First fixture lacked current failure-hook command metadata, its failed probe is retained, current seed metadata copied only to new clones. Current-metadata reproduction and both fixed controls pass. No adoption/Crystal/crash-recovery claim. Evidence: tmp/591/saga-worker/README.md, acceptance-current-metadata.log and1107_201950_23714-results.json.
Fresh default-context upload creates qualified snapshots and actual SQLworker serial mixed fallback finishes1200rows, exact2000ES/3200statversions/parents/historyA/B/C. Earlier unqualified snapshot failure belonged to reused creator context, not tested default upload path.

### Caller-context fix and complete integration verification
Unpublished allowlist compared displayed regproc names, whose schema visibility depends on search_path, so eligible clean jobs silently ran serial in import-aware callers.34555acdc compares same eight typed routine identities, no eligibility broadening.
Positive375regression written before fix: default path creates waiting concurrent dispatcher/two leaves, import-aware path creates none/zero and processes serial. Dump-based private prototype and tracked fix both produce two leaves in both contexts and exact two imported rows/units/versions/enterprise parents. Existing replay/barrier/failure/fallback outputs unchanged.373/375exact expected PASS, empty stderr/zero diffs. Source fingerprints/DBflags/global roles unchanged, no remaining private sessions. Evidence: tmp/591/handler-identity/REPORT.md, before-positive-375_statbus_591_concurrent_import_batches.{out,diff,stderr}, after-375_statbus_591_concurrent_import_batches.*, after-373_statbus_591_processing_batches_hold_whole_units.* and identical before.json/after.json.
Root replayed exactly two unpublished dispatcher/wakeup migrations on verified idle statbus_local/statbus_seed. Frozen normal fast suite132shared+2isolated PASS November7 21:11:22UTC, complete schema-doc generation21:12:08with no unintended deletions and only paired processing-phase doc. Explain/performance outputs restored. Logs: tmp/591/handler-identity-integration.log, test-handler-identity-fast-frozen.log and doc-db-handler-identity-frozen.log.
First full run also passed134SQLcases but root edited design guide during run and checkout-stability guard correctly rejected whole command. Preserved diagnosis/failure, frozen retry PASS without weakened guard. Dirty-tree release freshness stamps intentionally withheld, no release/CI claim. Earlier full132shared+2isolated463s at e9927efc9 and clean post-commit doc generation are retained in test-final-fast-verified.log/doc-db-final-after-commit.log.314/321/344positive business identity/error/counter tests have original failures and mutation proofs in d86033bc4/3fe5b77b9/e9927efc9.
Rabbit owns independent pre-existing crash-recovery589. Our rollback-state probe is not a host-crash test. All four591criteria remain open until authorized integration, date policy, full-register evidence, CI and release acceptance.

2026-11-08 09:17 UTC, read-only local retention inventory: 118 statbus_591* databases total 16,240,811,018 bytes (15.125 GiB), zero other sessions at capture. tmp/591 contains 1,282 evidence files, 1,211,555,458 bytes (1.128 GiB). This checkout's dbdumps has 29 files including .gitkeep, 3,009,015,734 bytes (2.802 GiB), and ~/statbus-backups is empty. A separate import_benchmark_41768 (872,527,551 bytes) has unverified ownership/need and is preserved. Reproducible local catalog/metadata evidence and caveats: tmp/retained-inventory-20261108/README.md, databases.sql/json and files.mjs/json. No remote query, migration, benchmark/test rerun or data deletion. Inventory is complete, but cleanup remains a separate owner-authorized follow-up after prototype review and fixture-retention decisions. Preserve tmp diagnostics and raw red/green/parity evidence. No 591 acceptance criterion is satisfied by this housekeeping and all four remain unchecked.

Morning handover correction, November 8 at 09:12 UTC: Reports ticket577 is now Done on master's 571336064. Its real rc04 Firefox observation showed waiting, labeled running, 69% progress, history merging at 76%, then idle at 08:57:31 UTC. Saved verified-acceptance.json and complete browser-transitions.json were independently inspected under statbus_test/tmp/rune-measure/reports-rc04-20261108/, without rerunning Norway work. The previous paragraph describing open Reports browser acceptance was the earlier overnight state. Final stable-promotion verdict is still awaited from rabbit and this separate Reports acceptance does not authorize or satisfy STATBUS-591.

2026-11-08 09:55 owner authorized integrating this branch on current master, coordinated push and named release candidates. This replaces the previous pending push-authorization gate. HARD RELEASE HOLD: next final stable promotion requires the owner's explicit personal review/approval, including history/schema review and declared valid_from policy. RC/CI success is not that approval. Rabbit informed and retains release/host operations; no destructive Norway authorization inferred. Rebased onto origin/master e38a812c2 at29db7f109, preserved all37commits. Only321expected-output conflict was upstream incidental stack line208->214, with persisted-error assertions preserved. Combined verification and complete version-controlled owner review guide are now in progress. All4acceptance criteria remain unchecked until independently satisfied.

Combined integration verified November8 10:14UTC: frozen clean57aa183009dbdb0a6fa7b0e947e13be83bd59ae5 full fast suite PASS134shared+2isolated=136, including371,372–378andreleased390crash recovery. Full schema documentation regeneration completed successfully with no deletions. The only drift was six redundant deparser aliases in non-first UNION arms of statistical_unit_def, saved separately and excluded as unrelated generated noise. Explain/performance output drift was saved and restored. App type check, lint(0errors/5warnings),25suites/208tests and production build PASS. Initial Jest extra-separator invocation ran no tests, diagnosed and corrected without code changes. Logs: tmp/591/combined-rc-{fast-frozen,doc-db,app-tsc,app-lint,app-test-corrected,app-build}.log. Two isolated fast cases094/143 are not the standalone small-history benchmark.

Master advanced only by592ticket closureab81814a9. Rebased after frozen checks to c91c274b0ba8d0682ba0c6595213764e76eaa0fc, exact git diff confirms tested migrations/tests/app/CLI/docs byte-identical, range-diff at tmp/591/combined-rc-ticket-rebase-range-diff.txt. No needless SQL rerun for that ticket-only rebase. Complete owner review guide is committed/linked, all personal approvals unchecked. Rabbit accepted combined named-RC coordination and the hard next-stable hold after receiving the exact09:55owner instruction. Date policy remains unchosen, explicit date/year loader interface is delegated to rabbit, no Saga adoption or new production-wipe authorization. Coordinated candidate push/CI/RC/full-register acceptance remain pending and all four criteria stay unchecked.

Coordinator integration 2026-11-08 10:40 UTC: accepted origin/statbus-591-import-speed exact2d8092b3314d0296d567aaeaac49fe6cc34f7f81 and rebased only five unpublished operator/security commits onto it, checkpoint7841df9852f2f5bf84d64ee8132c523306f6f328. Range-diff proves identical patches, and migrations/doc-db/SQL tests byte-identical to handed-off tested136-case source. Root applied all five missing forward migrations to verified local seed, generated types with no changes. Explicit valid-from/year interface and cloud transport pass; final actual PostgreSQL guarded loaders verify all3job dates in four fresh date/year scenarios, both legacy defaults, and both conflict paths refuse while preserving whole jobs/definitions/tasks. RED download conflict previously mutated all3dates. Evidence tmp/591-date-real and tmp/591-date-interface, exact limitations in owner guide. Security593 compatible patches plus bounded Zod query arrays now included, fullfrontend229tests/build pass, residual advisory gates explicit. No date policy selected, all four591criteria remain open. No full-register591measurement or Norway wipe/deployment claimed. Next stable HARD HELD for personal review. Final exact-SHA CI/namedRC/fullguest gates remain next.
<!-- SECTION:NOTES:END -->
