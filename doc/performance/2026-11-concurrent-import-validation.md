# Concurrent import validation, November 8, 2026

## Result and scope

The full BRREG downloads import completed with the real Crystal worker, the installed import queue default of four, and no queue overrides. The three jobs finished, all uploaded rows reconcile to accepted or rejected terminal rows, all 245 processing leaves completed, and the history consistency checks passed. Independent read-only reconstruction also passed for the imported power-group graph.

This is local correctness and actual-concurrency evidence, not a controlled production speedup measurement. The local database limit was 8 GiB, while the recorded Norway reference used 32 GiB. No experimental concurrency version was deployed to Norway by Hibiscus.

- Branch measured: `statbus-591-concurrency`.
- Exact source: `d25fef3d805db50918a133d0ead1eb8bf57ed840`.
- Runtime checkpoint: `f95da97d7f61450dc12a097cb7221cdee9ab0f81`.
- Serial base: `v2026.11.3-rc.03`, `fc1830fe410b19007056ef0853ad9e491d7f4ad9`.
- Retained isolated database: `import_benchmark_64469`.
- Three forward migrations: `20261108182300` through `20261108182302`.
- Ordinary temporal integrity checks stayed enabled. The SQL Saga deferral prototype was not adopted.
- Independent validation completed November 8 at 22:58:36 UTC, after the benchmark wrapper exited successfully at 22:57:52 UTC.

## Reproducible invocation and boundaries

```sh
./test/import_benchmark.sh --dataset downloads --valid-from 2026-11-07 \
  --timeout 14400 --no-debug --require-import-concurrency 2 \
  --result-json tmp/591/concurrency-v2/full-register/result.json
```

`--require-import-concurrency` asserts observed overlap. It does not change queue configuration. Installed queue settings were import 4, analytics 4 and maintenance 1. All three source SHA-256 checks passed both before and after the run and match the retained Norway A/B inputs. November 7 is an explicit benchmark date, not a decision about the application's default validity policy.

| Boundary | UTC |
| --- | --- |
| Loader started | 2026-11-08 19:48:27.152704 |
| Loader finished | 2026-11-08 19:48:43.206573 |
| Worker started | 2026-11-08 19:48:43.224799 |
| Worker finished | 2026-11-08 21:44:50.808929 |
| Wrapper, including later plan probes, finished | 2026-11-08 22:57:52 |

| Same-run wall measurement | Seconds |
| --- | ---: |
| CSV loading | 16.054 |
| First import analysis to last import processing completion | 4,764.540 |
| First import analysis to worker idle | 6,967.492 |
| Worker monotonic elapsed time | 6,967.459 |
| Loader start to worker idle | 6,983.656 |
| Wrapper including post-worker repeated-call diagnostics | 11,371.490 |

The wrapper time is not the import time. Post-worker diagnostics repeat analytics handlers in rollback-only transactions and account for the long interval after the worker had already finished.

## E1: six import phases and row outcomes

All three jobs used `default_valid_from = 2026-11-07`, ended in `finished`, and had no fatal job error. Analysis and processing durations below are wall intervals from the durable job timestamps, not sums of concurrent handlers.

| Job | Uploaded | Imported | Error rows | Warning count | Analysis seconds | Processing seconds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Legal units | 1,134,476 | 1,134,475 | 1 | 53,592 | 700.377 | 2,168.836 |
| Establishments | 823,768 | 823,767 | 1 | 26,321 | 754.667 | 750.476 |
| Legal relationships | 33,710 | 29,504 | 4,206 | 0 | 229.264 | 100.266 |

Every accepted row was actually `state = processed, action = use`. Every rejected row was actually `state = error, action = skip`. Error counts and skip counts describe the same rejected rows and must not be added together. Warning counts do not identify additional rejected rows. Zero failed worker tasks does not mean zero rejected input rows.

## E2: observed concurrency and sequencing

| Job | Completed processing leaves | Maximum overlapping leaves | Time with at least two overlapping leaves, seconds |
| --- | ---: | ---: | ---: |
| Legal units | 142 | 4 | 2,133.205 |
| Establishments | 103 | 4 | 709.467 |
| Legal relationships | 0 | 0 | 0 |

All 245 leaf intervals were complete. The independent collector reconstructed 2,842.672 seconds with at least two overlapping import leaves from durable start/stop intervals. Legal-relationship graph work remained serial. Import jobs remained ordered, and holistic processing did not run ahead of its processing fan-in.

The run ended with 13,882 completed tasks and three future pending maintenance tasks. No active, due or failed task remained in the independent acceptance snapshot.

## E3: business and history correctness

