BEGIN;

\i test/setup.sql

-- This test verifies directional change propagation:
-- 1. Full/unqualified refresh: no changed_* keys, all units processed
-- 2. Upward propagation scoping via changed_* keys in batch payloads:
--    ES change -> ES + parent LU + grandparent EN
--    LU change -> LU + parent EN (skip ES)
--    EN change -> EN only (skip LU + ES)
-- 3. Associated table changes (stat_for_unit, activity, location) propagate correctly
-- 4. Data correctness after each propagation

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

\i samples/demo/getting-started.sql

-- Create Import Job for Legal Units (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_44_lu',
    'Import LU Demo CSV (344_directional_change_propagation.sql)',
    'Import job for legal_units_demo.csv',
    'Test data load (344)',
    'r_year_curr';
\echo "User uploads the sample legal units"
\copy public.import_44_lu_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Formal Establishments (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_job_provided'),
    'import_44_esflu',
    'Import Formal ES Demo CSV (344_directional_change_propagation.sql)',
    'Import job for formal_establishments_units_demo.csv',
    'Test data load (344)',
    'r_year_curr';
\echo "User uploads the sample formal establishments"
\copy public.import_44_esflu_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'app/public/demo/formal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Informal Establishments (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_job_provided'),
    'import_44_eswlu',
    'Import Informal ES Demo CSV (344_directional_change_propagation.sql)',
    'Import job for informal_establishments_units_demo.csv',
    'Test data load (344)',
    'r_year_curr';
\echo "User uploads the sample informal establishments"
\copy public.import_44_eswlu_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'app/public/demo/informal_establishments_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- Create Import Job for Legal Relationships (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_relationship_job_provided'),
    'import_44_lr',
    'Import LR Demo CSV (344_directional_change_propagation.sql)',
    'Import job for legal_relationships_demo.csv',
    'Test data load (344)',
    'r_year_curr';
\echo "User uploads the sample legal relationships"
\copy public.import_44_lr_upload(influencing_tax_ident,influenced_tax_ident,rel_type_code,percentage) FROM 'app/public/demo/legal_relationships_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo Run worker processing for import jobs
CALL worker.process_tasks(p_queue => 'import');
\echo Run worker processing for analytics tasks (initial full refresh)
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Baseline: statistical_unit counts by unit_type"
SELECT unit_type, count(*) AS count
FROM public.statistical_unit
GROUP BY unit_type
ORDER BY unit_type;

--------------------------------------------------------------------------------
\echo "--- TEST 0: Full/unqualified refresh has NO changed_* keys (all units processed) ---"
--------------------------------------------------------------------------------
\echo "Initial full refresh ES/LU/EN batch should have no changed_* keys"
SELECT
    payload->>'changed_establishment_id_ranges' AS changed_est,
    payload->>'changed_legal_unit_id_ranges' AS changed_lu,
    payload->>'changed_enterprise_id_ranges' AS changed_en
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
  AND payload ? 'enterprise_ids'
ORDER BY id LIMIT 1;

\echo "Initial full refresh PG batch should have power_group_ids, no changed_* keys"
SELECT
    payload ? 'power_group_ids' AS has_pg_ids,
    payload ? 'enterprise_ids' AS has_ent_ids,
    payload->>'changed_establishment_id_ranges' AS changed_est
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
  AND payload ? 'power_group_ids' AND NOT (payload ? 'enterprise_ids')
ORDER BY id LIMIT 1;

\echo "Clear completed tasks for clean slate"
DELETE FROM worker.tasks WHERE state = 'completed';

--------------------------------------------------------------------------------
\echo "--- TEST A: LU-only change (should propagate to LU + EN, skip ES) ---"
--------------------------------------------------------------------------------
\echo "Action: Updating legal_unit name"
UPDATE public.legal_unit SET name = 'SSB Updated' WHERE name = 'Statistics Norway';

