BEGIN;

\i test/setup.sql


-- This test verifies that an UPDATE on a temporal table correctly triggers
-- the worker to refresh the statistical_unit materialized view.

-- 1. Load initial data using the import system (ported from 306_load_demo_data.sql)
-- 2. Check the initial state of a statistical unit.
-- 3. Perform an UPDATE on a related `activity` record.
-- 4. Verify that a `collect_changes` task is enqueued in worker.tasks.
-- 5. Process the tasks.
-- 6. Verify that the statistical unit has been updated with the new data.

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

-- Create Import Job for Legal Units (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_13_lu',
    'Import LU Demo CSV (313_update_triggers_refresh.sql)',
    'Import job for app/public/demo/legal_units_demo.csv using legal_unit_job_provided definition.',
    'Test data load (313_update_triggers_refresh.sql)',
    'r_year_curr';
\echo "User uploads the sample legal units (via import job: import_13_lu)"
\copy public.import_13_lu_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_job_provided'),
    'import_13_esflu',
    'Import Formal ES Demo CSV (313_update_triggers_refresh.sql)',
    'Import job for app/public/demo/formal_establishments_units_demo.csv using establishment_for_lu_job_provided definition.',
    'Test data load (313_update_triggers_refresh.sql)',
    'r_year_curr';
\echo "User uploads the sample formal establishments (via import job: import_13_esflu)"
\copy public.import_13_esflu_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'app/public/demo/formal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Informal Establishments (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_job_provided'),
    'import_13_eswlu',
    'Import Informal ES Demo CSV (313_update_triggers_refresh.sql)',
    'Import job for app/public/demo/informal_establishments_units_demo.csv using establishment_without_lu_job_provided definition.',
    'Test data load (313_update_triggers_refresh.sql)',
    'r_year_curr';
\echo "User uploads the sample informal establishments (via import job: import_13_eswlu)"
\copy public.import_13_eswlu_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'app/public/demo/informal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
\echo Run worker processing for analytics tasks
CALL worker.process_tasks(p_queue => 'analytics');

--
SELECT unit_type, external_idents, valid_from, valid_until, name, stats->'employees' as employees FROM public.statistical_unit
WHERE name = 'Statistics Norway'
ORDER BY unit_type, unit_id, valid_from, valid_until;

\echo "Initial data loaded. All subsequent tests will check the worker response to an UPDATE on a specific temporal table."

--------------------------------------------------------------------------------
\echo "--- TEST 1: UPDATE on stat_for_unit ---"
--------------------------------------------------------------------------------
\echo "Before: Checking stats for 'Statistics Norway' legal unit"
\x
SELECT external_idents, name, stats->'employees' as employees
FROM public.statistical_unit
WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;
\x

\echo "Action: Updating a stat_for_unit record for 'Statistics Norway' legal unit"
UPDATE public.stat_for_unit
SET value_int = 100
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Norway')
AND stat_definition_id = (SELECT id FROM public.stat_definition WHERE code = 'employees');

\echo "Check: Expect one 'collect_changes' task."
SELECT command, state
FROM worker.tasks
WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics'); -- Processes collect_changes, enqueues derive tasks and process derived tasks

\echo "After: check stats for 'Statistics Norway'. Expect employees to be 100."
\x
SELECT external_idents, name, stats->'employees' as employees
FROM public.statistical_unit
WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;
\x

--------------------------------------------------------------------------------
\echo "--- TEST 2: UPDATE on establishment ---"
--------------------------------------------------------------------------------
\echo "Before: Checking name for establishment 'Statistics Norway'"
SELECT name FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'establishment';

\echo "Action: Updating establishment name"
UPDATE public.establishment SET name = 'Statistics Norway Updated' WHERE name = 'Statistics Norway';

\echo "Check: Expect one 'collect_changes' task."
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';
\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After: Checking name for establishment 'Statistics Norway Updated'"
SELECT name FROM public.statistical_unit WHERE name = 'Statistics Norway Updated' AND unit_type = 'establishment';

--------------------------------------------------------------------------------
\echo "--- TEST 3: UPDATE on legal_unit ---"
--------------------------------------------------------------------------------
\echo "Before: Checking name of enterprise for legal_unit 'Statistics Norway'"
SELECT name FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = (SELECT enterprise_id FROM public.legal_unit WHERE name = 'Statistics Norway');

