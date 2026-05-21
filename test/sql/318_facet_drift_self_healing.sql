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
--   3. Injects a synthetic stale row into statistical_unit_facet (and
--      statistical_history_facet) — simulating drift that Path B would
--      have missed.
--   4. Calls worker.statistical_unit_facet_reduce and
--      worker.statistical_history_facet_reduce directly (no pipeline).
--   5. Asserts the synthetic rows are GONE — proving the new collapsed
--      MERGE is self-healing regardless of whether the dim+temporal of
--      the stale row was ever in pre_dirty_dims.
--
-- Under the BUGGY rc.42 Path B (≤128 dirty), the synthetic row would
-- survive: pre_dirty_dims wouldn't include the synthetic dim_tuple
-- (no staging row matches it), so the gating filter in the DELETE
-- step `WHERE dim_tuple IN pre_dirty_dims` excludes it. The fix uses
-- WHEN NOT MATCHED BY SOURCE THEN DELETE which is dim-tuple-agnostic.
--
-- This test ALSO captures #53 (history-reduce-dupkey). The two partial
-- unique indexes on statistical_history_facet (statistical_history_facet_month_key,
-- _year_key, created in 20240327000000) cover 10 / 9 dim columns, but the
-- source GROUP BY in worker.statistical_history_facet_reduce, the partitions
-- table UNIQUE constraint, and the statistical_history_facet_type itself
-- all dimension on 12 columns including unit_size_id + status_id. When source
-- produces two rows with the same 10-col tuple but distinct
-- (unit_size_id, status_id), MERGE's WHEN NOT MATCHED BY TARGET trips
-- "duplicate key value violates unique constraint statistical_history_facet_month_key".
--
-- Fix (schema-only, no proc change): migration extends both partial unique
-- indexes to 12 / 11 cols. STEPs 6-9 below exercise this repro.

BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the web provided examples"
CALL test.set_user_from_email('test.admin@statbus.org');
\i samples/demo/getting-started.sql

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

INSERT INTO public.statistical_history_facet
    (resolution, year, month, unit_type,
     primary_activity_category_path, secondary_activity_category_path,
     sector_path, legal_form_id, physical_region_path,
     physical_country_id, unit_size_id, status_id,
     exists_count, exists_change, exists_added_count, exists_removed_count,
     countable_count, countable_change, countable_added_count, countable_removed_count,
     births, deaths,
     name_change_count, primary_activity_category_change_count,
     secondary_activity_category_change_count, sector_change_count,
     legal_form_change_count, physical_region_change_count,
     physical_country_change_count, physical_address_change_count,
     unit_size_change_count, status_change_count,
     stats_summary)
VALUES
    -- Synthetic stale row: future year, no real units.
    ('year'::history_resolution, 2099, NULL, 'enterprise',
     NULL::ltree, NULL::ltree, NULL::ltree, NULL::int, NULL::ltree,
     NULL::int, NULL::int, NULL::int,
     99, 0, 0, 0,
     0, 0, 0, 0,
     0, 0,
     0, 0,
     0, 0,
     0, 0,
     0, 0,
     0, 0,
     '{}'::jsonb);

\echo "Post-inject: synthetic rows present in both target tables"
SELECT 'unit_facet' AS tbl,
       COUNT(*) AS synthetic_rows
FROM public.statistical_unit_facet
WHERE valid_from = '2099-01-01'::date AND count = 99
UNION ALL
SELECT 'history_facet',
       COUNT(*)
FROM public.statistical_history_facet
WHERE year = 2099 AND exists_count = 99;

\echo
\echo "=== STEP 3: Run the new collapsed reduces directly ==="
\echo "(simulates a normal pipeline drain triggering reduce)"
CALL worker.statistical_unit_facet_reduce('{}'::jsonb);
CALL worker.statistical_history_facet_reduce('{}'::jsonb);

\echo
\echo "=== STEP 4: Assert synthetic rows are GONE (self-healing) ==="
SELECT 'unit_facet' AS tbl,
       COUNT(*) AS synthetic_rows_after_reduce,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM public.statistical_unit_facet
WHERE valid_from = '2099-01-01'::date AND count = 99
UNION ALL
SELECT 'history_facet',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM public.statistical_history_facet
WHERE year = 2099 AND exists_count = 99;

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

