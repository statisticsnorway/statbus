-- Test 319: statistical_history drift self-healing under reduce.
--
-- statistical_history stores BOTH per-slot rows (hash_partition =
-- int4range(slot, slot+1)) AND a NULL-summary rollup (hash_partition IS NULL)
-- in the same persistent table. worker.statistical_history_reduce produces the
-- NULL summary by:
--   1. DELETE FROM statistical_history WHERE hash_partition IS NULL;
--   2. INSERT … SELECT … SUM(...) FROM statistical_history WHERE hash_partition IS NOT NULL
--      GROUP BY (resolution, year, month, unit_type);
--
-- This contract IS the self-healing mechanism for the rollup: any stale
-- NULL-summary content (from a prior buggy run, manual data poke, or future
-- regression) is wiped and rebuilt on every reduce. This test pins that
-- contract.
--
-- Mirrors test/sql/318_facet_drift_self_healing.sql in spirit (synthetic
-- stale row, run reduce, assert gone). The shape differs because
-- statistical_history's rollup lives in the same table as its per-slot rows
-- rather than in a separate target table fed from staging.

BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the demo examples"
CALL test.set_user_from_email('test.admin@statbus.org');
\i samples/demo/getting-started.sql

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_319_lu',
    'Test 319 legal unit load',
    'small dataset for history drift self-healing test',
    'test 319',
    false;
\copy public.import_319_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

SET ROLE postgres;  -- statistical_history rows with hash_partition IS NOT NULL are RLS-hidden from admin_user

\echo "=== STEP 1: Post-derive baseline — NULL summary equals SUM(per-slot) and matches ground truth ==="
\x off

WITH years AS (
    SELECT DISTINCT year FROM public.statistical_history
    WHERE resolution = 'year' AND hash_partition IS NULL
), per_slot_sum AS (
    SELECT resolution, year, unit_type,
           SUM(exists_count)::int AS parts_exists,
           SUM(countable_count)::int AS parts_countable
    FROM public.statistical_history
    WHERE resolution = 'year' AND hash_partition IS NOT NULL
    GROUP BY resolution, year, unit_type
)
SELECT y.year, sh.unit_type,
       sh.exists_count AS null_summary_exists,
       p.parts_exists,
       sh.exists_count = p.parts_exists AS layer_a_matches
FROM years y
JOIN public.statistical_history sh
  ON sh.resolution = 'year' AND sh.year = y.year AND sh.hash_partition IS NULL
JOIN per_slot_sum p
  ON p.resolution = sh.resolution AND p.year = sh.year AND p.unit_type = sh.unit_type
ORDER BY y.year, sh.unit_type;

\echo
\echo "=== STEP 2: Inject synthetic stale values into NULL-summary rows ==="
\echo "Pretend a prior bug or manual poke left the rollup wildly wrong."
\echo "This mimics the kind of latent stale state Phase 2 + Phase 3"
\echo "ensure get fixed on the next reduce."

UPDATE public.statistical_history
   SET exists_count = 99999,
       countable_count = 99999,
       exists_change = -99999,
       countable_change = -99999,
       exists_added_count = 99999,
       exists_removed_count = 99999,
       countable_added_count = 99999,
       countable_removed_count = 99999
 WHERE resolution = 'year'
   AND hash_partition IS NULL;

\echo "Post-inject: NULL summary rows now show 99999 across the board"
SELECT resolution, year, unit_type, exists_count, countable_count
FROM public.statistical_history
WHERE resolution = 'year' AND hash_partition IS NULL
ORDER BY year, unit_type;

\echo
\echo "=== STEP 3: Run statistical_history_reduce directly ==="
\echo "(simulates a normal pipeline drain triggering reduce — DELETE NULL + re-INSERT)"
CALL worker.statistical_history_reduce('{}'::jsonb);

\echo
\echo "=== STEP 4: Assert NULL-summary rows are restored to SUM(per-slot) ==="
\echo "No row should still carry the synthetic 99999."

SELECT 'sh_year_null_summary_synthetic_remaining' AS check_name,
       COUNT(*) AS rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM public.statistical_history
WHERE resolution = 'year'
  AND hash_partition IS NULL
  AND (exists_count = 99999
       OR countable_count = 99999
       OR exists_change = -99999
       OR countable_change = -99999);

\echo
\echo "=== STEP 5: Assert NULL summary == SUM(per-slot) (Layer A invariant) ==="

WITH per_slot_sum AS (
    SELECT resolution, year, unit_type,
           SUM(exists_count)::int AS parts_exists,
           SUM(countable_count)::int AS parts_countable
    FROM public.statistical_history
    WHERE resolution = 'year' AND hash_partition IS NOT NULL
    GROUP BY resolution, year, unit_type
)
SELECT 'sh_layer_a_divergent_rows' AS check_name,
       COUNT(*) AS rows,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM public.statistical_history sh
LEFT JOIN per_slot_sum p
  ON p.resolution = sh.resolution AND p.year = sh.year AND p.unit_type = sh.unit_type
WHERE sh.resolution = 'year' AND sh.hash_partition IS NULL
  AND (sh.exists_count IS DISTINCT FROM COALESCE(p.parts_exists, 0)
    OR sh.countable_count IS DISTINCT FROM COALESCE(p.parts_countable, 0));

\x auto

ROLLBACK;
