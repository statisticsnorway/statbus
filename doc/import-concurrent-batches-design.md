# STATBUS-591: concurrent processing of one import job's batches (design draft)

Status: draft for the owner (not implemented). Branch `statbus-591-import-speed`. Evidence: tmp/journal.md 13:57, 16:15;
tmp/rune-measure/A/import-tasks.out.

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
   tables, a table lock held to commit and a global state. Such batches stay serial. A fresh load (BRREG) is
   insert-only and never toggles.
2. **One unit in two batches.** `temporal_merge` on the same unit, and the enterprise created for a new legal unit.
3. **Primary establishment.** A formal establishment row that is primary demotes the legal unit's current primary:
   two batches with establishments of one legal unit race.
4. **Job counter.** `import_job.imported_rows` is updated after every batch; becomes one update at the end.

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

- **Level 1, slot:** `hash_slot` of the group key, the same 16,384-slot space derive uses
  (`abs(hashtext(type || ':' || id)) % 16384`). For existing units the slot is the unit's own `hash_slot`.
- **Level 2, batch:** consecutive slots packed into batches of about `processing_batch_size` rows, so a batch is
  a range of slots and a group never splits.

Do batch numbers have to stay the same between runs?
- **Derive:** yes. Partitions, staging and history deltas are keyed by slot, so a unit's slot must never change.
- **An import job's batches:** no. They are assigned once, after analysis, and used once. They only need to be
  fixed for the life of the job (they are, in the data table) and balanced. Re-running a job reassigns them.
- **Why still use the derive slot:** for existing units, a batch then covers one derive slot range, and the
  `collect_changes` cycle after it touches a few partitions per batch instead of all. Whether that speeds up
  the derive after an import is measured, not assumed; if it does not, level 1 can be any stable hash of the key.
- New units have no id yet, so their level-1 key is the founding row. Their derive slot is decided only when the
  unit exists, so alignment applies to updates of existing units, which is the case where derive cost matters.

## Running the batches

In `processing_data`, one `import_job_process` task spawns one child per batch under a concurrent parent;
the import queue gets concurrency N. Holistic process steps and the transition to `finished` run after the
children, as the next serial step. Batches that would toggle triggers run serially (prototype rule).

## Proof

- pg_regress: a job with several rows per unit, establishments of one legal unit with primary changes, new and
  existing units, processed concurrently, gives row-for-row the units of a serial run; no two batches share a key.
- Benchmark: selection and full downloads, N = 1, 2, 4, 8: wall, import queue span, derive after the import,
  memory, lock waits; row-for-row unit comparison against a serial run (AC1).
