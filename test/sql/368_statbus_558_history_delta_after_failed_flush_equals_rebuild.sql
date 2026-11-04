-- STATBUS-558: a cycle that stops after staging history deltas but before the flush leaves the
-- history delta tables, after the next cycle, equal to a full rebuild.
--
-- worker.derive_statistical_history_facet_delta_partition children stage, per refreshed unit,
-- its new versions (statistical_unit_staging) minus its old ones (statistical_unit), and commit.
-- If the flush then fails, statistical_unit still holds the old versions and the next cycle
-- stages the same units again. The staged rows of the cycle that never flushed must not be
-- added on top of the ones the next cycle stages.
--
-- Fixture: the demo legal units and establishments, imported and derived. Cycle A moves a legal
-- unit to another region, and its flush fails. Cycle B adds a new legal unit and completes.
-- The stored rows must then equal a full rebuild, unit_ids included.

BEGIN;

\i test/setup.sql

\echo "Test 368 (STATBUS-558): history deltas after a cycle whose flush failed equal a full rebuild"

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_368_lu', 'Test 368 legal units', 'Test 368 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_368_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- Stored rows of both tables, stats compared by their net (in minus out) per variable and field.
CREATE FUNCTION pg_temp.stats_net(d jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $stats_net$
    SELECT string_agg(x.key || '.' || x.field || '=' || x.net, ',' ORDER BY x.key, x.field)
    FROM (SELECT e.key, f.field,
                 COALESCE((e.value->'in'->>f.field)::numeric, 0) - COALESCE((e.value->'out'->>f.field)::numeric, 0) AS net
          FROM jsonb_each(COALESCE(d, '{}') - 'type'::text) AS e
          CROSS JOIN LATERAL (SELECT jsonb_object_keys(COALESCE(e.value->'in', '{}') || COALESCE(e.value->'out', '{}')) AS field) AS f
          WHERE jsonb_typeof(COALESCE(e.value->'in'->f.field, e.value->'out'->f.field)) = 'number') AS x
    WHERE x.net <> 0
$stats_net$;
CREATE TEMP VIEW stored_rows AS
SELECT 'stock' AS kind,
       concat_ws('|', d.unit_type, d.primary_activity_category_path, d.secondary_activity_category_path, d.sector_path,
                 d.legal_form_id, d.physical_region_path, d.physical_country_id, d.unit_size_id, d.status_id,
                 d.on_month, d.exists_delta, d.countable_delta, pg_temp.stats_net(d.stats_delta), d.unit_ids) AS row_text
FROM public.statistical_history_facet_stock_delta AS d
UNION ALL
SELECT 'flow',
       concat_ws('|', f.resolution, f.year, f.month, f.unit_type, f.primary_activity_category_path,
                 f.secondary_activity_category_path, f.sector_path, f.legal_form_id, f.physical_region_path,
                 f.physical_country_id, f.unit_size_id, f.status_id, f.flows, pg_temp.stats_net(f.stats_ended), f.unit_ids)
FROM public.statistical_history_facet_flow_delta AS f;
CREATE TEMP TABLE snapshot (label text, kind text, row_text text) ON COMMIT DROP;

\echo
\echo "368.1 cycle A: a legal unit moves region from 2024-01-01, and its flush fails"
-- The flush handler is replaced by one that raises, as a lost connection or an out-of-memory
-- error would end the step. The history children of the cycle have already staged their rows.
CREATE PROCEDURE pg_temp.flush_that_fails(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql AS $flush_that_fails$
BEGIN
    RAISE EXCEPTION 'test 368: the flush stops before it commits';
END;
$flush_that_fails$;
CREATE PROCEDURE pg_temp.process_analytics_quietly()
LANGUAGE plpgsql AS $process_analytics_quietly$
BEGIN
    LOOP
        PERFORM set_config('client_min_messages', 'error', true);
        CALL worker.process_tasks(p_queue => 'analytics', p_batch_size => 1);
        EXIT WHEN NOT EXISTS (SELECT 1 FROM worker.tasks AS t JOIN worker.command_registry AS c ON c.command = t.command
                               WHERE c.queue = 'analytics' AND t.state IN ('pending', 'interrupted'));
    END LOOP;
    PERFORM set_config('client_min_messages', 'notice', true);
END;
$process_analytics_quietly$;
SET LOCAL ROLE postgres;
UPDATE worker.command_registry SET handler_procedure = 'pg_temp.flush_that_fails'
 WHERE command = 'statistical_unit_flush_staging';
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_368_move', 'Test 368 region move', 'Test 368 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_368_move_upload(tax_ident, name, valid_from, valid_to, physical_region_code)
VALUES ('2220794', 'The Office Corp', '2024-01-01', 'infinity', '225602');
CALL worker.process_tasks(p_queue => 'import');
-- worker.process_tasks reports the failed flush as a WARNING carrying its run time; the task states
-- below are what the test asserts. The tasks run one at a time with warnings off for each (the timeline
-- refreshes set client_min_messages back to notice for the transaction).
CALL pg_temp.process_analytics_quietly();

-- The cycle's steps after the failed flush: the reports phase must not add the staged history rows,
-- because statistical_unit still holds the old versions they were computed against.
SELECT t.command, t.state
FROM worker.tasks AS t
WHERE t.id > (SELECT max(id) FROM worker.tasks WHERE command = 'collect_changes' AND state <> 'pending') - 1
  AND t.command IN ('collect_changes', 'derive_units_phase', 'derive_statistical_history_facet_delta',
                    'statistical_unit_flush_staging', 'derive_reports_phase', 'statistical_history_facet_delta_reduce')
ORDER BY t.id;
SET LOCAL ROLE postgres;
SELECT (SELECT count(*) FROM public.statistical_unit_staging) > 0 AS unit_staging_still_holds_the_move,
       (SELECT count(*) FROM public.statistical_history_facet_stock_delta_staging) > 0 AS history_rows_staged;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

\echo
\echo "368.2 cycle B: the flush works again, and a new legal unit from 2022-03-15 is imported"
SET LOCAL ROLE postgres;
UPDATE worker.command_registry SET handler_procedure = 'worker.statistical_unit_flush_staging'
 WHERE command = 'statistical_unit_flush_staging';
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_368_new', 'Test 368 new unit', 'Test 368 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_368_new_upload(tax_ident, name, valid_from, valid_to, physical_region_code, employees)
VALUES ('368000001', 'Test 368 new unit', '2022-03-15', 'infinity', '104601', '7');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
SET LOCAL ROLE postgres;
SELECT (SELECT count(*) FROM public.statistical_unit_staging) AS unit_staging_rows,
       (SELECT count(*) FROM public.statistical_history_facet_stock_delta_staging)
     + (SELECT count(*) FROM public.statistical_history_facet_flow_delta_staging) AS history_staging_rows;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');

\echo
\echo "368.3 the moved unit counts once: it leaves its old region and enters the new one in 2024-01"
SELECT d.physical_region_path, d.on_month, d.exists_delta, d.countable_delta
FROM public.statistical_history_facet_stock_delta AS d
WHERE d.unit_type = 'legal_unit'
  AND (SELECT su.unit_id FROM public.statistical_unit AS su
        WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '2220794' LIMIT 1) = ANY (d.unit_ids)
ORDER BY d.on_month, d.physical_region_path;
SELECT h.year, h.exists_count
FROM public.statistical_history AS h
WHERE h.resolution = 'year' AND h.unit_type = 'legal_unit' AND h.year BETWEEN 2023 AND 2025
ORDER BY h.year;

\echo
\echo "368.4 a full rebuild reproduces the stored rows exactly, unit_ids included"
INSERT INTO snapshot SELECT 'incremental', kind, row_text FROM stored_rows;
SELECT worker.enqueue_derive_statistical_unit_all() IS NOT NULL AS rebuild_scheduled;
CALL worker.process_tasks(p_queue => 'analytics');
INSERT INTO snapshot SELECT 'rebuilt', kind, row_text FROM stored_rows;
SELECT
    (SELECT count(*) FROM (SELECT kind, row_text FROM snapshot WHERE label = 'rebuilt'
                           EXCEPT ALL SELECT kind, row_text FROM snapshot WHERE label = 'incremental') AS x) AS only_in_rebuild,
    (SELECT count(*) FROM (SELECT kind, row_text FROM snapshot WHERE label = 'incremental'
                           EXCEPT ALL SELECT kind, row_text FROM snapshot WHERE label = 'rebuilt') AS x) AS only_in_incremental;

\echo
\echo "368.5 a rebuild cycle whose flush fails: the next cycle rebuilds again, and readers keep the last good rows meanwhile"
SELECT count(*) AS stock_rows_before FROM public.statistical_history_facet_stock_delta \gset
SET LOCAL ROLE postgres;
UPDATE worker.command_registry SET handler_procedure = 'pg_temp.flush_that_fails'
 WHERE command = 'statistical_unit_flush_staging';
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_368_move2', 'Test 368 second move', 'Test 368 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_368_move2_upload(tax_ident, name, valid_from, valid_to, physical_region_code)
VALUES ('2220794', 'The Office Corp', '2025-01-01', 'infinity', '104601');
CALL worker.process_tasks(p_queue => 'import');
SELECT worker.enqueue_derive_statistical_unit_all() IS NOT NULL AS rebuild_scheduled;
CALL pg_temp.process_analytics_quietly();
SELECT (SELECT t.info->>'rebuild' FROM worker.tasks AS t WHERE t.command = 'derive_statistical_history_facet_delta'
         ORDER BY t.id DESC LIMIT 1) AS failed_cycle_was_a_rebuild,
       (SELECT count(*) FROM public.statistical_history_facet_stock_delta) = :stock_rows_before AS readers_keep_the_last_good_rows;

SET LOCAL ROLE postgres;
UPDATE worker.command_registry SET handler_procedure = 'worker.statistical_unit_flush_staging'
 WHERE command = 'statistical_unit_flush_staging';
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_368_new2', 'Test 368 second new unit', 'Test 368 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_368_new2_upload(tax_ident, name, valid_from, valid_to, physical_region_code, employees)
VALUES ('368000002', 'Test 368 second new unit', '2023-05-01', 'infinity', '104601', '3');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
SELECT (SELECT t.info->>'rebuild' FROM worker.tasks AS t WHERE t.command = 'derive_statistical_history_facet_delta'
         ORDER BY t.id DESC LIMIT 1) AS next_cycle_rebuilt;
DELETE FROM snapshot;
INSERT INTO snapshot SELECT 'incremental', kind, row_text FROM stored_rows;
SELECT worker.enqueue_derive_statistical_unit_all() IS NOT NULL AS rebuild_scheduled;
CALL worker.process_tasks(p_queue => 'analytics');
INSERT INTO snapshot SELECT 'rebuilt', kind, row_text FROM stored_rows;
SELECT
    (SELECT count(*) FROM (SELECT kind, row_text FROM snapshot WHERE label = 'rebuilt'
                           EXCEPT ALL SELECT kind, row_text FROM snapshot WHERE label = 'incremental') AS x) AS only_in_rebuild,
    (SELECT count(*) FROM (SELECT kind, row_text FROM snapshot WHERE label = 'incremental'
                           EXCEPT ALL SELECT kind, row_text FROM snapshot WHERE label = 'rebuilt') AS x) AS only_in_incremental;

\echo
\echo "368.6 the staged rows survive a database crash: the staging tables are logged (an unlogged table is emptied by crash recovery)"
SELECT c.relname, c.relpersistence
FROM pg_class AS c
WHERE c.oid IN ('public.statistical_history_facet_stock_delta_staging'::regclass,
                'public.statistical_history_facet_flow_delta_staging'::regclass)
ORDER BY c.relname;

ROLLBACK;
