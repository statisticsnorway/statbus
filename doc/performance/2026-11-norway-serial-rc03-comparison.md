# Norway serial rc.03 full-register comparison

STATBUS-597. Measured on the Norway installation, using the existing published **v2026.11.3-rc.03**, commit `fc1830fe410b19007056ef0853ad9e491d7f4ad9`. All times below are UTC.

## Result

The complete three-file register loaded successfully on a clean installation. Initial analytics finished on November 8, 2026 at **23:48:49**. Compared with the previous same-host run, import span fell **12.59%**, from 6,717 seconds to **5,871.348 seconds**. Load through initial analytics fell **6.17%**, from 7,325 seconds to **6,872.802 seconds**.

Relationship analysis fell **69.03%**, from 1,196.639 to **370.645 seconds**, a **3.23x** old/new ratio. The final analytics tail was longer, so this does not imply a comparable whole-load speedup.

The **separate full recalculation also completed successfully**, with **3,684/3,684 tasks completed and zero failures**. It took **1,245.163781 seconds (20m 45.164s)**, compared with **1,262.942033 seconds (21m 2.942s)** before: **1.41% shorter**, or 17.778 seconds saved. This run **does not demonstrate a large full-recalculation improvement**. The pronounced gain is in relationship import analysis, not the separately measured full recalculation.

All three jobs, rejected rows, warnings, stock/history outputs and **108,851 canonical business-key graph records** match the previous baseline. No experimental concurrency was deployed, no new candidate was cut, and stable promotion remains held for the owner's review.

## Comparison boundaries

| Measurement | Previous Norway reference | Clean serial rc.03 | Change |
|---|---:|---:|---:|
| Import span, first import task start through last import stop | 6,717 s | 5,871.347583 s | 12.59% shorter |
| Initial analytics tail after import stop | 608 s | 1,001.454434 s | 64.71% longer |
| Load through initial analytics stop | 7,325 s | 6,872.802017 s | 6.17% shorter |
| Separate full recalculation through last task completion | 1,262.942033 s | 1,245.163781 s | 1.41% shorter |

The old import measurements are retained at integer-second precision. The new measurements are database timestamps, not SSH observer or wrapper duration. New load through last task completion is 6,872.847786 seconds, slightly later than the stop-based figure used in the table. Per-command task-time sums can overlap and are not elapsed wall time.

The import reference is run B on November 7, 2026, using `v2026.11.2-rc.02` / `2e7e20641`. The separate recalculation reference ran on November 8 from **08:36:26.699674** through **08:57:29.641707**, root `53750`, after the installation had moved to `929fe787c2ab323d3a8c6d013bb9864fbec7bd67` / v2026.11.2. That reference completed **3,684 of 3,684 tasks**, with zero failures. The import and recalculation references are therefore explicitly different runtime versions.

These are same-host, same-input observational release comparisons, not randomized repeated trials or isolated causal attribution to an individual patch. Cache state and analytics scheduling can affect the result. Local experimental concurrency measurements used a different 8 GiB database limit and are not used to claim a Norway speedup.

## Complete import phases

| File / phase | Old run B, seconds | Serial rc.03, seconds | Change |
|---|---:|---:|---:|
| Legal units, analysis | 841.511218 | 855.738654 | 1.69% longer |
| Legal units, processing | 2,246.356136 | 2,209.609657 | 1.64% shorter |
| Establishments, analysis | 676.731839 | 704.883668 | 4.16% longer |
| Establishments, processing | 1,700.531774 | 1,663.766377 | 2.16% shorter |
| Relationships, analysis | 1,196.639400 | 370.645456 | 69.03% shorter |
| Relationships, processing | 53.264355 | 64.296484 | 20.71% longer |

The first import task started at **21:54:16.434369**. The final import stopped at **23:32:07.781952**. Initial analytics stopped at **23:48:49.236386**. Successful uploads are not treated as completed imports.

Initial analytics ran 32 collection/derive cycles. Refresh batches consumed 6,256.515737 aggregate task seconds across 4,776 tasks. Staging flushes consumed 1,246.629096 seconds across 32 tasks, with a maximum of 284.395040 seconds. Statistical-unit derivation consumed 706.299285 seconds across 32 tasks, with a maximum of 361.964170 seconds. These task sums describe work and overlap, not additional wall time to add to the load total.

## Full recalculation

The separately enqueued root `45578` was requested on November 8 at **23:48:54.091552**, after the complete load and initial analytics had passed output checks. Its first task started at **23:48:54.122466** and its last completion was on **November 9 at 00:09:39.286247**. All **3,684/3,684 tasks completed**, zero failed. The genuine durable runner exited **zero**, and an independent read-only check at **00:10:56** confirmed three finished jobs, zero active/failed tasks, an empty change log and no pending-change flag.

