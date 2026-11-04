-- STATBUS-558: the history delta tables after incremental cycles equal a full rebuild.
--
-- public.statistical_history_facet_stock_delta and public.statistical_history_facet_flow_delta are maintained per
-- cycle: worker.derive_statistical_history_facet_delta stages, per hash range, the new versions
-- of the refreshed units minus their old versions, and
-- worker.statistical_history_facet_delta_reduce adds the staged rows in. A full rebuild
-- (worker.enqueue_derive_statistical_unit_all) recomputes both tables from
-- statistical_unit alone. The two must hold the same rows: every cell, date,
-- count, flow, stats value and unit_ids list.
--
-- Fixture: the demo legal units and establishments, imported and derived
-- (the first cycle adds every unit incrementally: statistical_unit is still
-- empty when it runs, so there is nothing to rebuild from). Then three incremental
-- cycles, each a different kind of change:
--   A. a region move from 2024-01-01 (a unit leaves one cell and enters another),
--   B. a new legal unit (a unit enters),
--   C. a legal unit deleted with its establishments' links (units leave
--      through worker.derive_statistical_unit's orphan cleanup).
-- 367.8 adds a unit with no known start (valid_from -infinity), which must
-- count from the first period.
-- After each cycle the stored rows are snapshotted; a final rebuild then must
-- reproduce the last snapshot exactly.

BEGIN;

\i test/setup.sql

