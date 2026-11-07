# STATBUS-591: concurrent processing of one import job's batches (design draft)

Status: implemented on local branch `statbus-591-import-speed`, not released. Whole-slot grouping passed
127 shared and two isolated fast tests. Concurrent scheduling passed its private SQL regression and a
small simultaneous-connection parity probe. A graph extension of that probe found a chosen-root identity
difference after concurrent new legal-unit allocation. Full-suite and real-worker BRREG measurements are
pending, and unrestricted legal-unit concurrency is not yet an exact-output-equivalent release candidate.
Evidence: `tmp/journal.md`, `tmp/591/`, `tmp/rune-measure/A/import-tasks.out`.

## Where the time goes (rune run A, rc.18, full BRREG)

| Job | Analysis | Processing | Processing shape |
|---|---:|---:|---|
| Legal units, 1,134,476 rows | 811 s | 2,139 s | 142 batches of 8,000 rows, 12-35 s each, one at a time |
| Establishments, 823,768 rows | 739 s | 1,643 s | 103 batches, same |
| Relationships, 33,710 rows | 1,147 s | 60 s | power_group_link analysis 1,024 s on rune |

Processing is 3,782 s of the 6,625 s import queue. Analysis batches are 1-3 s each (32,768 rows), so the gain is
in processing.

The equality-join analysis prototype took 0.66 s on the local full-file fixture, versus 264 s locally before
the change. It has not yet been measured against rune's 1,024 s baseline. Legal-unit and establishment
times in this table sum their batched step tasks, not every phase-transition invocation.

## What two concurrent batches could collide on (process phase, one transaction per batch)

1. **Trigger toggling.** A batch with any non-insert row runs `ALTER TABLE ... DISABLE TRIGGER` on seven unit
   tables. Its table lock is held to commit and serializes conflicting batches. Trigger DDL is transactional,
   so no cross-session trigger-state race has been demonstrated. Such batches stay serial in this prototype.
   A fresh insert-only load skips the toggle.
2. **One unit in two batches.** `temporal_merge` on the same unit, and the enterprise created for a new legal unit.
3. **Primary establishment.** A formal establishment row that is primary demotes the legal unit's current primary:
   two batches with establishments of one legal unit race.
4. **Job counter.** `import_job.imported_rows` is incremented atomically at each batch's transaction tail.
   Keeping that short update preserves live progress. Measure contention before replacing it with a final recount.

## Grouping: which rows must share a batch

`import.analyse_external_idents` (step 15, before any processing) already gives every row a unit key in
`founding_row_id`: existing legal unit `id + 1e9`, existing establishment `id + 2e9`, new unit the row_id of its
first row. All rows of one unit share it.

| Job mode | Group key |
|---|---|
| legal_unit, establishment_informal | `founding_row_id` |
| establishment_formal | `legal_unit_id` (resolved by step 19), else `founding_row_id` |
| legal_relationship | rows are independent; `power_group_link` stays holistic |

## Two levels, as for statistical units

- **Level 1, slot:** hash the dependency-group key into 16,384 import slots. The key uses a resolved legal unit,
  enterprise or founding row, depending on the columns available. This shares derive's slot count, not its
  key identities, and does not establish matching derive partitions.
- **Level 2, batch:** consecutive occupied slots packed toward `processing_batch_size` rows. A slot, including
  all of its dependency groups, belongs to one batch. Oversized slots remain whole and may leave batch-number
  gaps. Use explicit floor division because PostgreSQL's `sum(bigint)` is numeric and an integer cast rounds.

Do batch numbers have to stay the same between runs?
- **Derive:** yes. Partitions, staging and history deltas are keyed by slot, so a unit's slot must never change.
- **An import job's batches:** no. They are assigned once, after analysis, and used once. They only need to be
  fixed for the life of the job (they are, in the data table) and balanced. Re-running a job reassigns them.
- **Why two levels:** dependencies determine stable groups, while a row-size target determines the number of
  transactions. Changing the target moves slot boundaries without splitting a dependency group. There is no
  measured derive-locality benefit yet. Unit refresh itself uses temporally closed change sets, not this packing.
- New units have no persistent id yet, so their import key uses the founding row. It need only remain stable
  within this job. Moving an establishment between parents across its historical rows can bridge group keys:
  concurrent dispatch must verify that each founding unit remains in one batch and fall back to serial if not.

Packing refreshes the import data table's `action` statistics once after analysis and before dispatch.
Upload-time statistics describe NULL actions, not the accepted rows being packed. On a 24,000-row fixture,
that stale estimate made slot aggregation repeat inside a nested loop and exceeded the 10-second test
limit. Refreshing only `action` kept the same assignment and completed the regression in 0.27 seconds.

## Running the batches

In `processing_data`, one `import_job_process` task spawns one child per batch under a concurrent parent;
the import queue gets concurrency N. Holistic process steps and the transition to `finished` run after the
children, as the next serial step. Different import jobs remain serial because their inputs can depend on
previous jobs. The existing worker already has concurrent fibers and a child barrier, so this needs no
Crystal worker change. The migration leaves the queue's default concurrency unchanged at one.

The first dispatch scope is deliberately narrow:
- New legal units with new enterprises, or new formal establishments with resolved legal-unit parents.
- Every processing row is an insert and every founding unit belongs to one batch.
- Every non-holistic processing handler belongs to the known unit, location, activity, contact, statistical
  variable or tag handlers. A custom handler retains serial execution until its dependencies are understood.

