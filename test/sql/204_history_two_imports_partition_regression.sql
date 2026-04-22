SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

\echo "Regression for ET history-count drift: two sequential imports of"
\echo "LU+Establishment where unit IDs hash to distinct hash_slot"
\echo "values must both appear in statistical_history after the second import."

CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/norway/getting-started.sql

\echo "--- Baseline: no units loaded ---"
SELECT
    (SELECT COUNT(DISTINCT id) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) FROM public.enterprise) AS enterprise_count;

-- ===================================================================
-- IMPORT 1: LU A + Establishment A (tax_idents 100000001 / 300000001)
-- ===================================================================
\echo "--- Import 1a: LU A ---"
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_204_lu_a',
    'Import LU A for partition regression',
    'Import job for test/data/204_regression_lu_a.csv.',
    'Test data load (204_history_two_imports_partition_regression.sql)';

\copy public.import_204_lu_a_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/204_regression_lu_a.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
CALL worker.process_tasks(p_queue => 'import');

\echo "--- Import 1b: Establishment A ---"
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_204_est_a',
    'Import Establishment A for partition regression',
    'Import job for test/data/204_regression_est_a.csv.',
    'Test data load (204_history_two_imports_partition_regression.sql)';

\copy public.import_204_est_a_upload(valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, postal_address_part1, postal_postcode, postal_postplace, postal_region_code, postal_country_iso_2, primary_activity_category_code, secondary_activity_category_code, data_source_code, unit_size_code, employees, turnover) FROM 'test/data/204_regression_est_a.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "--- Base table counts after import 1 ---"
SELECT
    (SELECT COUNT(DISTINCT id) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) FROM public.enterprise) AS enterprise_count;

\echo "--- Unit IDs + hash slots after import 1 ---"
SELECT
    'legal_unit'::text AS unit_type, lu.id AS unit_id,
    public.hash_slot('legal_unit'::text, lu.id) AS hash_slot
FROM public.legal_unit AS lu
UNION ALL
SELECT 'establishment', es.id, public.hash_slot('establishment'::text, es.id)
FROM public.establishment AS es
UNION ALL
SELECT 'enterprise', e.id, public.hash_slot('enterprise'::text, e.id)
FROM public.enterprise AS e
ORDER BY unit_type, unit_id;

\echo "--- statistical_history year=2021 after import 1 (expect exists_count=1 per unit_type) ---"
SELECT unit_type, exists_count, countable_count
FROM public.statistical_history
WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NULL
  AND unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY unit_type;

\echo "--- Per-partition rows after import 1 (year=2021) [as postgres, bypass RLS] ---"
SET LOCAL ROLE postgres;
SELECT unit_type, hash_partition, exists_count
FROM public.statistical_history
WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NOT NULL
  AND unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY unit_type, lower(hash_partition);

\echo "--- ALL statistical_history rows after import 1 (any year/resolution) [as postgres] ---"
SELECT resolution, year, unit_type, hash_partition, exists_count
FROM public.statistical_history
WHERE unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY resolution, year, unit_type, lower(hash_partition) NULLS FIRST;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "--- statistical_unit coverage after import 1 (year range) ---"
SELECT unit_type, MIN(valid_from) AS min_from, MAX(valid_until) AS max_until, COUNT(*) AS row_count
FROM public.statistical_unit
WHERE unit_type IN ('legal_unit', 'establishment', 'enterprise')
GROUP BY unit_type
ORDER BY unit_type;

-- ===================================================================
-- IMPORT 2: LU B + Establishment B (tax_idents 100000002 / 300000002)
-- ===================================================================
\echo "--- Import 2a: LU B ---"
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_204_lu_b',
    'Import LU B for partition regression',
    'Import job for test/data/204_regression_lu_b.csv.',
    'Test data load (204_history_two_imports_partition_regression.sql)';

\copy public.import_204_lu_b_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code) FROM 'test/data/204_regression_lu_b.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
CALL worker.process_tasks(p_queue => 'import');