\echo "Check: Expect one collect_changes task"
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: changed_est should be empty, changed_lu and changed_en should have ranges"
SELECT
    payload->>'changed_establishment_id_ranges' AS changed_est,
    CASE WHEN (payload->>'changed_legal_unit_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_lu,
    CASE WHEN (payload->>'changed_enterprise_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_en
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
ORDER BY id DESC LIMIT 1;

\echo "Verify: name updated in statistical_unit for LU"
SELECT name FROM public.statistical_unit
WHERE name = 'SSB Updated' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;

\echo "Verify: enterprise name also updated (upward propagation)"
SELECT name FROM public.statistical_unit
WHERE unit_type = 'enterprise'
  AND unit_id = (SELECT enterprise_id FROM public.legal_unit WHERE name = 'SSB Updated')
AND valid_from <= current_date AND current_date < valid_until;

\echo "Clean up for next test"
DELETE FROM worker.tasks WHERE state = 'completed';

--------------------------------------------------------------------------------
\echo "--- TEST B: ES-only change (should propagate to ES + parent LU) ---"
--------------------------------------------------------------------------------
\echo "Action: Updating an establishment name (formal ES linked to a LU)"
UPDATE public.establishment SET name = 'ES Changed By Test'
WHERE id = (
    SELECT e.id FROM public.establishment AS e
    WHERE e.legal_unit_id IS NOT NULL
    ORDER BY e.id LIMIT 1
);

\echo "Check: Expect one collect_changes task"
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: changed_est and changed_lu should have ranges (ES propagates to parent LU via collect_changes)"
SELECT
    CASE WHEN (payload->>'changed_establishment_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_est,
    CASE WHEN (payload->>'changed_legal_unit_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_lu,
    CASE WHEN (payload->>'changed_enterprise_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_en
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
ORDER BY id DESC LIMIT 1;

\echo "Verify: establishment name updated in statistical_unit"
SELECT count(*) AS found FROM public.statistical_unit
WHERE name = 'ES Changed By Test' AND unit_type = 'establishment';

\echo "Clean up for next test"
DELETE FROM worker.tasks WHERE state = 'completed';

--------------------------------------------------------------------------------
\echo "--- TEST C: EN-only change (should propagate to EN only, skip LU + ES) ---"
--------------------------------------------------------------------------------
\echo "Action: Updating enterprise short_name"
UPDATE public.enterprise SET short_name = 'SSB-EN'
WHERE id = (SELECT enterprise_id FROM public.legal_unit WHERE name = 'SSB Updated');

\echo "Check: Expect one collect_changes task"
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: only changed_enterprise_id_ranges should have ranges (EN only, skip LU + ES)"
SELECT
    payload->>'changed_establishment_id_ranges' AS changed_est,
    payload->>'changed_legal_unit_id_ranges' AS changed_lu,
    CASE WHEN (payload->>'changed_enterprise_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_en
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
ORDER BY id DESC LIMIT 1;

\echo "Verify: enterprise short_name updated in statistical_unit"
SELECT name FROM public.statistical_unit
WHERE name = 'SSB-EN' AND unit_type = 'enterprise'
AND valid_from <= current_date AND current_date < valid_until;

\echo "Clean up for next test"
DELETE FROM worker.tasks WHERE state = 'completed';

--------------------------------------------------------------------------------
\echo "--- TEST D: stat_for_unit change (LU-associated, propagates like LU change) ---"
--------------------------------------------------------------------------------
\echo "Before: employees for SSB Updated"
SELECT stats->'employees' AS employees FROM public.statistical_unit
WHERE name = 'SSB Updated' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;

\echo "Action: Updating stat_for_unit (employees) for SSB Updated"
UPDATE public.stat_for_unit SET value_int = 999
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'SSB Updated')
  AND stat_definition_id = (SELECT id FROM public.stat_definition WHERE code = 'employees');

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: should have changed_lu ranges (stat_for_unit is LU-associated)"
SELECT
    payload->>'changed_establishment_id_ranges' AS changed_est,
    CASE WHEN (payload->>'changed_legal_unit_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_lu,
    CASE WHEN (payload->>'changed_enterprise_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_en
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
ORDER BY id DESC LIMIT 1;

\echo "After: employees for SSB Updated (should be 999)"
SELECT stats->'employees' AS employees FROM public.statistical_unit
WHERE name = 'SSB Updated' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;

\echo "Clean up for next test"
DELETE FROM worker.tasks WHERE state = 'completed';

--------------------------------------------------------------------------------
\echo "--- TEST E: activity change (LU-associated, propagates like LU change) ---"
--------------------------------------------------------------------------------
\echo "Before: primary_activity_category_path for SSB Updated"
SELECT primary_activity_category_path FROM public.statistical_unit
WHERE name = 'SSB Updated' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;

\echo "Action: Updating activity category for SSB Updated"
UPDATE public.activity
SET category_id = (SELECT id FROM public.activity_category_available WHERE path = 'A.01')
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'SSB Updated')
  AND type = 'primary';

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: should have changed_lu ranges (activity is LU-associated)"
SELECT
    payload->>'changed_establishment_id_ranges' AS changed_est,
    CASE WHEN (payload->>'changed_legal_unit_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_lu,
    CASE WHEN (payload->>'changed_enterprise_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_en
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
ORDER BY id DESC LIMIT 1;

\echo "After: primary_activity_category_path for SSB Updated (should be A.01)"
SELECT primary_activity_category_path FROM public.statistical_unit
WHERE name = 'SSB Updated' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;

\echo "Clean up for next test"
DELETE FROM worker.tasks WHERE state = 'completed';

--------------------------------------------------------------------------------
\echo "--- TEST F: location change (LU-associated, propagates like LU change) ---"
--------------------------------------------------------------------------------
\echo "Before: physical_address_part1 for SSB Updated"
SELECT physical_address_part1 FROM public.statistical_unit
WHERE name = 'SSB Updated' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;

\echo "Action: Updating location address for SSB Updated"
UPDATE public.location SET address_part1 = '42 Test Street'
WHERE legal_unit_id = (SELECT id FROM public.legal_unit WHERE name = 'SSB Updated');

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: should have changed_lu ranges (location is LU-associated)"
SELECT
    payload->>'changed_establishment_id_ranges' AS changed_est,
    CASE WHEN (payload->>'changed_legal_unit_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_lu,
    CASE WHEN (payload->>'changed_enterprise_id_ranges')::int4multirange <> '{}'::int4multirange THEN 'has_ranges' END AS changed_en
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
ORDER BY id DESC LIMIT 1;

\echo "After: physical_address_part1 for SSB Updated (should be 42 Test Street)"
SELECT physical_address_part1 FROM public.statistical_unit
WHERE name = 'SSB Updated' AND unit_type = 'legal_unit'
AND valid_from <= current_date AND current_date < valid_until;

--------------------------------------------------------------------------------
\echo "--- TEST G: LR change (should spawn PG-only batch with power_group_ids) ---"
--------------------------------------------------------------------------------
\echo "Baseline: power_group and legal_relationship counts"
SELECT count(*) AS power_group_count FROM public.power_group;
SELECT count(*) AS lr_count FROM public.legal_relationship;

\echo "Action: Updating a legal_relationship percentage"
UPDATE public.legal_relationship SET percentage = 99
WHERE id = (SELECT id FROM public.legal_relationship ORDER BY id LIMIT 1);

\echo "Check: Expect one collect_changes task"
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: PG batch should have power_group_ids but no enterprise_ids"
SELECT
    payload ? 'power_group_ids' AS has_pg_ids,
    payload ? 'enterprise_ids' AS has_ent_ids
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
  AND payload ? 'power_group_ids' AND NOT (payload ? 'enterprise_ids')
ORDER BY id DESC LIMIT 1;

\echo "Clean up for next test"
DELETE FROM worker.tasks WHERE state = 'completed';

--------------------------------------------------------------------------------
\echo "--- TEST H: PG metadata change (should spawn PG-only batch) ---"
--------------------------------------------------------------------------------
\echo "Action: Updating power_group short_name"
UPDATE public.power_group SET short_name = 'PG-TEST'
WHERE id = (SELECT id FROM public.power_group ORDER BY id LIMIT 1);

\echo "Check: Expect one collect_changes task"
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: PG batch should have power_group_ids but no enterprise_ids"
SELECT
    payload ? 'power_group_ids' AS has_pg_ids,
    payload ? 'enterprise_ids' AS has_ent_ids
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
  AND payload ? 'power_group_ids' AND NOT (payload ? 'enterprise_ids')
ORDER BY id DESC LIMIT 1;

\echo "Clean up for next test"
DELETE FROM worker.tasks WHERE state = 'completed';

--------------------------------------------------------------------------------
\echo "--- TEST I: PR change (custom_root override, should spawn PG-only batch) ---"
--------------------------------------------------------------------------------
\echo "Check: power_root rows exist (cycle/multi PGs from LR import)"
SELECT count(*) AS pr_count FROM public.power_root;

\echo "Action: Setting custom_root on a power_root row (NSO override)"
UPDATE public.power_root
SET custom_root_legal_unit_id = derived_root_legal_unit_id
WHERE id = (SELECT id FROM public.power_root ORDER BY id LIMIT 1);

\echo "Check: Expect one collect_changes task (if PR rows exist)"
SELECT command, state FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';

\echo "Run analytics worker"
CALL worker.process_tasks(p_queue => 'analytics');

\echo "Task payload: PG batch should have power_group_ids but no enterprise_ids"
SELECT
    payload ? 'power_group_ids' AS has_pg_ids,
    payload ? 'enterprise_ids' AS has_ent_ids
FROM worker.tasks
WHERE command = 'statistical_unit_refresh_batch'
  AND state = 'completed'
  AND payload ? 'power_group_ids' AND NOT (payload ? 'enterprise_ids')
ORDER BY id DESC LIMIT 1;

\echo "Clean up for next test"
DELETE FROM worker.tasks WHERE state = 'completed';

ROLLBACK;
