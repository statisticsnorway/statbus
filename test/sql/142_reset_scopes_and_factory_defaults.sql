-- 50bwaz: reset scopes follow the reset dialog, and a reset restores factory
-- defaults.
--
-- The dialog offers Units; Units and Getting started; Units, Getting started
-- and Customisation. public.reset_scope has the same three values:
--   units           the statistical units and the import jobs that made them
--   getting-started units + the six Getting started steps (country and
--                   activity category standard in settings, custom activity
--                   codes, regions, custom sectors, custom legal forms) and
--                   the activity category standards as shipped
--   customisation   getting-started + the /admin Customisation section: every
--                   system row restored from <table>_factory_default, custom
--                   rows removed; users untouched
-- System priorities start at 10 in steps of 10, so 1-9 are free for users,
-- and a priority is unique among enabled rows only.
BEGIN;

\i test/setup.sql

\echo "Test 142: reset scopes and factory defaults (50bwaz)"

\echo "142.1: the reset scopes are the three the dialog names"
SELECT enum_range(NULL::public.reset_scope) AS reset_scopes;

\echo "142.2: shipped priorities start at 10, person_ident disabled"
SELECT code, priority, enabled FROM public.external_ident_type_factory_default ORDER BY priority;
SELECT code, priority, enabled FROM public.stat_definition_factory_default ORDER BY priority;
SELECT code, priority FROM public.status_factory_default ORDER BY priority;
SELECT code, code_pattern FROM public.activity_category_standard_factory_default ORDER BY code;

\echo "142.3: a fresh database holds the shipped rows (setup enables person_ident for import tests)"
SELECT code, priority FROM public.stat_definition ORDER BY priority;
SELECT code, priority FROM public.status ORDER BY priority;
SELECT code, priority FROM public.external_ident_type ORDER BY priority;

\echo "142.4: a priority is unique among enabled rows only"
SAVEPOINT s_priority;
INSERT INTO public.stat_definition(code, type, frequency, name, priority, enabled)
VALUES ('disabled_at_10', 'int', 'yearly', 'Disabled at 10', 10, false);
SELECT code, priority, enabled FROM public.stat_definition WHERE priority = 10 ORDER BY code;
SAVEPOINT s_enabled_clash;
INSERT INTO public.stat_definition(code, type, frequency, name, priority, enabled)
VALUES ('enabled_at_10', 'int', 'yearly', 'Enabled at 10', 10, true);
ROLLBACK TO SAVEPOINT s_enabled_clash;
INSERT INTO public.status(code, name, assigned_by_default, used_for_counting, priority, enabled, custom)
VALUES ('mine', 'Mine', false, false, 1, true, true);
SAVEPOINT s_status_clash;
INSERT INTO public.status(code, name, assigned_by_default, used_for_counting, priority, enabled, custom)
VALUES ('mine_too', 'Mine too', false, false, 1, true, true);
ROLLBACK TO SAVEPOINT s_status_clash;
ROLLBACK TO SAVEPOINT s_priority;

-- A database a user has set up and filled: Getting started done, /admin
-- customised (system rows edited, custom rows added), units imported.
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.settings(activity_category_standard_id, country_id, region_version_id)
SELECT (SELECT id FROM public.activity_category_standard WHERE code = 'nace_v2.1')
     , (SELECT id FROM public.country WHERE iso_2 = 'NO')
     , (SELECT id FROM public.region_version WHERE code = 'initial');
