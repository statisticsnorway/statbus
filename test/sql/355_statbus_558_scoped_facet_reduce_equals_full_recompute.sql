-- STATBUS-558: the facet reduces recompute only the combinations a cycle
-- changed, including the removed ones, and the result equals a reduce over
-- the whole cache.
--
-- After a dirty derive, each per-slot child records the combinations its
-- rewrite changed in worker.statistical_unit_facet_changed or
-- worker.statistical_history_facet_changed, and the reduce recomputes only
-- those. The April 2026 over-count (31 against a true 24 on demo) came from
-- deleted units whose slots were never marked dirty; this test covers that
-- deletion and a unit moving region, for both facet tables.
BEGIN;

\i test/setup.sql

\echo "Test 355 (STATBUS-558): scoped facet reduces equal a full recompute"

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_558_lu', 'Test 355 demo legal units with source dates', 'Test 355 (STATBUS-558)', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
\copy public.import_558_lu_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM 'app/public/demo/legal_units_with_source_dates_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

-- The checks read the per-slot caches, which only the worker's roles may
-- read; a view reads its tables with its owner's rights, so they are created
-- and read as postgres.
SET LOCAL ROLE postgres;

-- Rows where a facet table differs from a reduce over its whole cache:
-- missing_or_wrong are combinations the target lacks or counts differently,
-- stale are target rows the cache no longer supports.
CREATE TEMP VIEW facet_vs_full_recompute AS
WITH unit_full AS (
    SELECT valid_from, valid_to, valid_until, unit_type,
           physical_region_path::text AS region, primary_activity_category_path::text AS activity,
           sector_path::text AS sector, legal_form_id, physical_country_id, status_id,
           SUM(count)::bigint AS count
      FROM public.statistical_unit_facet_staging
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
unit_target AS (
    SELECT valid_from, valid_to, valid_until, unit_type,
           physical_region_path::text, primary_activity_category_path::text,
           sector_path::text, legal_form_id, physical_country_id, status_id,
           count::bigint
      FROM public.statistical_unit_facet),
history_full AS (
    SELECT resolution, year, month, unit_type,
           primary_activity_category_path::text AS activity, secondary_activity_category_path::text AS secondary,
           sector_path::text AS sector, legal_form_id, physical_region_path::text AS region,
           physical_country_id, unit_size_id, status_id,
           SUM(exists_count)::int AS exists_count, SUM(countable_count)::int AS countable_count,
           SUM(births)::int AS births, SUM(deaths)::int AS deaths
      FROM public.statistical_history_facet_partitions
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12),
history_target AS (
    SELECT resolution, year, month, unit_type,
           primary_activity_category_path::text, secondary_activity_category_path::text,
           sector_path::text, legal_form_id, physical_region_path::text,
           physical_country_id, unit_size_id, status_id,
           exists_count, countable_count, births, deaths
      FROM public.statistical_history_facet)
SELECT 'statistical_unit_facet' AS facet_table,
       (SELECT count(*) FROM (TABLE unit_full EXCEPT TABLE unit_target) AS d) AS missing_or_wrong,
       (SELECT count(*) FROM (TABLE unit_target EXCEPT TABLE unit_full) AS d) AS stale
UNION ALL
SELECT 'statistical_history_facet',
       (SELECT count(*) FROM (TABLE history_full EXCEPT TABLE history_target) AS d),
       (SELECT count(*) FROM (TABLE history_target EXCEPT TABLE history_full) AS d);

-- Units existing today against the drilldown's count for today.
CREATE TEMP VIEW facet_vs_truth_today AS
WITH truth AS (
    SELECT unit_type, COUNT(DISTINCT unit_id)::int AS units
      FROM public.statistical_unit
     WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until AND used_for_counting
     GROUP BY unit_type),
facet AS (
    SELECT unit_type, COALESCE(SUM(count), 0)::int AS units
      FROM public.statistical_unit_facet
     WHERE valid_from <= CURRENT_DATE AND CURRENT_DATE < valid_until
     GROUP BY unit_type)
SELECT t.unit_type, t.units AS existing_units, f.units AS facet_count
  FROM truth AS t LEFT JOIN facet AS f USING (unit_type)
 ORDER BY t.unit_type;

-- How each reduce ran: mode 'full' over the whole cache, or 'dirty' over the
-- recorded combinations. Only reduces after the last checked task are shown.
CREATE TEMP TABLE checked_up_to (task_id bigint);
INSERT INTO checked_up_to VALUES (0);
CREATE TEMP VIEW reduces_since_last_check AS
SELECT command, info->>'mode' AS mode,
       (info->>'changed_combinations')::int > 0 AS recomputed_changed_combinations
  FROM worker.tasks
 WHERE command IN ('statistical_unit_facet_reduce', 'statistical_history_facet_reduce')
   AND id > (SELECT task_id FROM checked_up_to)
 ORDER BY id;

\echo "First load: both reduces run over the whole cache and match it"
SELECT * FROM reduces_since_last_check;
SELECT * FROM facet_vs_full_recompute;
UPDATE checked_up_to SET task_id = (SELECT max(id) FROM worker.tasks);

\echo "One legal unit moves to another region"
UPDATE public.location AS l
   SET region_id = (SELECT r.id FROM public.region AS r WHERE r.id <> l.region_id ORDER BY r.id LIMIT 1)
 WHERE l.id = (SELECT min(id) FROM public.location WHERE legal_unit_id IS NOT NULL AND type = 'physical');
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
CALL worker.process_tasks(p_queue => 'analytics');
SET LOCAL ROLE postgres;

\echo "Both reduces recompute only the changed combinations, and match the full recompute"
SELECT * FROM reduces_since_last_check;
SELECT * FROM facet_vs_full_recompute;
SELECT * FROM facet_vs_truth_today;
UPDATE checked_up_to SET task_id = (SELECT max(id) FROM worker.tasks);

\echo "Three legal units and their enterprises are deleted"
CREATE TEMP TABLE deleted_unit AS
SELECT id AS legal_unit_id, enterprise_id FROM public.legal_unit ORDER BY id LIMIT 3;
SET CONSTRAINTS ALL DEFERRED;
DELETE FROM public.activity      WHERE legal_unit_id IN (SELECT legal_unit_id FROM deleted_unit);
DELETE FROM public.location      WHERE legal_unit_id IN (SELECT legal_unit_id FROM deleted_unit);
DELETE FROM public.contact       WHERE legal_unit_id IN (SELECT legal_unit_id FROM deleted_unit);
DELETE FROM public.stat_for_unit WHERE legal_unit_id IN (SELECT legal_unit_id FROM deleted_unit);
DELETE FROM public.legal_unit    WHERE id IN (SELECT legal_unit_id FROM deleted_unit);
DELETE FROM public.enterprise    WHERE id IN (SELECT enterprise_id FROM deleted_unit);
RESET ROLE;
CALL test.set_user_from_email('test.admin@statbus.org');
CALL worker.process_tasks(p_queue => 'analytics');
SET LOCAL ROLE postgres;

\echo "The removed combinations are recomputed: the facets count the 20 remaining units"
SELECT * FROM reduces_since_last_check;
SELECT * FROM facet_vs_full_recompute;
SELECT * FROM facet_vs_truth_today;

ROLLBACK;