\echo
\echo "=== STEP 6: #53 repro — colliding source partitions across unit_size_id ==="
\echo "Two source rows share dim_10 tuple, distinct unit_size_id."
\echo "Bug: worker.statistical_history_facet_reduce trips dup-key on month_key."
\echo "Fix (Landing B): extended indexes accept both rows."

-- statistical_history_facet_partitions is an UNLOGGED staging table not
-- granted to admin_user; elevate to postgres (superuser, RLS bypassed) for
-- the TRUNCATE + INSERT + inspect block, then drop back to test admin.
SET LOCAL ROLE postgres;

-- Isolate the dup-key scenario from STEPs 1-5's analytics state
TRUNCATE public.statistical_history_facet_partitions;
TRUNCATE public.statistical_history_facet;

INSERT INTO public.statistical_history_facet_partitions
    (hash_slot, resolution, year, month, unit_type,
     primary_activity_category_path, secondary_activity_category_path,
     sector_path, legal_form_id, physical_region_path,
     physical_country_id, unit_size_id, status_id,
     exists_count, exists_change, exists_added_count, exists_removed_count,
     countable_count, countable_change, countable_added_count, countable_removed_count,
     births, deaths,
     name_change_count, primary_activity_category_change_count,
     secondary_activity_category_change_count, sector_change_count,
     legal_form_change_count, physical_region_change_count,
     physical_country_change_count, physical_address_change_count,
     unit_size_change_count, status_change_count,
     stats_summary)
VALUES
    -- Two rows: identical dim_10, distinct unit_size_id (1 vs 2), same hash_slot.
    -- All dim_10 cols are NON-NULL — the 10-col partial unique on the target uses
    -- default NULLS DISTINCT semantics, so two rows with NULL in any dim col
    -- would NOT collide. Using simple sentinel ltree/int values (no FK on
    -- either table for these cols) keeps the inputs synthetic + deterministic
    -- while ensuring the partial unique sees an honest 10-col tuple collision.
    -- The 13-col partitions UNIQUE distinguishes them via unit_size_id; the
    -- 10-col target unique does not.
    (1, 'year-month'::history_resolution, 2025, 1, 'enterprise'::statistical_unit_type,
     'root'::ltree, 'root'::ltree, 'root'::ltree, 1::int, 'root'::ltree,
     1::int, 1::int /* size A */, 1::int,
     1, 0, 0, 0, 1, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     '{}'::jsonb),
    (1, 'year-month'::history_resolution, 2025, 1, 'enterprise'::statistical_unit_type,
     'root'::ltree, 'root'::ltree, 'root'::ltree, 1::int, 'root'::ltree,
     1::int, 2::int /* size B */, 1::int,
     1, 0, 0, 0, 1, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     '{}'::jsonb);

\echo "Partition source rows pre-reduce:"
SELECT unit_size_id, exists_count
  FROM public.statistical_history_facet_partitions
 ORDER BY unit_size_id;

RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

\echo
\echo "=== STEP 7: Call reduce — bug fires HERE with dup-key on month_key ==="
\echo "Pre-fix: ERROR aborts the test; expected captures up to and including the ERROR line."
\echo "Post-fix: CALL succeeds; STEPs 8-9 run; expected regenerated in Landing C."
CALL worker.statistical_history_facet_reduce('{}'::jsonb);

\echo
\echo "=== STEP 8: Target should contain BOTH rows post-fix (one per unit_size_id) ==="
SELECT COUNT(*) AS target_rows,
       CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL (bug active or fix incomplete)' END AS verdict
  FROM public.statistical_history_facet
 WHERE resolution = 'year-month' AND year = 2025 AND month = 1;

SELECT unit_size_id, exists_count
  FROM public.statistical_history_facet
 WHERE resolution = 'year-month' AND year = 2025 AND month = 1
 ORDER BY unit_size_id;

\echo
\echo "=== STEP 9: dirty_hash_slots empty (TRUNCATE at proc tail ran) ==="
-- statistical_unit_facet_dirty_hash_slots is also restricted to postgres.
SET LOCAL ROLE postgres;
SELECT COUNT(*) AS dirty_count,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL (proc tail did not run — error path?)' END AS verdict
  FROM public.statistical_unit_facet_dirty_hash_slots;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

ROLLBACK;