INSERT INTO public.region_upload(path, name) VALUES ('01', 'Region one');
INSERT INTO public.sector_custom(path, name) VALUES ('9000', 'Custom sector');
INSERT INTO public.legal_form_custom(code, name) VALUES ('XX', 'Custom legal form');
INSERT INTO public.activity_category_enabled_custom(path, name) VALUES ('A.01.1', 'Custom A.01.1');
UPDATE public.activity_category_standard SET code_pattern = 'digits' WHERE code = 'nace_v2.1';
UPDATE public.unit_size SET name = 'Teeny' WHERE code = 'tny';
UPDATE public.data_source SET enabled = false WHERE code = 'census';
UPDATE public.status SET name = 'Live', priority = 5 WHERE code = 'active';
UPDATE public.stat_definition SET name = 'Staff' WHERE code = 'employees';
DELETE FROM public.stat_definition WHERE code = 'turnover';
UPDATE public.external_ident_type SET enabled = true, priority = 3 WHERE code = 'person_ident';
INSERT INTO public.unit_size_custom(code, name) VALUES ('xl', 'Extra large');
INSERT INTO public.import_job(definition_id, slug, description, edit_comment, time_frame_ident)
SELECT id, 'test_142_job', 'Test 142 job', 'Test 142', 'live'
  FROM public.import_definition WHERE slug = 'legal_unit_job_provided';
RESET ROLE;

CREATE TEMP VIEW state AS
SELECT (SELECT count(*) FROM public.import_job WHERE slug = 'test_142_job') AS import_jobs
     , (SELECT count(*) FROM public.settings) AS settings
     , (SELECT count(*) FROM public.region) AS regions
     , (SELECT count(*) FROM public.sector WHERE custom) AS custom_sectors
     , (SELECT count(*) FROM public.legal_form WHERE custom) AS custom_legal_forms
     , (SELECT count(*) FROM public.activity_category WHERE custom) AS custom_activity_codes
     , (SELECT code_pattern FROM public.activity_category_standard WHERE code = 'nace_v2.1') AS nace_code_pattern
     , (SELECT ac.code FROM public.activity_category AS ac JOIN public.activity_category_standard AS s ON s.id = ac.standard_id
         WHERE s.code = 'nace_v2.1' AND ac.path = 'A.01.1.1' AND NOT ac.custom) AS nace_code_0111
     , (SELECT name FROM public.unit_size WHERE code = 'tny' AND NOT custom) AS tny_name
     , (SELECT count(*) FROM public.unit_size WHERE custom) AS custom_unit_sizes
     , (SELECT enabled FROM public.data_source WHERE code = 'census') AS census_enabled
     , (SELECT name || '/' || priority FROM public.status WHERE code = 'active' AND NOT custom) AS active_status
     , (SELECT name FROM public.stat_definition WHERE code = 'employees') AS employees_name
     , (SELECT count(*) FROM public.stat_definition WHERE code = 'turnover') AS turnover_rows
     , (SELECT enabled || '/' || priority FROM public.external_ident_type WHERE code = 'person_ident') AS person_ident
     , (SELECT count(*) FROM auth.user WHERE email LIKE 'test.%@statbus.org') AS test_users;

\echo "142.5: before any reset"
SELECT * FROM state;

\echo "142.6: units removes the units and their import jobs, keeps Getting started and /admin"
SAVEPOINT s_units;
SELECT public.reset(true, 'units') ? 'import_job' AS reports_import_jobs;
SELECT * FROM state;
ROLLBACK TO SAVEPOINT s_units;

\echo "142.7: getting-started also empties the Getting started steps and restores the standards; /admin stays"
SAVEPOINT s_getting_started;
SELECT public.reset(true, 'getting-started') IS NOT NULL AS reset_ran;
SELECT * FROM state;
ROLLBACK TO SAVEPOINT s_getting_started;

\echo "142.8: customisation also restores every /admin system row as shipped; users stay"
SAVEPOINT s_customisation;
SELECT public.reset(true, 'customisation') IS NOT NULL AS reset_ran;
SELECT * FROM state;
SELECT code, name, priority, enabled FROM public.external_ident_type ORDER BY priority;
SELECT code, name, priority, enabled FROM public.stat_definition ORDER BY priority;
SELECT code, name, priority, enabled FROM public.status ORDER BY priority;
SELECT code, name, enabled FROM public.unit_size ORDER BY code;
SELECT code, name, enabled FROM public.data_source ORDER BY code;
ROLLBACK TO SAVEPOINT s_customisation;

ROLLBACK;