\echo "--- Import 2b: Establishment B ---"
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_204_est_b',
    'Import Establishment B for partition regression',
    'Import job for test/data/204_regression_est_b.csv.',
    'Test data load (204_history_two_imports_partition_regression.sql)';

\copy public.import_204_est_b_upload(valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, birth_date, death_date, physical_address_part1, physical_postcode, physical_postplace, physical_region_code, physical_country_iso_2, postal_address_part1, postal_postcode, postal_postplace, postal_region_code, postal_country_iso_2, primary_activity_category_code, secondary_activity_category_code, data_source_code, unit_size_code, employees, turnover) FROM 'test/data/204_regression_est_b.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "--- Base table counts after import 2 ---"
SELECT
    (SELECT COUNT(DISTINCT id) FROM public.legal_unit) AS legal_unit_count,
    (SELECT COUNT(DISTINCT id) FROM public.establishment) AS establishment_count,
    (SELECT COUNT(DISTINCT id) FROM public.enterprise) AS enterprise_count;

\echo "--- Unit IDs + hash slots after import 2 ---"
SELECT
    'legal_unit'::text AS unit_type, lu.id AS unit_id,
    public.hash_slot('legal_unit'::text, lu.id) AS hash_slot
FROM public.legal_unit AS lu
UNION ALL
SELECT 'establishment', es.id, public.hash_slot('establishment'::text, es.id)
FROM public.establishment AS es
UNION ALL
SELECT 'enterprise', e.id, public.hash_slot('enterprise'::text, e.id)
FROM public.enterprise AS e
ORDER BY unit_type, unit_id;

\echo "--- statistical_history year=2021 after import 2 (expect exists_count=2 per unit_type; master bug: 1) ---"
SELECT unit_type, exists_count, countable_count
FROM public.statistical_history
WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NULL
  AND unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY unit_type;

\echo "--- Per-partition rows after import 2 (year=2021) [as postgres, bypass RLS] ---"
SET LOCAL ROLE postgres;
SELECT unit_type, hash_partition, exists_count
FROM public.statistical_history
WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NOT NULL
  AND unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY unit_type, lower(hash_partition);

\echo "--- ALL statistical_history rows after import 2 (any year/resolution) [as postgres] ---"
SELECT resolution, year, unit_type, hash_partition, exists_count
FROM public.statistical_history
WHERE unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY resolution, year, unit_type, lower(hash_partition) NULLS FIRST;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "--- statistical_unit coverage after import 2 (year range) ---"
SELECT unit_type, MIN(valid_from) AS min_from, MAX(valid_until) AS max_until, COUNT(*) AS row_count
FROM public.statistical_unit
WHERE unit_type IN ('legal_unit', 'establishment', 'enterprise')
GROUP BY unit_type
ORDER BY unit_type;

\echo "--- statistical_unit temporal fields per unit_type after import 2 ---"
SELECT unit_type, unit_id, valid_from, valid_to, valid_until, birth_date, death_date,
       used_for_counting, hash_slot
FROM public.statistical_unit
WHERE unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY unit_type, unit_id, valid_from;

\echo "--- RAW statistical_history_def(year, 2021, NULL) output — root-entry (hash_partition IS NULL) ---"
SELECT unit_type, hash_partition, exists_count, countable_count
FROM public.statistical_history_def('year'::public.history_resolution, 2021, NULL)
WHERE unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY unit_type;

\echo "--- RAW statistical_history_def(year, 2021, '[0,16384)'::int4range) output — full hash range ---"
SELECT unit_type, hash_partition, exists_count, countable_count
FROM public.statistical_history_def('year'::public.history_resolution, 2021, NULL, '[0,16384)'::int4range)
WHERE unit_type IN ('legal_unit', 'establishment', 'enterprise')
ORDER BY unit_type;

