SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Regression #102/#105: orphan hash_partition rows must be cleaned up during full rebuild."
\echo "derive_statistical_history full-refresh only spawns children for currently-populated"
\echo "partitions. Orphan rows from prior runs survive and inflate the NULL summary via reduce."

CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

-- === FIXTURE: Two LUs in distinct hash partitions (reuse 204 data files) ===
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_205_lu_a',
    'LU A for orphan-partition regression',
    'test/data/204_regression_lu_a.csv',
    '205_history_orphan_partition_regression.sql';

\copy public.import_205_lu_a_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/204_regression_lu_a.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
CALL worker.process_tasks(p_queue => 'import');

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_205_lu_b',
    'LU B for orphan-partition regression',
    'test/data/204_regression_lu_b.csv',
    '205_history_orphan_partition_regression.sql';

\copy public.import_205_lu_b_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/204_regression_lu_b.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- === Baseline: verify clean state before orphan injection ===
\echo "--- Baseline: NULL summary must equal partition sums (clean state) ---"
SET LOCAL ROLE postgres;
SELECT
    a.unit_type,
    a.aggregate_exists_count,
    COALESCE(p.partitions_sum, 0) AS per_partition_sum,
    a.aggregate_exists_count = COALESCE(p.partitions_sum, 0) AS consistent
FROM (
    SELECT unit_type, exists_count AS aggregate_exists_count
    FROM public.statistical_history
    WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NULL
      AND unit_type IN ('enterprise', 'legal_unit')
) AS a
LEFT JOIN (
    SELECT unit_type, SUM(exists_count)::integer AS partitions_sum
    FROM public.statistical_history
    WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NOT NULL
      AND unit_type IN ('enterprise', 'legal_unit')
    GROUP BY unit_type
) AS p USING (unit_type)
ORDER BY a.unit_type;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

-- === Inject orphan: simulate stale partition rows from a prior upgrade ===
-- hash_partition [999999,1000000) is outside the normal [0,16384) range.
-- A full rebuild only spawns children for partitions occupied by current
-- statistical_unit rows. This orphan is never visited, so on HEAD it
-- survives the rebuild and statistical_history_reduce sums it into the
-- NULL summary row.
SET LOCAL ROLE postgres;
INSERT INTO public.statistical_history
  (resolution, year, month, unit_type,
   exists_count, exists_change, exists_added_count, exists_removed_count,
   countable_count, countable_change, countable_added_count, countable_removed_count,
   births, deaths, name_change_count, primary_activity_category_change_count,
   secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
   physical_region_change_count, physical_country_change_count, physical_address_change_count,
   stats_summary, hash_partition)
VALUES
  ('year', 2021, NULL, 'enterprise',
   7, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
   '{}'::jsonb, '[999999,1000000)'::int4range),
  ('year', 2021, NULL, 'legal_unit',
   7, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
   '{}'::jsonb, '[999999,1000000)'::int4range);
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

-- === Full rebuild: all-NULL payload triggers full refresh path ===
DO $spawn_collect_changes$
BEGIN
  PERFORM worker.spawn(
      p_command => 'collect_changes',
      p_payload => jsonb_build_object(
          'establishment_id_ranges', NULL,
          'legal_unit_id_ranges',    NULL,
          'enterprise_id_ranges',    NULL,
          'power_group_id_ranges',   NULL,
          'valid_ranges',            NULL
      )
  );
END;
$spawn_collect_changes$;
CALL worker.process_tasks(p_queue => 'analytics');

-- === Assert A: orphan partition row must be gone after fix ===
-- Expected AFTER FIX: 0 rows.
-- Expected ON HEAD:   2 rows (enterprise=7, legal_unit=7) -- orphan survived.
\echo "--- Assert A: orphan hash_partition=[999999,1000000) absent after rebuild (0 rows = pass) ---"
SET LOCAL ROLE postgres;
SELECT hash_partition, unit_type, exists_count
FROM public.statistical_history
WHERE hash_partition = '[999999,1000000)'::int4range
ORDER BY unit_type;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

-- === Assert B: NULL summary equals sum of partition rows ===
-- Expected AFTER FIX: consistent=t, aggregate_exists_count=2, per_partition_sum=2.
-- Expected ON HEAD:   consistent=t but both are 9 (inflated by orphan).
\echo "--- Assert B: NULL summary equals sum of partition rows ---"
SET LOCAL ROLE postgres;
SELECT
    a.unit_type,
    a.aggregate_exists_count,
    COALESCE(p.partitions_sum, 0) AS per_partition_sum,
    a.aggregate_exists_count = COALESCE(p.partitions_sum, 0) AS consistent
FROM (
    SELECT unit_type, exists_count AS aggregate_exists_count
    FROM public.statistical_history
    WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NULL
      AND unit_type IN ('enterprise', 'legal_unit')
) AS a
LEFT JOIN (
    SELECT unit_type, SUM(exists_count)::integer AS partitions_sum
    FROM public.statistical_history
    WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NOT NULL
      AND unit_type IN ('enterprise', 'legal_unit')
    GROUP BY unit_type
) AS p USING (unit_type)
ORDER BY a.unit_type;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

-- === Assert C: NULL summary matches direct unit count (truth) ===
-- Expected AFTER FIX: matches_truth=t, null_row_count=truth=2.
-- Expected ON HEAD:   matches_truth=f, null_row_count=9 vs truth=2.
\echo "--- Assert C: NULL summary exists_count matches statistical_unit truth ---"
SELECT
    sh.unit_type,
    sh.exists_count                                     AS null_row_count,
    (SELECT COUNT(*)::integer
       FROM public.statistical_unit AS su
      WHERE su.unit_type = sh.unit_type
        AND su.valid_from <= '2021-01-01'::date
        AND '2021-01-01'::date < su.valid_until)        AS truth,
    sh.exists_count = (SELECT COUNT(*)::integer
       FROM public.statistical_unit AS su
      WHERE su.unit_type = sh.unit_type
        AND su.valid_from <= '2021-01-01'::date
        AND '2021-01-01'::date < su.valid_until)        AS matches_truth
FROM public.statistical_history AS sh
WHERE sh.resolution = 'year' AND sh.year = 2021 AND sh.hash_partition IS NULL
  AND sh.unit_type IN ('enterprise', 'legal_unit')
ORDER BY sh.unit_type;

ROLLBACK;
