-- STATBUS-477 family E: reloading the country list through country_view keeps
-- the countries it contains and corrects them in place.
--
-- country_view is loaded by migrations only, from the shipped
-- dbseed/country/country_codes.csv. Before the fix, admin.upsert_country
-- conflicted on (iso_2, iso_3, iso_num, name) WHERE country.id = EXCLUDED.id
-- (never fires; and name in the target means a corrected name never
-- conflicts), and admin.delete_stale_country deleted every country older than
-- the statement, so a reload left 0 countries, or aborted on RESTRICT when
-- settings referenced a country.
--
-- Invariants checked:
--   1. With settings referencing NO, reloading the shipped file keeps all its
--      countries with the same ids, and settings intact.
--   2. A reload that corrects NO's name updates it in place (same id).
--   3. A reload without one unreferenced country removes only that country.
--   4. A reload without a referenced country fails on the RESTRICT foreign key
--      and changes nothing (the transaction is the unit).
BEGIN;

\i test/setup.sql

\echo "Test 135: country reload keeps and corrects countries (STATBUS-477 family E)"

INSERT INTO public.settings(activity_category_standard_id, country_id, region_version_id)
SELECT (SELECT id FROM public.activity_category_standard WHERE code = 'nace_v2.1')
     , (SELECT id FROM public.country WHERE iso_2 = 'NO')
     , (SELECT id FROM public.region_version WHERE code = 'initial');

CREATE TEMP TABLE country_before AS SELECT id, iso_2, name FROM public.country;
CREATE TEMP TABLE country_file(name text, iso_2 text, iso_3 text, iso_num text);
\copy country_file(name, iso_2, iso_3, iso_num) FROM 'dbseed/country/country_codes.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true)

\echo "135.1: reload the shipped file with settings referencing NO"
\copy public.country_view(name, iso_2, iso_3, iso_num) FROM 'dbseed/country/country_codes.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true)
SELECT (SELECT count(*) FROM country_file) AS countries_in_file
     , (SELECT count(*) FROM public.country) AS countries_after
     , (SELECT count(*) FROM country_before AS b JOIN public.country AS c ON c.id = b.id AND c.iso_2 = b.iso_2) AS kept_with_same_id
     , (SELECT c.iso_2 FROM public.settings AS s JOIN public.country AS c ON c.id = s.country_id) AS settings_country;

\echo "135.2: a reload correcting NO's name updates it in place"
UPDATE country_file SET name = 'Norway (corrected)' WHERE iso_2 = 'NO';
INSERT INTO public.country_view(name, iso_2, iso_3, iso_num)
SELECT name, iso_2, iso_3, iso_num FROM country_file ORDER BY iso_2;
SELECT c.iso_2, c.name, c.id = (SELECT id FROM country_before WHERE iso_2 = 'NO') AS same_id
  FROM public.country AS c WHERE c.iso_2 = 'NO';
SELECT count(*) AS countries_after FROM public.country;

\echo "135.3: a reload without an unreferenced country (AQ) removes only that country"
INSERT INTO public.country_view(name, iso_2, iso_3, iso_num)
SELECT name, iso_2, iso_3, iso_num FROM country_file WHERE iso_2 <> 'AQ' ORDER BY iso_2;
SELECT count(*) AS countries_after
     , count(*) FILTER (WHERE iso_2 = 'AQ') AS aq_rows
  FROM public.country;

\echo "135.4: a reload without a referenced country (NO) fails on RESTRICT and changes nothing"
SAVEPOINT before_bad_reload;
\set ON_ERROR_STOP off
\set VERBOSITY terse
INSERT INTO public.country_view(name, iso_2, iso_3, iso_num)
SELECT name, iso_2, iso_3, iso_num FROM country_file WHERE iso_2 <> 'NO' ORDER BY iso_2;
\set VERBOSITY default
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_bad_reload;
SELECT count(*) AS countries_after
     , (SELECT name FROM public.country WHERE iso_2 = 'NO') AS no_name
  FROM public.country;

ROLLBACK;
