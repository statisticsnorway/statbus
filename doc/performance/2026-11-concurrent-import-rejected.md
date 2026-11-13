# Decision: stop pursuing concurrent import batches

**Decision date:** November 13, 2026. **Status:** rejected by the owner after the full-register comparison. **Tracker:** STATBUS-591.

Keep import processing serial. Do not land the concurrent batch dispatcher, its batch-tail wakeup changes, or its four-worker default from the experimental branches. This decision does not withdraw the separate serial power-group and collector fixes already on master.

## What we tried

Dependency-closed LU/establishment batches ran through the existing worker with either one or four import workers. Jobs remained ordered and holistic power-group work remained serial. Earlier small fixtures showed overlapping batches and shorter runtimes. The full-register measurement below did not reproduce an overall speedup.

The November 12–13 comparison used the same 8-core bench host, the same input files, a fresh database for each round, and serial/concurrent/concurrent/serial order. Both configurations used the experimental implementation, changing only whether the final migration enabled four import workers. Therefore the one-worker measurements are a concurrency control, not a direct measurement of unchanged master.

- One worker: `ee3a51dfb2d38266aecc10603bfc221dd818fff1`, branch `statbus-591-serial-bench`.
- Four workers: `da11950e1f40f76a429a17ceb56c4ce0f164d4cd`, branch `statbus-591-concurrency-rebased`.
- Run identity: `20261112T193846Z`. Local raw evidence: `tmp/bench/20261112/box/20261112T193846Z/`, including `run.log`, `round-*.log`, worker logs and fingerprints. These files are retained locally, not shipped with the documentation.

## Results in minutes

“Import to idle” includes analytics that run alongside import. “Later recalculation” is a separate explicit full recalculation after that idle point, not time to add to the import-only work inside its overlapping queues.

| Round | Import workers | Import to idle | Later recalculation | Failed tasks |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1 | 159.7 | 19.9 | 0 |
| 2 | 4 | 173.3 | 18.5 | 0 |
| 3 | 4 | 168.3 | 19.2 | 0 |
| 4 | 1 | 150.5 | 20.4 | 0 |

Mean import-to-idle time was **155.1 minutes with one worker versus 170.8 minutes with four**, about **15.7 minutes slower**. Both concurrent runs were slower than either serial run.

All four rounds completed 245 import processing batches. Their summed execution times were 89.7/88.8 minutes in the serial rounds and 237.6/200.6 minutes in the concurrent rounds. These are sums across tasks, not wall times. Analytics scheduling also differed: statistical-unit staging flushed 32/33 times in serial rounds versus nine in each concurrent round.

Round 4 initially refused an incompatible cached seed, then fetched the seed for its exact serial source and recreated the template before timing the import. The refusal and recovery are preserved in its log.

## Why we stopped, and what we do not know

The owner chose to discard this approach because the full workflow became slower and pursuing concurrent writes adds contention and locking concerns without a demonstrated benefit on this workload. The measured increase in batch execution time is consistent with contention. This run did not capture lock-wait attribution, so a particular lock is **not a proven explanation**. Import/analytics overlap and the bench memory configuration also limit extrapolation to other hosts. The later 15 GiB search-index comparison is a different experiment, not a revised import measurement.

No failed tasks is not proof of identical business results. Raw fingerprints differ in every round, including the two serial rounds. Surrogate allocation can change hashes, but these artifacts alone do not prove that it explains every difference. Most table counts agree, while facet-staging counts differ. These runs are timing evidence, not a completed normalized semantic-parity acceptance. Earlier retained serial/concurrent probes established matching memberships in their scope and separately reported automatic-root differences.

## Consequences

- Keep master's serial import behavior. The rejected candidate is not on master, so this decision requires no runtime revert.
- Preserve branch SHAs, diagnostics and earlier regression evidence as the record of the experiment. Discarding the approach does not authorize deleting retained databases or worktrees.
- Retire the pending concurrency eligibility, recovery and root-policy reviews as gates for this abandoned implementation. Independent validity-date, security and cleanup decisions remain separate.
- Reopen concurrency only through a new owner-approved proposal with a concrete contention diagnosis, a matched end-to-idle speed improvement, and normalized business/temporal parity. Small-fixture parallelism alone is insufficient.

The [combined import review](2026-11-combined-import-review.md) retains the earlier integration and withdrawal history. Its older concurrency proposals and checklists do not override this decision.