The new and old task trees contain the same number of each command. Their aggregate processing times were **4,140.708406** and **4,158.636576** seconds respectively. Full command breakdown, in aggregate task seconds:

| Command | Tasks, each run | Old | Serial rc.03 |
|---|---:|---:|---:|
| `collect_changes` | 1 | 0.211944 | 0.530260 |
| `derive_reports_phase` | 1 | 0.007924 | 0.006916 |
| `derive_statistical_history_facet_delta` | 1 | 4.733942 | 12.923324 |
| `derive_statistical_history_facet_delta_partition` | 256 | 645.882103 | 593.953255 |
| `derive_statistical_unit` | 1 | 58.276487 | 59.924687 |
| `derive_statistical_unit_facet` | 1 | 4.630308 | 3.628840 |
| `derive_statistical_unit_facet_partition` | 256 | 61.468108 | 63.989845 |
| `derive_units_phase` | 1 | 0.003626 | 0.004244 |
| `derive_used_tables` | 1 | 13.962342 | 6.872172 |
| `statistical_history_facet_delta_reduce` | 1 | 40.169655 | 39.852760 |
| `statistical_unit_facet_reduce` | 1 | 22.399598 | 22.087313 |
| `statistical_unit_flush_staging` | 1 | 24.850828 | 25.002906 |
| `statistical_unit_refresh_batch` | 3,162 | 3,282.039711 | 3,311.931884 |

Refresh work remained dominant and did not decrease in aggregate task time. Its maximum individual task duration was 5.136914 seconds before and 5.029166 seconds after. There is no measured basis here for claiming the expected large recalculation gain. Further statement-level profiling is separately tracked in STATBUS-598, not silently included in this completed serial reference.

All stock/history/job outputs and the entire canonical graph were preserved across the separate recalculation. All three input post-hashes passed. The final monitor reported rc.03 healthy across services, API, site, disk, backups, upgrader and worker, with no failed or stuck worker tasks. Target source remained `fc1830fe410b19007056ef0853ad9e491d7f4ad9`; tracked files remained unchanged and pre-existing untracked support/configuration files were retained.

## Output acceptance

| Job | Input rows | Imported | Rejected | Warnings |
|---|---:|---:|---:|---:|
| Legal units | 1,134,476 | 1,134,475 | 1 | 53,592 |
| Establishments | 823,768 | 823,767 | 1 | 26,321 |
| Relationships | 33,710 | 29,504 | 4,206 | 0 |

All jobs reached `finished`. The rejected rows and errors are identical to the retained old baseline, including the two physical-country validation errors and 4,206 unknown relationship-type rows. These input rejections are not failed worker tasks. The controlled job validity date is **November 7, 2026**, matching the old comparison. It is a benchmark control, not approval of the unresolved general import-date policy.

Exact stock outputs are 823,767 establishments, 1,134,475 legal units, 1,134,475 enterprises and 25,635 power groups. All eight year/year-month history rows, including existence/countability and births/deaths/name-change counts, match the reference.

The independent canonical graph comparison found **zero removed and zero added records** across:

- 29,504 relationship edges, including topology, grouping, percentage and periods.
- 25,635 power-group records and their attributes.
- 53,268 membership records, identified by business keys and periods.
- 444 root records.

Both baseline and new load have 29,496 leveled relationship records. This dataset does not demonstrate a level-count correction, and none is claimed. Canonical keys avoid confusing regenerated internal IDs with changes in business output.

## Candidate, host and clean reset

The owner authorized the Norway reset, entire dataset and separate full recalculation on November 8 at **21:33 UTC**. The target is `no.statbus.org`, on `rune.statbus.org`, standalone slot `no`, database `statbus_no`. The supported named-candidate upgrade completed at **21:49:06.990803**, followed by the explicitly authorized clean database recreation and `./sb install --non-interactive`, which completed at **21:53:19**, exit zero.

The reset removed only the verified slot-specific database volume `statbus-no-db-data`. The installation retained its 15 users and configuration. Fresh readiness checks established zero import jobs/units, exact published serial seed/function definitions, migrations `20261108104710`, `20261108104712`, `20261108104714`, default import concurrency **one**, and healthy services/API/site/worker/upgrader. Norway had not previously applied the removed `711`/`713` migrations. Its reset was for this expressly requested clean reference, not proof that obsolete migration objects existed there.

