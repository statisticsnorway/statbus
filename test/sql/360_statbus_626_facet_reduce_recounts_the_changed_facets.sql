-- STATBUS-626: a small edit refreshes only the facets it changed, and the facet table always
-- equals its definition.
--
-- worker.statistical_unit_facet_reduce keeps public.statistical_unit_facet equal to
-- public.statistical_unit_facet_def (the facet counts over statistical_unit). After a partial
-- cycle it recounts only the facets the cycle's units left or entered: the facet keys staged in
-- the rewritten hash ranges before the rewrite (worker.derive_statistical_unit_facet records
-- them) together with the keys staged after it. A facet that loses its last contributor is
-- deleted.
--
-- The April 2026 scoped reduce (20260422000000) recounted the same two sides but kept the
-- before-side in a table every derive emptied. A cycle whose reduce failed lost that cycle's
-- before-side when the next cycle derived again, so a facet the first cycle left stayed counted
-- (20260429233218 collapsed the reduce to a whole-table MERGE).
--
-- Fixture: the demo legal units, imported and derived. Then incremental cycles, each a different
-- kind of change, and after each the stored facets are compared with the definition:
--   A. a legal unit moves from 2024-01-01 to a region no other unit has (it enters a new facet),
--   B. the same unit moves on to a second unused region (its sole-contributor facet empties),
--   C. a new legal unit,
--   D. the new legal unit is deleted with its enterprise (units leave through orphan cleanup),
--   E. a move whose facet reduce fails, then a cycle with an unrelated new unit: the second
--      cycle's reduce must still remove the facet the first cycle's unit left.
-- 360.6 shows a partial cycle's reduce recounts only its keys; 360.7 a full recalculation.

BEGIN;

\i test/setup.sql

\echo "Test 360 (STATBUS-626): the facet table equals its definition after partial cycles"

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_360_lu', 'Test 360 legal units', 'Test 360 (STATBUS-626)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_360_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- Stored facets and the definition, as comparable text rows.
CREATE TEMP VIEW stored_facets AS
SELECT concat_ws('|', f.valid_from, f.valid_to, f.valid_until, f.unit_type, f.physical_region_path,
                 f.primary_activity_category_path, f.sector_path, f.legal_form_id, f.physical_country_id,
                 f.status_id, f.count, f.stats_summary) AS row_text
FROM public.statistical_unit_facet AS f;
CREATE TEMP VIEW defined_facets AS
SELECT concat_ws('|', d.valid_from, d.valid_to, d.valid_until, d.unit_type, d.physical_region_path,
                 d.primary_activity_category_path, d.sector_path, d.legal_form_id, d.physical_country_id,
                 d.status_id, d.count, d.stats_summary) AS row_text
FROM public.statistical_unit_facet_def AS d;
CREATE TEMP VIEW facets_vs_definition AS
SELECT (SELECT count(*) FROM stored_facets) AS stored,
       (SELECT count(*) FROM defined_facets) AS defined,
       (SELECT count(*) FROM (SELECT row_text FROM stored_facets EXCEPT ALL SELECT row_text FROM defined_facets) AS x) AS only_stored,
       (SELECT count(*) FROM (SELECT row_text FROM defined_facets EXCEPT ALL SELECT row_text FROM stored_facets) AS x) AS only_defined;

-- Each cycle imports one row through the legal unit import and drains analytics.
CREATE PROCEDURE pg_temp.import_lu(p_slug text, p_tax_ident text, p_name text, p_valid_from date, p_region text)
LANGUAGE plpgsql AS $import_lu$
BEGIN
    INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
    SELECT id, p_slug, 'Test 360 ' || p_slug, 'Test 360 (STATBUS-626)', false
    FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    EXECUTE format($$INSERT INTO public.%1$I (tax_ident, name, valid_from, valid_to, physical_region_code, employees)
                    VALUES ($1, $2, $3, 'infinity', $4, '3')$$, p_slug || '_upload')
    USING p_tax_ident, p_name, p_valid_from::text, p_region;
END;
$import_lu$;

-- Regions 22121 and 22122 hold no demo unit, so a unit moved there is the facet's only contributor.
\echo
\echo "360.0 after the first load the facets equal their definition"
SELECT * FROM facets_vs_definition;

\echo
\echo "360.1 cycle A: a legal unit moves from 2024-01-01 to region 22121, which no other unit is in"
CALL pg_temp.import_lu('import_360_a', '2220794', 'The Office Corp', '2024-01-01', '22121');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
SELECT * FROM facets_vs_definition;
SELECT f.unit_type, f.valid_from, f.count
FROM public.statistical_unit_facet AS f
WHERE f.physical_region_path = (SELECT path FROM public.region WHERE code = '22121')
ORDER BY f.unit_type, f.valid_from;