\echo "Test 367 (STATBUS-558): incremental history deltas equal a full rebuild"

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_367_lu', 'Test 367 legal units', 'Test 367 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_367_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_367_es', 'Test 367 establishments', 'Test 367 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
\copy public.import_367_es_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM 'app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- The stored rows of both tables. A stats_delta keeps gross in and out flows, which depend on the
-- path of changes; the stock a row contributes is in minus out, so rows are compared by that net,
-- per variable and field (count, sum, sum_sq, or each category count).
CREATE TEMP TABLE snapshot (label text, kind text, row_text text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.stats_net(d jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $stats_net$
    SELECT string_agg(x.key || '.' || x.field || '=' || x.net, ',' ORDER BY x.key, x.field)
    FROM (SELECT e.key, f.field,
                 COALESCE((e.value->'in'->>f.field)::numeric, 0) - COALESCE((e.value->'out'->>f.field)::numeric, 0) AS net
          FROM jsonb_each(COALESCE(d, '{}') - 'type'::text) AS e
          CROSS JOIN LATERAL (SELECT jsonb_object_keys(COALESCE(e.value->'in', '{}') || COALESCE(e.value->'out', '{}')) AS field) AS f
          WHERE jsonb_typeof(COALESCE(e.value->'in'->f.field, e.value->'out'->f.field)) = 'number'
          UNION ALL
          SELECT e.key, f.field || '.' || c.k,
                 COALESCE((e.value->'in'->f.field->>c.k)::numeric, 0) - COALESCE((e.value->'out'->f.field->>c.k)::numeric, 0)
          FROM jsonb_each(COALESCE(d, '{}') - 'type'::text) AS e
          CROSS JOIN LATERAL (SELECT jsonb_object_keys(COALESCE(e.value->'in', '{}') || COALESCE(e.value->'out', '{}')) AS field) AS f
          CROSS JOIN LATERAL (SELECT jsonb_object_keys(COALESCE(e.value->'in'->f.field, '{}') || COALESCE(e.value->'out'->f.field, '{}')) AS k
                              WHERE jsonb_typeof(COALESCE(e.value->'in'->f.field, e.value->'out'->f.field)) = 'object') AS c) AS x
    WHERE x.net <> 0
$stats_net$;
CREATE TEMP VIEW stored_rows AS
SELECT 'stock' AS kind,
       concat_ws('|', d.unit_type, d.primary_activity_category_path, d.secondary_activity_category_path, d.sector_path,
                 d.legal_form_id, d.physical_region_path, d.physical_country_id, d.unit_size_id, d.status_id,
                 d.on_month, d.exists_delta, d.countable_delta,
                 pg_temp.stats_net(d.stats_delta), d.unit_ids) AS row_text
FROM public.statistical_history_facet_stock_delta AS d
UNION ALL
SELECT 'flow',
       concat_ws('|', f.resolution, f.year, f.month, f.unit_type, f.primary_activity_category_path,
                 f.secondary_activity_category_path, f.sector_path, f.legal_form_id, f.physical_region_path,
                 f.physical_country_id, f.unit_size_id, f.status_id, f.flows,
                 pg_temp.stats_net(f.stats_ended), f.unit_ids)
FROM public.statistical_history_facet_flow_delta AS f;

\echo
\echo "367.0 the first cycle added every unit (statistical_unit was still empty, so nothing to rebuild) and every task completed"
SELECT t.command, t.state, t.info->>'rebuild' AS rebuild
FROM worker.tasks AS t
WHERE t.command = 'derive_statistical_history_facet_delta'
ORDER BY t.id;
SELECT count(*) FILTER (WHERE t.state <> 'completed') AS not_completed
FROM worker.tasks AS t
JOIN worker.command_registry AS c ON c.command = t.command
WHERE c.queue = 'analytics';

INSERT INTO snapshot SELECT 'initial', kind, row_text FROM stored_rows;

\echo
\echo "367.1 cycle A: one legal unit moves region from 2024-01-01"
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_367_move', 'Test 367 region move', 'Test 367 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_367_move_upload(tax_ident, name, valid_from, valid_to, physical_region_code)
VALUES ('2220794', 'The Office Corp', '2024-01-01', 'infinity', '225602');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
INSERT INTO snapshot SELECT 'after_move', kind, row_text FROM stored_rows;

\echo
\echo "367.2 cycle B: a new legal unit from 2022-03-15"
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_367_new', 'Test 367 new unit', 'Test 367 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_367_new_upload(tax_ident, name, valid_from, valid_to, physical_region_code, employees)
VALUES ('367000001', 'Test 367 new unit', '2022-03-15', 'infinity', '104601', '7');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
INSERT INTO snapshot SELECT 'after_new', kind, row_text FROM stored_rows;

\echo
\echo "367.3 cycle C: the new legal unit is deleted with its enterprise"
CREATE TEMP TABLE _victim ON COMMIT DROP AS
SELECT lu.id AS lu_id, lu.enterprise_id AS ent_id
FROM public.legal_unit AS lu
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id AND ei.ident = '367000001';
SET LOCAL ROLE postgres;
SET CONSTRAINTS ALL DEFERRED;
DELETE FROM public.activity      WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.location      WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.contact       WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.stat_for_unit WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.external_ident WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.legal_unit    WHERE id IN (SELECT lu_id FROM _victim);
DELETE FROM public.enterprise    WHERE id IN (SELECT ent_id FROM _victim);
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
CALL worker.process_tasks(p_queue => 'analytics');
INSERT INTO snapshot SELECT 'after_delete', kind, row_text FROM stored_rows;

\echo
\echo "367.4 the first load and the three change cycles were all incremental (no rebuild), and every task completed"
SELECT t.info->>'rebuild' AS rebuild, count(*) AS cycles
FROM worker.tasks AS t
WHERE t.command = 'derive_statistical_history_facet_delta'
GROUP BY 1 ORDER BY 1;
SELECT count(*) FILTER (WHERE t.state <> 'completed') AS not_completed
FROM worker.tasks AS t
JOIN worker.command_registry AS c ON c.command = t.command
WHERE c.queue = 'analytics';

\echo
\echo "367.5 each cycle changed the stored rows (rows that differ from the previous snapshot)"
WITH s AS (SELECT * FROM snapshot),
pairs(prev, curr) AS (VALUES ('initial', 'after_move'), ('after_move', 'after_new'), ('after_new', 'after_delete'))
SELECT p.curr AS snapshot,
       (SELECT count(*) FROM (SELECT kind, row_text FROM s WHERE label = p.curr
                              EXCEPT ALL SELECT kind, row_text FROM s WHERE label = p.prev) AS x) AS rows_added_or_changed,
       (SELECT count(*) FROM (SELECT kind, row_text FROM s WHERE label = p.prev
                              EXCEPT ALL SELECT kind, row_text FROM s WHERE label = p.curr) AS x) AS rows_removed_or_changed
FROM pairs AS p ORDER BY p.curr;

\echo
\echo "367.6 no row lists the deleted legal unit or its enterprise; the moved unit is listed under its new region from 2024"
SELECT k.kind, k.unit_type, k.on_month, k.year, k.unit_ids
FROM (SELECT 'stock' AS kind, unit_type, on_month, NULL::int AS year, unit_ids FROM public.statistical_history_facet_stock_delta
      UNION ALL SELECT 'flow', unit_type, NULL, year, unit_ids FROM public.statistical_history_facet_flow_delta) AS k
WHERE (k.unit_type = 'legal_unit' AND (SELECT lu_id FROM _victim) = ANY (k.unit_ids))
   OR (k.unit_type = 'enterprise' AND (SELECT ent_id FROM _victim) = ANY (k.unit_ids));
SELECT d.physical_region_path, d.on_month, d.exists_delta
FROM public.statistical_history_facet_stock_delta AS d
WHERE d.unit_type = 'legal_unit'
  AND (SELECT su.unit_id FROM public.statistical_unit AS su
        WHERE su.unit_type = 'legal_unit' AND su.external_idents->>'tax_ident' = '2220794' LIMIT 1) = ANY (d.unit_ids)
ORDER BY d.on_month, d.physical_region_path;

\echo
\echo "367.7 a full rebuild reproduces the incremental result exactly, unit_ids included"
SELECT worker.enqueue_derive_statistical_unit_all() IS NOT NULL AS rebuild_scheduled;
CALL worker.process_tasks(p_queue => 'analytics');
INSERT INTO snapshot SELECT 'rebuilt', kind, row_text FROM stored_rows;
SELECT kind,
       count(*) FILTER (WHERE label = 'rebuilt') AS rebuilt_rows,
       count(*) FILTER (WHERE label = 'after_delete') AS incremental_rows
FROM snapshot WHERE label IN ('rebuilt', 'after_delete')
GROUP BY kind ORDER BY kind;
SELECT
    (SELECT count(*) FROM (SELECT kind, row_text FROM snapshot WHERE label = 'rebuilt'
                           EXCEPT ALL SELECT kind, row_text FROM snapshot WHERE label = 'after_delete') AS x) AS only_in_rebuild,
    (SELECT count(*) FROM (SELECT kind, row_text FROM snapshot WHERE label = 'after_delete'
                           EXCEPT ALL SELECT kind, row_text FROM snapshot WHERE label = 'rebuilt') AS x) AS only_in_incremental;
SELECT (SELECT t.info->>'rebuild' FROM worker.tasks AS t WHERE t.command = 'derive_statistical_history_facet_delta' ORDER BY t.id DESC LIMIT 1) AS last_cycle_rebuilt;

\echo
\echo "367.8 a unit valid from -infinity counts from the first period to its end (review finding 1)"
-- Crafted statistical_unit rows, as derive would write them: unit 9001 has no known start and ends
-- 2020-12-31 with 5 employees; it must be in the stock of every period up to 2020 and leave in 2021.
SAVEPOINT unbounded;
SET LOCAL ROLE postgres;
TRUNCATE public.statistical_history_facet_stock_delta, public.statistical_history_facet_flow_delta,
         public.statistical_history_facet_stock_delta_staging, public.statistical_history_facet_flow_delta_staging;
DELETE FROM public.statistical_unit;
INSERT INTO public.statistical_unit (unit_type, unit_id, valid_from, valid_to, valid_until, name, used_for_counting,
                                     hash_slot, stats_summary)
VALUES ('legal_unit', 9001, '-infinity', '2020-12-31', '2021-01-01', 'Unbounded start', true, 1,
        '{"type": "stats_agg", "employees": {"type": "int_agg", "count": 1, "sum": 5, "sum_sq": 25, "min": 5, "max": 5}}'::jsonb),
       ('legal_unit', 9002, '2019-01-01', 'infinity', 'infinity', 'Anchor', true, 2, NULL);
CALL worker.statistical_history_facet_delta_stage_partition('[0,16384)'::int4range, true, 'public.statistical_unit', 'public.statistical_unit');
CALL worker.statistical_history_facet_delta_apply();
CALL public.statistical_history_period_refresh();
SELECT h.year, h.exists_count, h.countable_count, (h.stats_summary->'employees'->>'sum')::numeric AS employees_sum
FROM public.statistical_history AS h
WHERE h.resolution = 'year' AND h.unit_type = 'legal_unit'
ORDER BY h.year;
ROLLBACK TO SAVEPOINT unbounded;

ROLLBACK;
