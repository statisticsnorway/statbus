-- STATBUS-604: a user edits a unit through the for-portion-of views, as the
-- app does through PostgREST, and the edit lands exactly where the unit exists
-- inside the portion. Every session runs under pg_safeupdate
-- (postgres/postgresql.conf), so each statement the edit causes, including
-- those in triggers, names the rows it changes.
BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all

\echo "The guard is active in this session, as in every production session"
SELECT current_setting('safeupdate.enabled') AS safeupdate_enabled;

\echo "Load two legal units over time and their establishments"
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
       'import_397_lu_era', 'Legal units over time (397)', 'test 397', 'Test data load (397)';
\copy public.import_397_lu_era_upload(valid_from,valid_to,tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,sector_code,legal_form_code,data_source_code) FROM 'test/data/03_norwegian-legal-units-over-time.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
CALL worker.process_tasks(p_queue => 'import');

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
SELECT (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
       'import_397_es_era', 'Establishments over time (397)', 'test 397', 'Test data load (397)';
\copy public.import_397_es_era_upload(valid_from, valid_to, tax_ident,legal_unit_tax_ident,name,birth_date,death_date,physical_address_part1,physical_postcode,physical_postplace,physical_region_code,physical_country_iso_2,postal_address_part1,postal_postcode,postal_postplace,postal_region_code,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,data_source_code,unit_size_code,employees,turnover) FROM 'test/data/03_norwegian-establishments-over-time.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
CALL worker.process_tasks(p_queue => 'import');

SELECT slug, state FROM public.import_job WHERE slug LIKE 'import_397_%' ORDER BY slug;

\echo "Starting state: the legal unit KRAN & SPESIALLØFT AS exists from 2013-01-01"
SELECT lu.name, lu.valid_from, lu.valid_to
  FROM public.legal_unit AS lu
  JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
  JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
 WHERE ei.ident = '921835809'
 ORDER BY lu.valid_from;

SELECT ei.legal_unit_id AS lu_id FROM public.external_ident AS ei
  JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
 WHERE ei.ident = '921835809' \gset
SELECT ei.legal_unit_id AS other_lu_id FROM public.external_ident AS ei
  JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
 WHERE ei.ident = '823573673' \gset
SELECT min(es.id) AS es_id FROM public.establishment AS es WHERE es.legal_unit_id = :lu_id \gset

CREATE TEMP TABLE other_units_before ON COMMIT DROP AS
SELECT 'legal_unit' AS kind, id, name, valid_from, valid_to FROM public.legal_unit WHERE id <> :lu_id
UNION ALL
SELECT 'establishment', id, name, valid_from, valid_to FROM public.establishment WHERE id <> :es_id;

\echo "1. Rename the legal unit for exactly its own row (2013-01-01 .. infinity)"
UPDATE public.legal_unit__for_portion_of_valid
   SET name = 'KRAN 604 AS', valid_from = '2013-01-01', valid_to = 'infinity'
 WHERE id = :lu_id;

SELECT name, valid_from, valid_to FROM public.legal_unit WHERE id = :lu_id ORDER BY valid_from;

\echo "2. Rename it with a portion starting before the unit existed (2010-01-01 .. infinity):"
\echo "   the change applies from 2013-01-01 and no row appears before it"
UPDATE public.legal_unit__for_portion_of_valid
   SET name = 'KRAN 604 EARLY AS', valid_from = '2010-01-01', valid_to = 'infinity'
 WHERE id = :lu_id;

SELECT name, valid_from, valid_to FROM public.legal_unit WHERE id = :lu_id ORDER BY valid_from;

\echo "3. Rename the establishment for the portion it exists in"
SELECT valid_from AS es_from FROM public.establishment WHERE id = :es_id ORDER BY valid_from LIMIT 1 \gset
UPDATE public.establishment__for_portion_of_valid
   SET name = 'KRAN 604 ESTABLISHMENT', valid_from = :'es_from', valid_to = 'infinity'
 WHERE id = :es_id;

SELECT name, valid_from, valid_to FROM public.establishment WHERE id = :es_id ORDER BY valid_from;

\echo "4. Change the legal unit's physical address for its whole existence"
UPDATE public.location__for_portion_of_valid
   SET address_part1 = 'Testveien 604', valid_from = '2013-01-01', valid_to = 'infinity'
 WHERE legal_unit_id = :lu_id AND type = 'physical';

SELECT address_part1, valid_from, valid_to FROM public.location
 WHERE legal_unit_id = :lu_id AND type = 'physical' ORDER BY valid_from;

\echo "Every other unit is unchanged"
SELECT count(*) AS other_units_changed
  FROM (
    SELECT kind, id, name, valid_from, valid_to FROM other_units_before
    EXCEPT
    (SELECT 'legal_unit', id, name, valid_from, valid_to FROM public.legal_unit WHERE id <> :lu_id
     UNION ALL
     SELECT 'establishment', id, name, valid_from, valid_to FROM public.establishment WHERE id <> :es_id)
  ) AS changed;

ROLLBACK;