\echo "Action: Updating legal_unit short_name"
UPDATE public.legal_unit SET short_name = 'GIL' WHERE name = 'Statistics Norway';

\echo "Check: Expect one 'collect_changes' task."
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';
\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After: Checking name of enterprise for legal_unit 'Statistics Norway'. Expect 'GIL'."
SELECT name FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = (SELECT enterprise_id FROM public.legal_unit WHERE name = 'Statistics Norway');

--------------------------------------------------------------------------------
\echo "--- TEST 4: UPDATE on location ---"
--------------------------------------------------------------------------------
\echo "Before: Checking physical_address_part1 for 'Statistics Norway'"
SELECT physical_address_part1 FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit';

\echo "Action: Updating location address_part1"
UPDATE public.location SET address_part1 = '123 New Street' WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Norway');

\echo "Check: Expect one 'collect_changes' task."
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';
\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After: Checking physical_address_part1 for 'Statistics Norway'"
SELECT physical_address_part1 FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit';

--------------------------------------------------------------------------------
\echo "--- TEST 5: UPDATE on activity ---"
--------------------------------------------------------------------------------
\echo "Before: Checking primary_activity_category_path for 'Statistics Norway'"
SELECT primary_activity_category_path FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit';

\echo "Action: Updating activity category_id"
UPDATE public.activity
SET category_id = (SELECT id FROM public.activity_category_available WHERE path = 'A.01')
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Norway')
  AND type = 'primary';

\echo "Check: Expect one 'collect_changes' task."
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';
\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After: Checking primary_activity_category_path for 'Statistics Norway'"
SELECT primary_activity_category_path FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit';


--------------------------------------------------------------------------------
\echo "--- TEST 6: UPDATE on contact ---"
--------------------------------------------------------------------------------
\echo "Before: Checking email_address for 'Statistics Norway' (is null as no contact exists yet)"
SELECT valid_from, valid_until, email_address FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit';

\echo "Action: INSERT a new contact and then UPDATE it to test trigger."
-- The demo data does not include contacts, so we insert one to be able to test the UPDATE trigger.
INSERT INTO public.contact (legal_unit_id, email_address, valid_from, valid_to, edit_by_user_id)
SELECT
    lu.id,
    'test@example.com',
    '2026-01-01',
    'infinity',
    (SELECT u.id FROM auth.user u WHERE u.email = 'test.admin@statbus.org')
FROM public.legal_unit lu WHERE lu.name = 'Statistics Norway';

UPDATE public.contact
SET email_address = 'updated.test@example.com'
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Norway');

\echo "Check: Expect one 'collect_changes' task (coalesced from INSERT and UPDATE)."
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After: Checking email_address for 'Statistics Norway' (should be updated)"
SELECT email_address FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit';


--------------------------------------------------------------------------------
\echo "--- TEST 7: UPDATE on enterprise ---"
--------------------------------------------------------------------------------
\echo "Before: Checking name of enterprise for 'Statistics Norway'"
-- Note: the enterprise is implicitly created and named after the first legal unit.
SELECT name FROM public.statistical_unit
WHERE unit_type = 'enterprise'
  AND unit_id = (SELECT enterprise_id FROM public.legal_unit WHERE name = 'Statistics Norway');

\echo "Action: Updating enterprise name directly"
UPDATE public.enterprise
SET short_name = 'SSB'
WHERE id = (SELECT enterprise_id FROM public.legal_unit WHERE name = 'Statistics Norway');

\echo "Check: Expect one 'collect_changes' task."
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After: Checking name of enterprise. Expect 'SSB'."
SELECT name FROM public.statistical_unit
WHERE name = 'SSB' AND unit_type = 'enterprise'
  AND unit_id = (SELECT enterprise_id FROM public.legal_unit WHERE name = 'Statistics Norway');

--------------------------------------------------------------------------------
\echo "--- TEST 8: UPDATE on external_ident ---"
--------------------------------------------------------------------------------
\echo "Before: Checking external_idents for 'Statistics Norway' legal unit"
\x
SELECT external_idents FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit';
\x

\echo "Action: Updating external_ident.ident for 'Statistics Norway' legal unit"
UPDATE public.external_ident
SET ident = '947111110'
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Norway')
  AND type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident');

\echo "Check: Expect one 'collect_changes' task."
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After: check external_idents for 'Statistics Norway'. Expect updated tax_ident."
\x
SELECT external_idents FROM public.statistical_unit WHERE name = 'Statistics Norway' AND unit_type = 'legal_unit';
\x