\echo
\echo "360.2 cycle B: the same unit moves on from 2024-01-01 to region 22122; region 22121 is left with no unit"
CALL pg_temp.import_lu('import_360_b', '2220794', 'The Office Corp', '2024-01-01', '22122');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
SELECT * FROM facets_vs_definition;
SELECT r.code, count(f.*) AS facets, COALESCE(sum(f.count), 0) AS units
FROM public.region AS r
LEFT JOIN public.statistical_unit_facet AS f ON f.physical_region_path = r.path
WHERE r.code IN ('22121', '22122')
GROUP BY r.code ORDER BY r.code;

\echo
\echo "360.3 cycle C: a new legal unit from 2022-03-15"
CALL pg_temp.import_lu('import_360_c', '360000001', 'Test 360 new unit', '2022-03-15', '104601');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
SELECT * FROM facets_vs_definition;

\echo
\echo "360.4 cycle D: the new legal unit is deleted with its enterprise"
CREATE TEMP TABLE _victim ON COMMIT DROP AS
SELECT lu.id AS lu_id, lu.enterprise_id AS ent_id
FROM public.legal_unit AS lu
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id AND ei.ident = '360000001';
SET LOCAL ROLE postgres;
SET CONSTRAINTS ALL DEFERRED;
DELETE FROM public.activity       WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.location       WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.contact        WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.stat_for_unit  WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.external_ident WHERE legal_unit_id IN (SELECT lu_id FROM _victim);
DELETE FROM public.legal_unit     WHERE id IN (SELECT lu_id FROM _victim);
DELETE FROM public.enterprise     WHERE id IN (SELECT ent_id FROM _victim);
SET CONSTRAINTS ALL IMMEDIATE;
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
CALL worker.process_tasks(p_queue => 'analytics');
SELECT * FROM facets_vs_definition;

\echo
\echo "360.5 cycle E: the unit moves back to region 22121 and the facet reduce fails; the next cycle adds an unrelated unit"
-- The reduce handler is replaced by one that raises, as a lost connection would end the step.
-- Cycle E's facet children have rewritten staging; its facets are not reduced.
CREATE PROCEDURE pg_temp.reduce_that_fails(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
LANGUAGE plpgsql AS $reduce_that_fails$
BEGIN
    RAISE EXCEPTION 'test 360: the facet reduce stops before it commits';
END;
$reduce_that_fails$;
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
UPDATE worker.command_registry SET handler_procedure = 'pg_temp.reduce_that_fails'
 WHERE command = 'statistical_unit_facet_reduce';
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
CALL pg_temp.import_lu('import_360_e', '2220794', 'The Office Corp', '2024-01-01', '22121');
CALL worker.process_tasks(p_queue => 'import');
CALL pg_temp.process_analytics_quietly();
SELECT t.command, t.state
FROM worker.tasks AS t
WHERE t.command = 'statistical_unit_facet_reduce'
ORDER BY t.id DESC LIMIT 1;

SET LOCAL ROLE postgres;
UPDATE worker.command_registry SET handler_procedure = 'worker.statistical_unit_facet_reduce'
 WHERE command = 'statistical_unit_facet_reduce';
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
CALL pg_temp.import_lu('import_360_e2', '360000002', 'Test 360 unrelated unit', '2023-06-01', '397601');
CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');
SELECT * FROM facets_vs_definition;
SELECT r.code, count(f.*) AS facets, COALESCE(sum(f.count), 0) AS units
FROM public.region AS r
LEFT JOIN public.statistical_unit_facet AS f ON f.physical_region_path = r.path
WHERE r.code IN ('22121', '22122')
GROUP BY r.code ORDER BY r.code;

\echo
\echo "360.6 the reduce of a partial cycle recounts only the facets its units left or entered"
SELECT t.info->>'mode' AS mode,
       (t.info->>'keys_recounted')::int < (SELECT count(*) FROM public.statistical_unit_facet) AS fewer_keys_than_facets
FROM worker.tasks AS t
WHERE t.command = 'statistical_unit_facet_reduce' AND t.state = 'completed'
ORDER BY t.id DESC LIMIT 1;

\echo
\echo "360.7 a full recalculation recounts every facet and leaves the table equal to its definition"
SELECT worker.enqueue_derive_statistical_unit_all() IS NOT NULL AS rebuild_scheduled;
CALL worker.process_tasks(p_queue => 'analytics');
SELECT * FROM facets_vs_definition;
SELECT t.info->>'mode' AS mode
FROM worker.tasks AS t
WHERE t.command = 'statistical_unit_facet_reduce' AND t.state = 'completed'
ORDER BY t.id DESC LIMIT 1;

ROLLBACK;