- Actual data-table terminal states and counters reconcile every uploaded row for each expected job.
- The existing history checks observed staging drained, incremental history equal to rebuilt history, and history equal to statistical-unit ground truth: zero divergent rows in each check.
- The eight year/month stock-summary rows exactly match the saved Norway B reference: establishments 823,767, legal units 1,134,475, enterprises 1,134,475 and power groups 25,635 in both periods.
- A separate read-only collector reconstructed all 29,504 accepted relationship records and their domain rows, 25,635 weak components and assigned groups, directed BFS edge levels, eligible automatic roots, custom-root eligibility and exact public memberships defined by reachable nodes.
- The graph has 53,276 nodes and 53,268 nodes reachable from the selected roots. The collector checks the defined directed reachability membership, not an invented requirement that every weak-component node be reachable from one selected root.
- The independent graph proof covers the imported uniform interval `[2026-11-07, infinity)`. It is not a historical A/B graph-snapshot equivalence proof and does not replace the separate mixed-interval regression coverage.
- No particular automatic root identity was required where the existing algorithm permits more than one eligible root. The separate business-attribute root-selection proposal was not included in this measured concurrency runtime.

Earlier bounded actual-worker evidence also covered genuine mixed LU, formal-establishment and informal-establishment updates, exact parent coverage and primary flags. The retained selection comparison matched twelve serial-reference business tables with domain validity dates preserved. Those checks are separate from this full-register clean import.

## E4: memory

The Docker sampler recorded 429 samples during the actual worker interval. Its highest observed database-container working set was **6.260 GiB out of an 8 GiB limit**, sampled at 20:59:36 UTC. This is a sampled container working set, not an exact database-process peak.

The 271 samples after worker completion belong to rollback-only diagnostics and are reported separately. Their maximum was 5.729 GiB. Neither interval should be mixed with the Norway run's 32 GiB limit or presented as proof of a causal memory improvement.

## E5: code-review findings and remaining landing work

The initial full import passed. Root review nevertheless identified additional acceptance and harness work before landing:

1. The hierarchy probe hardcoded January 1, 2025 and skipped the imported November 2026 data. This is a benchmark coverage defect, not proof that current entities are missing. Add an original failing caller-path regression, derive the snapshot from the measured jobs and execute all four real hierarchy probes at that date.
2. Benchmark success did not independently require the expected jobs to finish and all uploaded rows to reconcile. Add positive success criteria for pre-worker job identities and uploaded counts, fatal job errors, final states and actual data rows, with original-failure cases for failed, unfinished and missing jobs even when the worker exits zero.
3. Add literal cross-connection proof that a successful committed batch retains its exact domain version when a later batch fails, and that fan-in fails rather than invoking holistic processing.
4. Complete source-grounded actual-analysis coverage of establishment primary-demotion footprints, including shared old parents and different incoming targets. Existing fixtures with incoming primary flags false do not prove the primary-demotion case.

These items are tracked as executable todos. Their final source, tests and review evidence must be added before claiming landing readiness. No runtime defect is asserted merely because a coverage case was missing.

## B2: retry, duplicate safety and operator recovery

These are three different contracts:

- Existing worker deadlock/serialization retries are bounded, and apply only if that error reaches the worker boundary. An inner handler may translate an error into a failed job instead.
- Batch uniqueness and the job/batch advisory lock make duplicate processing calls safe. Already processed rows are not processed twice.
- A terminal failed import is not reset by duplicate invocation. Successful sibling batches already committed remain committed. The delivered change does not provide whole-job undo, a replay button or an operator recovery CLI.

The inspected jobs UI offers View Imported Data, state-gated Approve/Reject and Delete, not a recovery action. This is source inspection, not a new browser acceptance claim. Any genuine row combination that passes analysis but fails processing must be retained and brought back to improve analysis. Synthetic failure injection proves the failure contract, not the existence of a genuine analyzer omission. Owner decision B2 remains unresolved.

## E6: evidence, integration and authorization

Retained local evidence is under `tmp/591/concurrency-v2/full-register/`: original `result.json`, benchmark exit and logs, pre/post input checksums, `full-register-acceptance.json`, `graph-acceptance/report.json` and `memory-summary.out`. These diagnostic artifacts are not versioned database fixtures. Keep them until authorized cleanup.

Before this full import, all 143 PostgreSQL cases, full schema documentation, generated types, the actual migration up/down/up comparison, bounded mixed and selection workers, and exact branch application CI passed. New review repairs require their own relevant tests and an exact integrated-source CI result. A branch application check is not a full master gate.

Rabbit owns a separately authorized serial Norway reference import and subsequent full recalculation. Those operations are not deployment of this experiment. Compare that run only when its saved evidence is available; do not repeat the serial import locally or infer a controlled concurrency gain from different machines.

The overnight instruction is **reviewed landing only**. Coordinate the exact final diff with Rabbit before master push. No new release candidate, tag or stable release is authorized. Personal review of eligibility, failure recovery, automatic roots, validity defaults and residual security findings remains open.