--------------------------------------------------------------------------------
\echo "--- TEST 9: UPDATE establishment parent (legal_unit_id) ---"
--------------------------------------------------------------------------------
\echo "Before: Checking parent of establishment 'Statistics Norway Updated'"
SELECT lu.name as legal_unit_name
FROM public.statistical_unit su_es
JOIN public.timeline_establishment tes ON su_es.unit_id = tes.unit_id AND su_es.valid_from = tes.valid_from
JOIN public.legal_unit lu ON tes.legal_unit_id = lu.id
WHERE su_es.name = 'Statistics Norway Updated'
  AND su_es.unit_type = 'establishment'
  AND su_es.valid_from <= current_date AND current_date < su_es.valid_until;

\echo "Action: Clear pending tasks, unset primary status, then update establishment's legal_unit_id"
DELETE FROM worker.tasks WHERE state = 'pending';

UPDATE public.establishment
SET primary_for_legal_unit = false
WHERE name = 'Statistics Norway Updated';

UPDATE public.establishment
SET legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Denmark')
WHERE name = 'Statistics Norway Updated';

\echo "Check: Expect one 'collect_changes' task (captures both old and new parent IDs)."
SELECT command, state
FROM worker.tasks
WHERE state = 'pending'
ORDER BY command;

\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After: Checking new parent of establishment 'Statistics Norway Updated'. Expect 'Statistics Denmark'."
SELECT lu.name as legal_unit_name
FROM public.statistical_unit su_es
JOIN public.timeline_establishment tes ON su_es.unit_id = tes.unit_id AND su_es.valid_from = tes.valid_from
JOIN public.legal_unit lu ON tes.legal_unit_id = lu.id
WHERE su_es.name = 'Statistics Norway Updated' AND su_es.unit_type = 'establishment'
  AND su_es.valid_from <= current_date AND current_date < su_es.valid_until;


--------------------------------------------------------------------------------
\echo "--- TEST 10: UPDATE external_ident parent (legal_unit_id) ---"
--------------------------------------------------------------------------------
\echo "Clear pending tasks to isolate test case"
DELETE FROM worker.tasks WHERE state = 'pending';

\echo "Before: Checking external_idents for 'Statistics Ethiopia' and 'Statistics Sweden'"
\x
SELECT name, external_idents FROM public.statistical_unit WHERE name IN ('Statistics Ethiopia', 'Statistics Sweden') AND unit_type = 'legal_unit' ORDER BY name;
\x

\echo "Action (1): Delete stat_ident for 'Statistics Ethiopia'"
DELETE FROM public.external_ident
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Ethiopia')
  AND type_id = (SELECT id FROM public.external_ident_type WHERE code = 'stat_ident')
  AND ident = '18';

\echo "Check: Expect one 'collect_changes' task."
-- The DELETE fires the statement trigger which logs to base_change_log and enqueues collect_changes.
SELECT command, state
FROM worker.tasks
WHERE state = 'pending'
ORDER BY command;

\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After (1): Check 'Statistics Ethiopia'. Expect stat_ident to be gone."
\x
SELECT name, external_idents FROM public.statistical_unit WHERE name = 'Statistics Ethiopia' AND unit_type = 'legal_unit';
\x

\echo "Action (2): Move stat_ident from 'Statistics Sweden' to 'Statistics Ethiopia'"
UPDATE public.external_ident
SET legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Ethiopia')
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'Statistics Sweden')
  AND type_id = (SELECT id FROM public.external_ident_type WHERE code = 'stat_ident')
  AND ident = '15';

\echo "Check: Expect one 'collect_changes' task (captures both old and new parent IDs via UNION ALL)."
-- The UPDATE on legal_unit_id fires the statement trigger which logs both OLD and NEW rows,
-- capturing both the old parent (Sweden) and new parent (Ethiopia) LU IDs.
SELECT command, state
FROM worker.tasks
WHERE state = 'pending'
ORDER BY command;

\echo "Run worker to process tasks..."
CALL worker.process_tasks(p_queue => 'analytics');

\echo "After (2): Checking external_idents for both units. Ethiopia should have stat_ident 15, Sweden should not."
\x
SELECT name, external_idents FROM public.statistical_unit WHERE name IN ('Statistics Ethiopia', 'Statistics Sweden') AND unit_type = 'legal_unit' ORDER BY name;
\x

ROLLBACK;
