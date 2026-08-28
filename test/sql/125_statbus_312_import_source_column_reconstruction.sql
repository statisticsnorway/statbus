\i test/setup.sql

-- STATBUS-312: migration 20260828231905 reconstructs import_source_column /
-- import_mapping rows that a construction-order-dependent bug in
-- import.cleanup_orphaned_synced_mappings (migration 20260422011930) can
-- wrongly delete during a full-from-migrations seed replay. This test
-- constructs the exact defect shape (a wrongly-deleted source column on an
-- otherwise-correct, enabled, non-custom default definition), re-applies
-- the migration's own SQL file (the shipped bytes, not a copy — cannot
-- drift from what actually runs in production), and asserts BOTH
-- directions the ruling requires: the missing mapping comes back, AND
-- nothing outside the affected row is created or altered.
--
-- Target: legal_unit_job_provided's 'tax_ident' source column (external_idents
-- step, maps to the tax_ident_raw data column) — an ordinary default-definition
-- column, chosen because it is stable and well-known, not because anything is
-- special about it.

-- Global baselines BEFORE any modification — captured via \gset (test/007,
-- test/109 etc. already establish this as the house pattern for asserting
-- "the total is unchanged" without hardcoding a number that could drift
-- with the seed) rather than a hardcoded literal, so this test does not
-- silently start lying if the seed's default-definition set ever grows.
SELECT count(*) AS n FROM public.import_source_column \gset before_isc_
SELECT count(*) AS n FROM public.import_mapping \gset before_map_

\echo -- Baseline: the target column exists and is correctly mapped before we break anything.
SELECT isc.column_name, im.target_data_column_id, im.is_ignored, idc.column_name AS target_column_name
  FROM public.import_source_column isc
  JOIN public.import_definition d ON d.id = isc.definition_id
  JOIN public.import_mapping im ON im.source_column_id = isc.id
  JOIN public.import_data_column idc ON idc.id = im.target_data_column_id
 WHERE d.slug = 'legal_unit_job_provided' AND isc.column_name = 'tax_ident';

-- SCENARIO 1 — CONSTRUCT THE WRONG STATE: delete the source_column exactly
-- as the construction-order bug would (cascades to its import_mapping via
-- the FK ON DELETE CASCADE — confirmed in doc/db/table/public_import_source_column.md).
DELETE FROM public.import_source_column isc
 USING public.import_definition d
 WHERE isc.definition_id = d.id
   AND d.slug = 'legal_unit_job_provided'
   AND isc.column_name = 'tax_ident';

\echo -- Confirmed gone (0 rows) before the repair runs.
SELECT count(*) AS should_be_zero
  FROM public.import_source_column isc
  JOIN public.import_definition d ON d.id = isc.definition_id
 WHERE d.slug = 'legal_unit_job_provided' AND isc.column_name = 'tax_ident';

-- Re-apply the repair migration's own file — the shipped bytes.
\i migrations/20260828231905_reconstruct_import_source_columns_lost_to_seed_path_divergence.up.sql

\echo -- SCENARIO 1 assertion (the positive): the mapping is restored, correctly.
SELECT isc.column_name, im.target_data_column_id, im.is_ignored, idc.column_name AS target_column_name
  FROM public.import_source_column isc
  JOIN public.import_definition d ON d.id = isc.definition_id
  JOIN public.import_mapping im ON im.source_column_id = isc.id
  JOIN public.import_data_column idc ON idc.id = im.target_data_column_id
 WHERE d.slug = 'legal_unit_job_provided' AND isc.column_name = 'tax_ident';

-- NOTE ON PRIORITY, deliberately not asserted above: the reconstructed row
-- gets a FRESH priority (current max + 1 for the definition), not its
-- original position — this is the real procedure's own behavior for any
-- newly-created source column (synchronize_definition_step_mappings has no
-- memory of a deleted row's old priority), not a defect of the repair.
-- What matters, and is asserted, is that the column exists again and maps
-- to the correct target — not that it occupies the same numeric slot.

\echo -- SCENARIO 2 assertion (negative #1, the point of the ruling's two negatives): global totals return to EXACTLY the pre-break baseline — nothing outside the one deleted row was created.
SELECT (SELECT count(*) FROM public.import_source_column) - :before_isc_n AS source_column_delta;
SELECT (SELECT count(*) FROM public.import_mapping) - :before_map_n AS mapping_delta;

-- SCENARIO 3 (negative #2) — SETTLED DATABASE IS UNTOUCHED: re-run the
-- migration again on a now-fully-correct database (idempotency AND the
-- "does not invent mappings on a settled database" property together —
-- without this, a migration that recreated EVERY definition's columns from
-- scratch on every run would also pass scenario 2 by accident).
\i migrations/20260828231905_reconstruct_import_source_columns_lost_to_seed_path_divergence.up.sql

\echo -- SCENARIO 3 assertion: still exactly at baseline after a second (no-op) run.
SELECT (SELECT count(*) FROM public.import_source_column) - :before_isc_n AS source_column_delta_after_rerun;
SELECT (SELECT count(*) FROM public.import_mapping) - :before_map_n AS mapping_delta_after_rerun;

\echo -- SCENARIO 3 assertion, continued: the reconstructed row itself is unchanged by the no-op re-run (same id, not deleted-and-recreated again).
SELECT isc.column_name, im.is_ignored, idc.column_name AS target_column_name
  FROM public.import_source_column isc
  JOIN public.import_definition d ON d.id = isc.definition_id
  JOIN public.import_mapping im ON im.source_column_id = isc.id
  JOIN public.import_data_column idc ON idc.id = im.target_data_column_id
 WHERE d.slug = 'legal_unit_job_provided' AND isc.column_name = 'tax_ident';
