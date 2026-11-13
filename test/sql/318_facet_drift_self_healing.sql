-- Test 318: Facet drift self-healing under collapsed global MERGE reduce
--
-- Phase 3 of the counting-bug investigation. The previous Path B in
-- worker.statistical_unit_facet_reduce had a structurally incomplete
-- DELETE step (only reaches target rows whose dim+temporal IS IN
-- pre_dirty_dims). Stale rows could accumulate and not self-heal.
--
-- This test:
--   1. Loads a small demo dataset and runs the derive pipeline.
--   2. Verifies target = truth at CURRENT_DATE.
--   3. Injects a synthetic stale row into statistical_unit_facet —
--      simulating drift that Path B would have missed.
--   4. Calls worker.statistical_unit_facet_reduce directly (no pipeline).
--   5. Asserts the synthetic row is GONE — proving the new collapsed
--      MERGE is self-healing regardless of whether the dim+temporal of
--      the stale row was ever in pre_dirty_dims.
--
-- Under the BUGGY rc.42 Path B (≤128 dirty), the synthetic row would
-- survive: pre_dirty_dims wouldn't include the synthetic dim_tuple
-- (no staging row matches it), so the gating filter in the DELETE
-- step `WHERE dim_tuple IN pre_dirty_dims` excludes it. The fix uses
-- WHEN NOT MATCHED BY SOURCE THEN DELETE which is dim-tuple-agnostic.
--
-- statistical_history_facet is a view over additive delta tables since
-- STATBUS-558; its recovery from drift is the full rebuild, pinned in
-- test 319.
--
-- Since STATBUS-626 a partial cycle recounts only the facet keys its units
-- left or entered (test 360). A row no unit supports lies outside those keys,
-- so the recount of every facet (worker.statistical_unit_facet_state.recount_all,
-- set by a full recalculation) is what clears it; step 3 requests that recount.

BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"
CALL test.set_user_from_email('test.admin@statbus.org');
-- Suppress the verbatim echo of the shared include. Its content is not what
-- this test asserts, and echoing it would couple the expected file to a file
-- that churns (any edit to it would break this test's expected output). Only
-- this test's own queries below contribute to the expected output.
-- (STATBUS-175: the standard pattern for tests that \i shared files.)
\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

-- Load a small dataset via the standard import path
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_318_lu',
    'Test 318 legal unit load',
    'small dataset for facet drift self-healing test',
    'test 318',
    false;
\copy public.import_318_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "=== STEP 1: Post-derive baseline — target equals truth ==="
\x off
WITH truth AS (
    SELECT COUNT(DISTINCT unit_id)::int AS n
    FROM public.statistical_unit
    WHERE valid_from <= CURRENT_DATE AND valid_until > CURRENT_DATE
      AND unit_type = 'enterprise' AND used_for_counting
), facet AS (
    SELECT COALESCE(SUM(count), 0)::int AS n
    FROM public.statistical_unit_facet
    WHERE valid_from <= CURRENT_DATE AND valid_until > CURRENT_DATE
      AND unit_type = 'enterprise'
)
SELECT truth.n AS enterprise_truth,
       facet.n AS enterprise_facet_sum,
       truth.n = facet.n AS matches
FROM truth, facet;

\echo
\echo "=== STEP 2: Inject synthetic stale rows ==="
\echo "These dim+temporal tuples have NO support in statistical_unit;"
\echo "the buggy Path B would not include them in pre_dirty_dims and"
\echo "thus would never DELETE them. The new collapsed reduce uses"
\echo "WHEN NOT MATCHED BY SOURCE THEN DELETE which IS reach them."

INSERT INTO public.statistical_unit_facet
    (valid_from, valid_to, valid_until, unit_type,
     physical_region_path, primary_activity_category_path,
     sector_path, legal_form_id, physical_country_id, status_id,
     count, stats_summary)
VALUES
    -- Synthetic stale row: future valid_from, no real units overlap.
    ('2099-01-01'::date, 'infinity'::date, 'infinity'::date, 'enterprise',
     NULL::ltree, NULL::ltree, NULL::ltree, NULL::int, NULL::int, NULL::int,
     99, '{}'::jsonb);

\echo "Post-inject: synthetic row present in the target table"
SELECT 'unit_facet' AS tbl,
       COUNT(*) AS synthetic_rows
FROM public.statistical_unit_facet
WHERE valid_from = '2099-01-01'::date AND count = 99;

\echo
\echo "=== STEP 3: Run the reduce directly, recounting every facet ==="
\echo "(a full recalculation sets recount_all; a partial cycle recounts only its keys,"
\echo " and a row no unit ever supported is outside every key a cycle touches)"
SET LOCAL ROLE postgres;
UPDATE worker.statistical_unit_facet_state SET recount_all = true WHERE NOT recount_all;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
CALL worker.statistical_unit_facet_reduce('{}'::jsonb);

\echo
\echo "=== STEP 4: Assert synthetic rows are GONE (self-healing) ==="
SELECT 'unit_facet' AS tbl,
       COUNT(*) AS synthetic_rows_after_reduce,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM public.statistical_unit_facet
WHERE valid_from = '2099-01-01'::date AND count = 99;

\echo
\echo "=== STEP 5: Assert facet_sum still equals truth post-reduce ==="
WITH truth AS (
    SELECT COUNT(DISTINCT unit_id)::int AS n
    FROM public.statistical_unit
    WHERE valid_from <= CURRENT_DATE AND valid_until > CURRENT_DATE
      AND unit_type = 'enterprise' AND used_for_counting
), facet AS (
    SELECT COALESCE(SUM(count), 0)::int AS n
    FROM public.statistical_unit_facet
    WHERE valid_from <= CURRENT_DATE AND valid_until > CURRENT_DATE
      AND unit_type = 'enterprise'
)
SELECT truth.n AS enterprise_truth,
       facet.n AS enterprise_facet_sum,
       truth.n = facet.n AS matches
FROM truth, facet;
\x auto

ROLLBACK;