Mixed operations, reused unit targets and informal establishments retain serial execution. A clean file
with multiple historical versions can still analyse as mixed insert/replace operations and remain serial.
That is an implementation boundary, not a claim that concurrent updates are logically impossible.
Deferring SQL Saga's temporal constraint checks may remove trigger-DDL serialization, but dependencies
and final-state integrity must still be established separately.

Each batch holds a transaction-scoped advisory lock, publishes row states and its atomic counter delta in
the same transaction, and treats an already committed batch as a zero-work replay. A unique task index
records one leaf per job and batch. Batch failures roll back domain writes and fail the worker leaf. Its
after-procedure records the failed job and row diagnostics outside the worker's handler savepoint, so the
failed state survives rollback and propagates through parent fan-in. Completed siblings may remain
committed, as with earlier serial batches. Holistic steps cannot run after a failed fan-in.

### Open compatibility boundary: ambiguous power-group roots

`import.process_power_group_link` chooses the smallest natural-root legal-unit ID for a multi-root group,
or the smallest influencing-member legal-unit ID for a cycle. Excluding terminal members repairs a
previous failure when the smallest component member could not satisfy root-membership validation.
Every previously valid minimum-ID choice remains unchanged. These are surrogate IDs. Concurrent insertion of new
legal units changes allocation order, so the same graph can choose a different logical root even though
its relationships, membership, BFS levels and cycle/multi classification are unchanged. An exact graph
probe reproduced three such differences at concurrency four or eight. Chosen root identifiers remain in
the parity checks. No business-key root-selection policy has been introduced.

Keeping legal-unit processing serial while parallelizing formal establishments is a narrower candidate
that preserves allocation order relative to this branch's serial phase with the same whole-slot packing.
A fresh 400-LU/800-ES experiment plus nine relationships passed
exact domain and chosen-root parity at four-way ES concurrency. Parallel legal-unit
processing needs either equivalent deterministic allocation or an explicitly agreed root-selection policy
before it can satisfy strict chosen-root parity. The small unit-only speed measurements below do not
establish that compatibility. These references do not restore the released batch-packing function.
Packing itself can reorder surrogate allocation, so this experiment does not establish chosen-root
identity parity against the pre-591 release.

## Verification

- SQL373 asserts complete historical units, complete legal-unit parent groups, exact row-target packing and
  whole hash slots, including a collision between different dependency keys.
- SQL376 asserts assignment and state/priority transitions for 24,000 accepted rows after analysis changed
  upload-time NULL actions, with complete dependency groups, exact whole-slot packing and bounded runtime.
- SQL375 exercises real worker fan-out, per-leaf progress, replay, the serial continuation barrier, complete
  holistic input, exact final unit/version totals and mixed/existing/informal serial fallbacks. Its injected
  batch-tail error occurs after real unit writes and asserts rollback plus failed leaf, job and wrapper.
  This regression uses one connection and does not establish cross-connection locking behaviour.
- SQL378 asserts exact memberships and levels for a cycle with a lower-ID terminal tail, a previously
  valid cycle, a natural-root chain and a multi-root component. It verifies bounded root validity,
  influencing-member eligibility, preserved custom overrides and stable group identities on replay.
- `tmp/591/concurrent-acceptance.py` uses simultaneous PostgreSQL connections on identical private inputs:
  400 new legal units and 800 new formal establishments. All nine imported domain tables match the
  original serial function after generated-ID and audit-timestamp normalization, including parent links,
  versions and exact counters. Observed active leaves reach the configured 2, 4 and 8.

| Execution | Wall time |
|---|---:|
| Original serial function | 20.437 s |
| Two connections | 8.415 s |
| Four connections | 7.791 s |
| Eight connections | 7.847 s |

These are small-fixture measurements in a fixed run order, not a production speed claim. The real Crystal
worker results below supersede any inference of a production gain from this fixture.

### Real Crystal worker: BRREG selection before deferred-wakeup prototype

Fresh identical private databases received the same 4,924 legal units, 24,027 establishment input rows
and two relationships. Each run imported 24,026 establishments and produced the same one input error.
Every normalized row in twelve domain tables and all per-job counters matched the original serial
function. History checks A (incremental versus rebuild), B (ground truth) and C (drained staging) passed.

| Import queue concurrency | Worker wall | Import queue span | Peak active batch leaves | Lock-wait samples |
|---|---:|---:|---:|---:|
| Original serial function | 82.644 s | 70.593 s | 0 | 12 |
| 2 | 89.000 s | 76.022 s | 2 | 127 |
| 4 | 88.776 s | 69.151 s | 4 | 165 |
| 8 | 87.719 s | 67.794 s | 4 | 179 |

There is no accepted end-to-end concurrency speedup in these measurements. The selection has one
legal-unit processing batch and four establishment batches, so eight fibers cannot produce eight active
leaves. It has no cycle/multi-root records and does not establish their chosen-root compatibility.

Live lock inspection identified `worker.base_change_log_has_pending` as the shared tuple blocking
independent batches. `worker.log_base_change` updates that singleton at the first domain write and
retains its lock until the batch commits. A scratch prototype is testing publication of the pending bit,
collector task and notification at the batch tail while preserving every transactional change-log append.
This is not temporal constraint deferral. The durable bit must still commit with the domain changes,
because it is the crash witness for the unlogged change log.

Evidence: `tmp/591/selection-v2-results.json`, per-run row snapshots and 0.2-second lock samples, and
`tmp/591/selection-v2-n4-live-blockers.txt`. Sampled whole-DB-container memory peaked between 5.75 and
6.02 GiB. That includes shared buffers and cached data from other retained databases, not an isolated
per-run memory footprint. Runs used a fixed order. Deferred-wakeup verification, the final full regression
suite, full-download comparisons and Norway acceptance remain before choosing production concurrency.
