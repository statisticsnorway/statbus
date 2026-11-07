# STATBUS-591: concurrent processing of one import job's batches (design draft)

Status: implemented on local branch `statbus-591-import-speed`, not released. Whole-slot grouping passed
127 shared and two isolated fast tests. Concurrent scheduling passed its private SQL regression and a
small simultaneous-connection parity probe. Full-suite and real-worker BRREG measurements are pending.
Evidence: `tmp/journal.md`, `tmp/591/`, `tmp/rune-measure/A/import-tasks.out`.

## Where the time goes (rune run A, rc.18, full BRREG)

| Job | Analysis | Processing | Processing shape |
|---|---:|---:|---|
| Legal units, 1,134,476 rows | 811 s | 2,139 s | 142 batches of 8,000 rows, 12-35 s each, one at a time |
| Establishments, 823,768 rows | 739 s | 1,643 s | 103 batches, same |
| Relationships, 33,710 rows | 1,147 s | 60 s | power_group_link analysis 1,024 s (fixed: 0.7 s) |

Processing is 3,782 s of the 6,625 s import queue. Analysis batches are 1-3 s each (32,768 rows), so the gain is
in processing.

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

## Verification

- SQL373 asserts complete historical units, complete legal-unit parent groups, exact row-target packing and
  whole hash slots, including a collision between different dependency keys.
- SQL375 exercises real worker fan-out, per-leaf progress, replay, the serial continuation barrier, complete
  holistic input, exact final unit/version totals and mixed/existing/informal serial fallbacks. Its injected
  batch-tail error occurs after real unit writes and asserts rollback plus failed leaf, job and wrapper.
  This regression uses one connection and does not establish cross-connection locking behaviour.
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
worker selection/full-download comparisons, memory and lock measurements, full regression suite and
Norway acceptance criteria remain to be completed before choosing a production concurrency setting.
