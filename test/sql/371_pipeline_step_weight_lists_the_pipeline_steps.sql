-- The navbar progress bar weighs each pipeline step by worker.pipeline_step_weight
-- (app/src/components/navbar.tsx computeWeightedPhaseProgress). A step the pipeline runs
-- without a weight row makes the bar fall to 0% while it runs, and a row for a step the
-- pipeline never runs is weight the bar can never earn. So, per phase, the weight rows in
-- seq order are exactly the steps worker.command_collect_changes spawns, in spawn order:
-- collect_changes itself (the pipeline root, shown as phase 1's first step) and then the
-- children of derive_units_phase; for phase 2 the children of derive_reports_phase.
--
-- Fixture: one legal unit imported and derived, which runs one full pipeline.

BEGIN;

\i test/setup.sql

\echo "Test 371: pipeline_step_weight lists exactly the steps the pipeline runs"

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/demo/getting-started.sql
\o
\set ECHO all

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_371', 'Test 371 one legal unit', 'Test 371', false
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_371_upload(valid_from, valid_to, tax_ident, name, employees) VALUES
    ('2020-01-01', 'infinity', '371000001', 'Progress steps AS', '10');

CALL worker.process_tasks(p_queue => 'import');
CALL worker.process_tasks(p_queue => 'analytics');

\echo
\echo "371.1 steps of the last pipeline per phase, in spawn order, beside the weighted steps in seq order"
WITH pipeline AS (
    SELECT max(id) AS id FROM worker.tasks WHERE command = 'collect_changes' AND state = 'completed'
), ran AS (
    SELECT 'is_deriving_statistical_units' AS phase, ARRAY['collect_changes'] || array_agg(c.command ORDER BY c.id) AS steps
    FROM pipeline JOIN worker.tasks AS p ON p.parent_id = pipeline.id AND p.command = 'derive_units_phase'
    JOIN worker.tasks AS c ON c.parent_id = p.id
    UNION ALL
    SELECT 'is_deriving_reports', array_agg(c.command ORDER BY c.id)
    FROM pipeline JOIN worker.tasks AS p ON p.parent_id = pipeline.id AND p.command = 'derive_reports_phase'
    JOIN worker.tasks AS c ON c.parent_id = p.id
), weighted AS (
    SELECT phase, array_agg(step ORDER BY seq, step) AS steps
    FROM public.pipeline_step_weight GROUP BY phase
)
SELECT ran.phase, ran.steps AS ran_steps, weighted.steps AS weighted_steps,
       ran.steps = weighted.steps AS weights_match_steps
FROM ran FULL JOIN weighted USING (phase)
ORDER BY ran.phase;

\echo
\echo "371.2 every weighted step has a positive weight"
SELECT count(*) AS steps, bool_and(weight > 0) AS all_positive FROM public.pipeline_step_weight;

ROLLBACK;
