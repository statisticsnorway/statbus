-- Test 322: statistical_history_facet recovery from empty delta tables.
--
-- statistical_history_facet is a view over public.statistical_history_facet_stock_delta and
-- public.statistical_history_facet_flow_delta (STATBUS-558). When those tables are empty while
-- statistical_unit has rows (a lost or truncated derived state), the next
-- ordinary cycle of worker.derive_statistical_history_facet_delta rebuilds them from
-- statistical_unit instead of adding a few staged deltas onto nothing.
--
-- This test:
--   1. Loads a small demo dataset and runs the pipeline; snapshots the view.
--   2. TRUNCATEs both delta tables.
--   3. Triggers an ordinary incremental cycle by renaming one unit.
--   4. Asserts the cycle rebuilt, and the view equals the snapshot except
--      for the rename's own change counts.

BEGIN;

\i test/setup.sql

\echo "Setting up Statbus using the demo examples"
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

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, review)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_322_lu',
    'Test 322 legal unit load',
    'small dataset for statistical_history_facet recovery test',
    'test 322',
    false;
\copy public.import_322_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo "=== STEP 1: Snapshot statistical_history_facet after the pipeline ==="
\x off

CREATE TEMP TABLE _pipeline_snapshot ON COMMIT DROP AS
SELECT
    resolution, year, month, unit_type,
    primary_activity_category_path, secondary_activity_category_path,
    sector_path, legal_form_id, physical_region_path,
    physical_country_id, unit_size_id, status_id,
    exists_count, exists_change, exists_added_count, exists_removed_count,
    countable_count, countable_change, countable_added_count, countable_removed_count,
    births, deaths,
    name_change_count, primary_activity_category_change_count,
    secondary_activity_category_change_count, sector_change_count,
    legal_form_change_count, physical_region_change_count, physical_country_change_count,
    physical_address_change_count, unit_size_change_count, status_change_count,
    stats_summary
FROM public.statistical_history_facet;

SELECT 'pipeline_snapshot_rows' AS step, COUNT(*) AS row_count
FROM _pipeline_snapshot;

\echo
\echo
\echo "=== STEP 2: TRUNCATE the delta tables ==="
SET ROLE postgres;
TRUNCATE public.statistical_history_facet_stock_delta, public.statistical_history_facet_flow_delta;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
SELECT count(*) AS facet_rows_while_empty FROM public.statistical_history_facet;

\echo
\echo "=== STEP 3: an ordinary cycle: one unit renamed from 2025-01-01 ==="
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_322_rename', 'Test 322 rename', 'test 322', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_322_rename_upload(tax_ident, name, valid_from, valid_to)
VALUES ('2220794', 'The Office Corp renamed', '2025-01-01', 'infinity');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
SELECT t.info->>'rebuild' AS last_history_cycle_rebuilt
FROM worker.tasks AS t WHERE t.command = 'derive_statistical_history_facet_delta' ORDER BY t.id DESC LIMIT 1;

\echo
\echo "=== STEP 4: the view equals the snapshot in every column but name_change_count ==="
WITH now_rows AS (
    SELECT resolution, year, month, unit_type,
           primary_activity_category_path, secondary_activity_category_path,
           sector_path, legal_form_id, physical_region_path,
           physical_country_id, unit_size_id, status_id,
           exists_count, exists_change, exists_added_count, exists_removed_count,
           countable_count, countable_change, countable_added_count, countable_removed_count,
           births, deaths,
           primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count,
           legal_form_change_count, physical_region_change_count, physical_country_change_count,
           physical_address_change_count, unit_size_change_count, status_change_count,
           stats_summary
    FROM public.statistical_history_facet
), snap_rows AS (
    SELECT resolution, year, month, unit_type,
           primary_activity_category_path, secondary_activity_category_path,
           sector_path, legal_form_id, physical_region_path,
           physical_country_id, unit_size_id, status_id,
           exists_count, exists_change, exists_added_count, exists_removed_count,
           countable_count, countable_change, countable_added_count, countable_removed_count,
           births, deaths,
           primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count,
           legal_form_change_count, physical_region_change_count, physical_country_change_count,
           physical_address_change_count, unit_size_change_count, status_change_count,
           stats_summary
    FROM _pipeline_snapshot
)
SELECT (SELECT count(*) FROM (SELECT * FROM snap_rows EXCEPT ALL SELECT * FROM now_rows) AS a) AS snapshot_minus_now,
       (SELECT count(*) FROM (SELECT * FROM now_rows EXCEPT ALL SELECT * FROM snap_rows) AS b) AS now_minus_snapshot;

\echo "The rename adds one name change to the 2025 year cell and the January 2025 month cell"
SELECT n.resolution, n.year, n.month, s.name_changes AS before, n.name_changes AS after
FROM (SELECT resolution, year, month, sum(name_change_count) AS name_changes
      FROM public.statistical_history_facet
      WHERE unit_type = 'legal_unit' AND name_change_count <> 0 GROUP BY 1, 2, 3) AS n
LEFT JOIN (SELECT resolution, year, month, sum(name_change_count) AS name_changes
           FROM _pipeline_snapshot
           WHERE unit_type = 'legal_unit' AND name_change_count <> 0 GROUP BY 1, 2, 3) AS s
  ON s.resolution = n.resolution AND s.year = n.year AND s.month IS NOT DISTINCT FROM n.month
ORDER BY 1, 2, 3;

ROLLBACK;