The database container has a **32 GiB** memory limit. The host has eight logical CPUs and approximately 62.6 GiB RAM. PostgreSQL is **18.6**. Relevant settings are shared buffers 8 GiB, effective cache 24 GiB, work memory 1 GiB, maintenance work memory 2 GiB, 30 connections, four parallel workers, two per gather, effective I/O concurrency 200, random page cost 1.1 and JIT enabled. Queue defaults are import 1, analytics 4 and maintenance 1. No queue override was installed.

Published image digests actually running on the target:

| Component | SHA-256 digest |
|---|---|
| Database | `637dba296650eb0d4de71b513636f98586d4c98cf18472ede6987a20451b6d6a` |
| Application | `43d06912db8ed31c3203ebbf62ef2621b2dad433e67b0d788afcfcc6d5d74ec4` |
| Worker | `01cf8949587651a57ede2e6e12123f74751bdb9e1faed08a50405f58277f2db6` |
| Proxy | `dd95dbb990ec3b18cd4a3f4c9221605bc732588718d733882883d48fe48bc177` |

The CLI SHA-256 is `33bdd395ac9522304163400253800be91413a7b5cc8a7117a15813a7a2d3ea09`, matching the published manifest. The manifest records image tags, not image digests. No direct manifest-to-digest comparison is claimed.

## Complete input identity

The literal `samples/norway/brreg/brreg-import-downloads-from-tmp.sh` loader used all three retained files, with no sampling or truncation:

| File under `tmp/` | Bytes | SHA-256 |
|---|---:|---|
| `enheter.csv` | 708,352,495 | `f14b6f792bb89c53085d1743298dedafbef45ef785f36c21387c56548e8739a6` |
| `underenheter_filtered.csv` | 235,859,636 | `1e207c750ce965ac5ec6e7e36538243981d43b813fccd405fa9b14e10a116a28` |
| `roller_legal_relationships.csv` | 1,006,875 | `707091a1d6950d042c4a563c00f2067d0ab74914e3ef15cbe78b4f29126f2862` |

These match the old run B hashes and sizes. The runner also verifies all three hashes after the separate recalculation.

## Retained recovery material and evidence

A fresh database backup was completed before recreation:

- `dbdumps/no_20261108_223654.pg_dump`, 2,744,843,430 bytes, SHA-256 `36d6575762d6d3d5c2c49442748a8616f1c5c0098cf2b5d2a752b9644400ec10`.
- SHA verification, archive listing and full `pg_restore --file=/dev/null` archive read passed. This verifies archive readability, not an actual restore into another database.
- The associated 36 log files and existing physical pre-upgrade snapshot are retained.
- Secure configuration/users/binary/untracked archive: `/home/statbus/statbus-retained/597-serial-rc03-20261108/config-and-untracked.tar.gz`, 11,175,118 bytes, SHA-256 `4f85f5be777d602c96524a0939d2b23533a945e3f012f56b06cfa859b3f3d322`, protected by directory mode 700/file mode 600. No credentials are included in this report.

Raw evidence is retained on the target under `/home/statbus/statbus/tmp/rune-measure/C-serial-rc03/`, with the root checkout copy under `tmp/rune-measure/C-serial-rc03/`. Key files are:

- `recreate.log`, `recreated-readiness.log`, `recreated-definitions.out`, `recreated-state.json`.
- `inputs.sha256`, `input-sizes-before.txt`, `upload.log`, `upload.exit`, `run-meta.txt`.
- `baseline-outputs.json`, `baseline-errors.jsonl`, `baseline-graph.jsonl`, `baseline-recalculation-timings.json`.
- `after-load-outputs.json`, `after-load-parity.json`, `after-load-errors.jsonl`, `after-load-graph.jsonl`, `import-timings.json`.
- `baseline-vs-rc03-graph-summary.json`, `baseline-vs-rc03-graph-differences.jsonl`.
- `recalculation-request.json`, `recalculation-status.jsonl`, `recalculation-timings.json`, `recalculation-parity.json`, `independent-recalculation-parity.json`.
- `after-recalculation-outputs.json`, `after-recalculation-graph.jsonl`, `input-hashes-after.txt`, `final-monitor.json`, `independent-final-host.out`, `run.exit`, `run-stopped`.

Independent checks recomputed elapsed time from the saved task timestamps, reconciled every per-command task count to the full 3,684-task tree, reran stock/history/job parity, compared canonical graph bytes and baseline error bytes, and verified the final idle state. The final monitor sample at **00:10:22** was after the actual last task completion.

Old baseline evidence is also retained under `tmp/rune-measure/B/` and `tmp/rune-measure/reports-rc04-20261108/`. A monitoring-window timeout is not a failed workload or a completed benchmark. The remote durable runner, its genuine `run.exit` and the terminal pipeline checks determine the final result.
