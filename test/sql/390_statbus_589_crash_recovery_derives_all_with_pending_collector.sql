\echo "=== STATBUS-589: crash recovery with a lost change log derives every unit ==="
\echo "After a crash PostgreSQL truncates the UNLOGGED worker.base_change_log while the"
\echo "durable worker.base_change_log_has_pending flag stays TRUE. The changes that were"
\echo "waiting are unknown, so recovery must derive every unit, also when an ordinary"
\echo "collect_changes task is already pending (it would read the empty log)."

BEGIN;

\i test/setup.sql

LOCK TABLE worker.tasks IN EXCLUSIVE MODE;

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment, time_context_ident)
SELECT (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
       'import_390_lu', 'STATBUS-589 legal units', 'Demo legal units', 'STATBUS-589', 'r_year_curr';
\copy public.import_390_lu_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

CALL worker.process_tasks(p_queue => 'import');

\echo "--- Imported units, nothing derived yet ---"
SELECT (SELECT count(*) FROM public.legal_unit) AS legal_units,
       (SELECT count(*) FROM public.statistical_unit) AS statistical_units;

-- The state a crash leaves: the change log is empty (UNLOGGED, truncated),
-- has_pending is TRUE, and the import's ordinary collector is still pending.
DELETE FROM worker.base_change_log;
UPDATE worker.base_change_log_has_pending SET has_pending = TRUE;

\echo "--- Crash state: one ordinary collect_changes pending ---"
SELECT state, payload FROM worker.tasks WHERE command = 'collect_changes' AND state IN ('pending', 'interrupted');

SELECT worker.reset_abandoned_processing_tasks() AS reset_count;

\echo "--- After recovery: the pending collector derives everything ---"
SELECT state, payload->'valid_ranges' AS valid_ranges, payload ? 'legal_unit_id_ranges' AS names_unit_ranges
FROM worker.tasks WHERE command = 'collect_changes' AND state = 'pending';
SELECT has_pending FROM worker.base_change_log_has_pending;

CALL worker.process_tasks(p_queue => 'analytics');

\echo "--- Every legal unit and its enterprise is derived ---"
SELECT unit_type, count(*) FROM public.statistical_unit GROUP BY unit_type ORDER BY unit_type;
SELECT (SELECT count(*) FROM public.statistical_unit WHERE unit_type = 'legal_unit')
     = (SELECT count(*) FROM public.legal_unit) AS every_legal_unit_derived;

ROLLBACK;