\echo "--- Worker task summary across the full run [as postgres, bypass RLS] ---"
SET LOCAL ROLE postgres;
\set ON_ERROR_STOP off
SAVEPOINT diag;
SELECT command, state, COUNT(*) AS task_count
FROM worker.tasks
WHERE command IN ('collect_changes', 'command_collect_changes',
                  'derive_units_phase', 'derive_reports_phase',
                  'derive_statistical_unit', 'statistical_unit_flush_staging',
                  'derive_statistical_history', 'derive_statistical_history_period',
                  'statistical_history_reduce')
GROUP BY command, state
ORDER BY command, state;
ROLLBACK TO SAVEPOINT diag;

\echo "--- derive_statistical_history tasks (the spawner; info.child_count reports fan-out) [as postgres] ---"
SAVEPOINT diag;
SELECT id, state, info, payload->>'valid_from' AS valid_from, payload->>'valid_until' AS valid_until
FROM worker.tasks
WHERE command = 'derive_statistical_history'
ORDER BY id;
ROLLBACK TO SAVEPOINT diag;

\echo "--- derive_statistical_history_period task distribution by hash_partition [as postgres] ---"
SAVEPOINT diag;
SELECT payload->>'resolution' AS resolution,
       NULLIF(payload->>'hash_partition', '')::int4range AS hash_partition,
       state,
       COUNT(*) AS task_count,
       SUM((info->>'rows_inserted')::bigint) AS total_rows_inserted
FROM worker.tasks
WHERE command = 'derive_statistical_history_period'
GROUP BY 1,2,3
ORDER BY resolution, lower(hash_partition) NULLS FIRST;
ROLLBACK TO SAVEPOINT diag;

\echo "--- year=2021 hash_partition spawns specifically [as postgres] ---"
SAVEPOINT diag;
SELECT id, state,
       NULLIF(payload->>'hash_partition', '')::int4range AS hash_partition,
       info->>'rows_inserted' AS inserted
FROM worker.tasks
WHERE command = 'derive_statistical_history_period'
  AND payload->>'resolution' = 'year'
  AND (payload->>'year')::int = 2021
ORDER BY lower(NULLIF(payload->>'hash_partition', '')::int4range) NULLS FIRST;
ROLLBACK TO SAVEPOINT diag;

\echo "--- Any failed/error tasks in the analytics pipeline [as postgres] ---"
SAVEPOINT diag;
SELECT id, command, state, LEFT(COALESCE(error, ''), 200) AS error_short, payload
FROM worker.tasks
WHERE state IN ('failed', 'error')
  AND (command LIKE 'derive_%' OR command LIKE 'statistical_%')
ORDER BY id
LIMIT 20;
ROLLBACK TO SAVEPOINT diag;

\echo "--- statistical_unit snapshot at read time used by derive_statistical_history (proxy: full table as postgres) ---"
SAVEPOINT diag;
SELECT unit_type, COUNT(*) AS row_count,
       array_agg(DISTINCT hash_slot ORDER BY hash_slot) AS distinct_slots
FROM public.statistical_unit
GROUP BY unit_type
ORDER BY unit_type;
ROLLBACK TO SAVEPOINT diag;

\set ON_ERROR_STOP on

\echo "--- Consistency: root (hash_partition IS NULL) aggregate must equal SUM of per-partition rows [as postgres, bypass RLS] ---"
SELECT
    a.unit_type,
    a.aggregate_exists_count,
    COALESCE(p.partitions_sum, 0) AS per_partition_sum,
    a.aggregate_exists_count = COALESCE(p.partitions_sum, 0) AS consistent
FROM (
    SELECT unit_type, exists_count AS aggregate_exists_count
    FROM public.statistical_history
    WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NULL
      AND unit_type IN ('legal_unit', 'establishment', 'enterprise')
) AS a
LEFT JOIN (
    SELECT unit_type, SUM(exists_count)::integer AS partitions_sum
    FROM public.statistical_history
    WHERE resolution = 'year' AND year = 2021 AND hash_partition IS NOT NULL
      AND unit_type IN ('legal_unit', 'establishment', 'enterprise')
    GROUP BY unit_type
) AS p USING (unit_type)
ORDER BY a.unit_type;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

ROLLBACK;
