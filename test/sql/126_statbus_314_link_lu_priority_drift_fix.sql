\i test/setup.sql

-- STATBUS-314/108 family: import.generate_link_lu_data_columns() computed
-- its base priority as MAX(priority) over ALL rows in the step -- including
-- its own previously-inserted dynamic rows -- so every additional
-- INSERT/UPDATE/DELETE on public.external_ident_type (each fires this via
-- the external_ident_type_lifecycle_callbacks_after_* triggers ->
-- lifecycle_callbacks.cleanup_and_generate(), statement-level) re-based off
-- its own last output and drifted the priority upward forever, independently
-- on every database that ever made such an edit. Verified empirically,
-- non-destructively, on a live database before writing this migration: two
-- extra calls with 2 active ident types climbed the dynamic priorities +2,
-- then +2 again.
--
-- Migration 20260829103700 fixes the formula to a pure function of a
-- TARGETED static-row lookup (never a MAX, filtered or otherwise) plus the
-- ident type's own priority -- matching import.generate_stat_var_data_columns'
-- already-idempotent-by-construction pattern (architect review) -- and
-- converges any already-drifted database to that value in the same
-- migration. Architect's formula-authority ruling: "the fleet is
-- authoritative when coherent; where a defect made it incoherent, the
-- definition is authoritative and every box converges to it."
--
-- Three cases, per the architect's review (the usual test only covers the
-- first):
--   (a) twice-in-a-row -> identical           (idempotence itself)
--   (b) already-correct -> untouched          (a settled database is left alone)
--   (c) DRIFTED state -> converges to correct (the single CALL actually
--       repairs a real box, regardless of how it got there -- this is
--       what discharges the "does 312/314 interplay matter" question:
--       converging from an ARBITRARY starting point proves ordering
--       relative to anything else that ever ran is irrelevant)

\echo -- Baseline: the seed has already applied this migration once (it ships with every seed build), so this state is already the corrected, converged one.
SELECT idc.priority, idc.column_name, idc.purpose
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit'
 ORDER BY idc.priority;

SELECT idc.priority AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' AND idc.column_name = 'primary_for_legal_unit' \gset static_
SELECT idc.priority AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' AND idc.column_name = 'legal_unit_tax_ident_raw' \gset baseline_
SELECT count(*) AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' \gset baseline_total_

-- CASE (b) -- ALREADY-CORRECT -> UNTOUCHED: a single extra call on a
-- settled database must be a complete no-op.
CALL import.generate_link_lu_data_columns();

SELECT idc.priority AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' AND idc.column_name = 'legal_unit_tax_ident_raw' \gset caseb_
SELECT count(*) AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' \gset caseb_total_

\echo -- CASE (b) assertion: one call on an already-correct database changes nothing -- same priority, same row count.
SELECT :caseb_n = :baseline_n AS case_b_priority_untouched,
       :caseb_total_n = :baseline_total_n AS case_b_row_count_untouched;

-- CASE (a) -- TWICE-IN-A-ROW -> IDENTICAL: the idempotence property
-- itself, independent of whether the prior state happened to be correct.
CALL import.generate_link_lu_data_columns();
SELECT idc.priority AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' AND idc.column_name = 'legal_unit_tax_ident_raw' \gset casea1_

CALL import.generate_link_lu_data_columns();
SELECT idc.priority AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' AND idc.column_name = 'legal_unit_tax_ident_raw' \gset casea2_

\echo -- CASE (a) assertion: two consecutive calls produce the IDENTICAL priority -- this is exactly the property the old formula violated (proven empirically: +2 per call with 2 active types, before this fix).
SELECT :casea1_n AS call_1, :casea2_n AS call_2, :baseline_n AS original_baseline,
       (:casea1_n = :casea2_n AND :casea2_n = :baseline_n) AS all_identical;

-- CASE (c) -- DRIFTED STATE -> CONVERGES TO CORRECT: simulate a fleet box
-- that accumulated an unknown amount of drift from its own history of
-- external_ident_type churn. The exact wrong value does not matter --
-- that is the point: convergence must not depend on how far a box had
-- drifted, or in what order anything else (including STATBUS-312's own
-- repair) ran before it.
UPDATE public.import_data_column idc
   SET priority = idc.priority + 37
  FROM public.import_step s
 WHERE s.id = idc.step_id
   AND s.code = 'link_establishment_to_legal_unit'
   AND idc.purpose = 'source_input';

\echo -- Confirmed arbitrarily drifted before the repair runs.
SELECT idc.priority, idc.column_name
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' AND idc.purpose = 'source_input'
 ORDER BY idc.priority;

-- Re-apply the repair migration's own file -- the shipped bytes -- the
-- actual mechanism that would repair a real box.
\i migrations/20260829103700_fix_generate_link_lu_data_columns_non_idempotent_priority_drift.up.sql

SELECT idc.priority AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' AND idc.column_name = 'legal_unit_tax_ident_raw' \gset casec_
SELECT idc.priority AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' AND idc.column_name = 'primary_for_legal_unit' \gset casec_static_
SELECT count(*) AS n
  FROM public.import_data_column idc
  JOIN public.import_step s ON s.id = idc.step_id
 WHERE s.code = 'link_establishment_to_legal_unit' \gset casec_total_

\echo -- CASE (c) assertion: converged back to the SAME value as the original baseline, regardless of the arbitrary +37 drift -- proving the target is the definition, not "whatever it was."
SELECT :casec_n = :baseline_n AS case_c_converged_to_original,
       :casec_static_n = :static_n AS case_c_static_column_untouched,
       :casec_total_n = :baseline_total_n AS case_c_row_count_unchanged;
