\set ECHO none
\set QUIET 1
BEGIN;
\i test/setup.sql
\set ECHO none
\set QUIET 1
\pset format unaligned
\pset tuples_only on
SET client_min_messages = error;
CALL test.set_user_from_email('test.admin@statbus.org');
\o /dev/null
\i samples/norway/getting-started.sql
\o
\set ECHO none
RESET ROLE;
-- STATBUS-591: genuine analysis results, real worker fanout and fan-in.
-- One SQL connection verifies the protocol, not simultaneous connection locks.
CREATE TABLE test.t380_observations (seq integer GENERATED ALWAYS AS IDENTITY, observation text);
GRANT SELECT, INSERT ON test.t380_observations TO admin_user;
GRANT USAGE ON SEQUENCE test.t380_observations_seq_seq TO admin_user;
CREATE PROCEDURE test.t380_to_processing(p_slug text)
LANGUAGE plpgsql AS $t380_to_processing$
DECLARE
    v_state public.import_job_state;
    v_before jsonb;
    v_after jsonb;
BEGIN
    LOOP
        SELECT state INTO STRICT v_state FROM public.import_job WHERE slug = p_slug;
        EXIT WHEN v_state = 'processing_data';
        IF v_state IN ('finished', 'failed', 'waiting_for_review') THEN
            RAISE EXCEPTION 'Job % reached % before processing_data', p_slug, v_state;
        END IF;
        SELECT jsonb_agg(jsonb_build_array(id, state) ORDER BY id) INTO v_before FROM worker.tasks;
        CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
        SELECT jsonb_agg(jsonb_build_array(id, state) ORDER BY id) INTO v_after FROM worker.tasks;
        IF v_after IS NOT DISTINCT FROM v_before THEN
            RAISE EXCEPTION 'Job % made no progress', p_slug;
        END IF;
    END LOOP;
END;
$t380_to_processing$;
CREATE PROCEDURE test.t380_dispatch(p_slug text)
LANGUAGE plpgsql AS $t380_dispatch$
DECLARE
    v_job public.import_job;
    v_analysis text;
    v_groups integer;
    v_batches integer;
    v_whole boolean;
    v_fanout text;
    v_fanin text;
BEGIN
    CALL test.t380_to_processing(p_slug);
    SELECT * INTO STRICT v_job FROM public.import_job WHERE slug = p_slug;
    EXECUTE format($SQL$
        SELECT string_agg(operation::text || ':' || n, ',' ORDER BY operation::text)
        FROM (SELECT operation, count(*) AS n FROM public.%1$I GROUP BY operation) AS operations
    $SQL$, v_job.data_table_name) INTO v_analysis;
    EXECUTE format($SQL$
        SELECT count(DISTINCT founding_row_id), count(DISTINCT batch_seq),
            (SELECT bool_and(batches = 1) FROM
                (SELECT count(DISTINCT batch_seq) AS batches FROM public.%1$I
                 GROUP BY founding_row_id) AS groups)
        FROM public.%1$I
    $SQL$, v_job.data_table_name) INTO v_groups, v_batches, v_whole;
    INSERT INTO test.t380_observations(observation)
    VALUES (format('%s analysis: %s groups=%s batches=%s whole=%s',
                   p_slug, v_analysis, v_groups, v_batches, v_whole));
    CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
    SELECT concat_ws('|', d.state, d.child_mode,
        (SELECT count(*) FROM worker.tasks WHERE parent_id = d.id AND command = 'import_job_process_batch'),
        j.state, j.imported_rows)
    INTO STRICT v_fanout
    FROM worker.tasks AS d JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
    WHERE j.slug = p_slug AND d.child_mode = 'concurrent';
    INSERT INTO test.t380_observations(observation) VALUES (p_slug || ' fanout: ' || v_fanout);
    CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'concurrent');
    CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
    SELECT concat_ws('|', j.state, j.imported_rows, d.state,
        (SELECT count(*) FROM worker.tasks WHERE parent_id = d.parent_id AND command = 'import_job_process' AND state = 'pending'))
    INTO STRICT v_fanin
    FROM worker.tasks AS d JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
    WHERE j.slug = p_slug AND d.child_mode = 'concurrent';
    INSERT INTO test.t380_observations(observation) VALUES (p_slug || ' barrier: ' || v_fanin);
    CALL worker.process_tasks(p_queue => 'import', p_mode => 'concurrent');
    SELECT concat_ws('|', j.state, j.imported_rows, d.state) INTO STRICT v_fanin
    FROM worker.tasks AS d JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
    WHERE j.slug = p_slug AND d.child_mode = 'concurrent';
    INSERT INTO test.t380_observations(observation) VALUES (p_slug || ' fanin: ' || v_fanin);
    CALL worker.process_tasks(p_queue => 'import', p_mode => 'serial');
END;
$t380_dispatch$;
CALL test.set_user_from_email('test.admin@statbus.org');
-- Seed existing parents and children through ordinary import analysis and processing.
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_seed_lu', 'T380 seed LU', 'T380', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_380_seed_lu_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT '2020-01-01', 'infinity', (380000000 + n)::text, 'T380 LU ' || n || ' 2020', '2100', 'AS', 'brreg'
FROM generate_series(1, 2) AS n;
CALL worker.process_tasks(p_queue => 'import');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_seed_es', 'T380 seed ES', 'T380', false, 1
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
INSERT INTO public.import_380_seed_es_upload (valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, data_source_code)
SELECT '2020-01-01', 'infinity', (380100000 + n)::text, (380000000 + n)::text, 'T380 ES ' || n || ' 2020', 'brreg'
FROM generate_series(1, 2) AS n;
CALL worker.process_tasks(p_queue => 'import');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_seed_informal', 'T380 seed informal', 'T380', false, 1
FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
INSERT INTO public.import_380_seed_informal_upload (valid_from, valid_to, tax_ident, name, data_source_code)
SELECT '2020-01-01', 'infinity', (380200000 + n)::text, 'T380 informal ' || n || ' 2020', 'brreg'
FROM generate_series(1, 2) AS n;
CALL worker.process_tasks(p_queue => 'import');
-- Existing LUs already have formal children: shortening their histories must preserve coverage.
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_lu', 'T380 mixed LU histories', 'T380', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_380_lu_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT y || '-01-01', CASE WHEN y = 2022 THEN 'infinity' ELSE y || '-12-31' END,
       (380000000 + n)::text, 'T380 LU ' || n || ' ' || y, '2100', 'AS', 'brreg'
FROM generate_series(2021, 2022) AS y CROSS JOIN generate_series(1, 4) AS n ORDER BY y, n;
CALL test.t380_dispatch('import_380_lu');
\echo LU exact histories: existing retain 2020, all four retain 2021 and 2022
SELECT name, valid_from, valid_until FROM public.legal_unit WHERE name LIKE 'T380 LU %' ORDER BY name;
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_es', 'T380 mixed formal histories', 'T380', false, 1
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
-- Each parent gets an existing or new history plus a new sibling, interleaved by year.
INSERT INTO public.import_380_es_upload (valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, data_source_code)
SELECT y || '-01-01', CASE WHEN y = 2022 THEN 'infinity' ELSE y || '-12-31' END,
       (380100000 + n)::text, (380000000 + ((n - 1) % 4) + 1)::text,
       'T380 ES ' || n || ' ' || y, 'brreg'
FROM generate_series(2021, 2022) AS y CROSS JOIN generate_series(1, 8) AS n ORDER BY y, n;
CALL test.t380_dispatch('import_380_es');
\echo Formal parent batches: all child histories and siblings stay with their legal parent
SELECT count(*) FROM
    (SELECT legal_unit_id FROM public.import_380_es_data GROUP BY legal_unit_id HAVING count(DISTINCT batch_seq) = 1 AND count(*) = 4) AS parents;
\echo Formal exact histories
SELECT name, valid_from, valid_until FROM public.establishment WHERE name LIKE 'T380 ES %' ORDER BY name;
\echo Formal primary and temporal parent coverage at each version start
SELECT point, count(DISTINCT es.id), count(DISTINCT lu.id), count(*) FILTER (WHERE es.primary_for_legal_unit),
       count(*) FILTER (WHERE lu.valid_from <= es.valid_from AND es.valid_until <= lu.valid_until)
FROM (VALUES ('2020-01-01'::date), ('2021-01-01'::date), ('2022-01-01'::date)) AS dates(point)
JOIN public.establishment AS es ON es.valid_from <= point AND point < es.valid_until
JOIN public.legal_unit AS lu ON lu.id = es.legal_unit_id AND lu.valid_from <= point AND point < lu.valid_until
WHERE es.name LIKE 'T380 ES %' GROUP BY point ORDER BY point;
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_informal', 'T380 mixed informal histories', 'T380', false, 1
FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
INSERT INTO public.import_380_informal_upload (valid_from, valid_to, tax_ident, name, data_source_code)
SELECT y || '-01-01', CASE WHEN y = 2022 THEN 'infinity' ELSE y || '-12-31' END,
       (380200000 + n)::text, 'T380 informal ' || n || ' ' || y, 'brreg'
FROM generate_series(2021, 2022) AS y CROSS JOIN generate_series(1, 4) AS n ORDER BY y, n;
CALL test.t380_dispatch('import_380_informal');
\echo Informal exact histories
SELECT name, valid_from, valid_until FROM public.establishment WHERE name LIKE 'T380 informal %' ORDER BY name;
\echo Informal independent enterprise parents and primary histories
SELECT count(DISTINCT id), count(*), count(DISTINCT enterprise_id), count(*) FILTER (WHERE primary_for_enterprise)
FROM public.establishment WHERE name LIKE 'T380 informal %';
-- Establish valid multi-unit enterprises in domain state before analysis. Import
-- operations and resolved parent IDs are produced only by the normal analyser.
UPDATE public.legal_unit SET enterprise_id =
    (SELECT enterprise_id FROM public.legal_unit WHERE name = 'T380 LU 1 2022'),
    primary_for_enterprise = false
WHERE name LIKE 'T380 LU 2 %';
UPDATE public.establishment SET enterprise_id =
    (SELECT enterprise_id FROM public.establishment WHERE name = 'T380 informal 1 2022'),
    primary_for_enterprise = false
WHERE name LIKE 'T380 informal 2 %';
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_shared_lu', 'T380 shared LU enterprise', 'T380', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_380_shared_lu_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT '2023-01-01', 'infinity', (380000000 + n)::text, 'T380 shared LU ' || n, '2100', 'AS', 'brreg'
FROM generate_series(1, 3) AS n;
CALL test.t380_to_processing('import_380_shared_lu');
\echo Shared LU analysis: three existing units, two enterprise dependencies, two whole-parent batches
SELECT count(DISTINCT legal_unit_id), count(DISTINCT enterprise_id), count(DISTINCT batch_seq),
       (SELECT count(*) FROM (SELECT enterprise_id FROM public.import_380_shared_lu_data
         GROUP BY enterprise_id HAVING count(DISTINCT batch_seq) = 1) AS parents)
FROM public.import_380_shared_lu_data;
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo Shared LU fanout: two complete enterprise leaves
SELECT d.state, d.child_mode,
       (SELECT count(*) FROM worker.tasks WHERE parent_id = d.id AND command = 'import_job_process_batch')
FROM worker.tasks AS d JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
WHERE j.slug = 'import_380_shared_lu' AND d.child_mode = 'concurrent';
CALL worker.process_tasks(p_queue => 'import', p_mode => 'concurrent');
CALL worker.process_tasks(p_queue => 'import', p_mode => 'serial');
\echo Shared LU final: three exact versions, two enterprise parents, two primary units
SELECT count(DISTINCT id), count(*), count(DISTINCT enterprise_id), count(*) FILTER (WHERE primary_for_enterprise),
       count(*) FILTER (WHERE valid_from = '2023-01-01' AND valid_until = 'infinity')
FROM public.legal_unit WHERE name LIKE 'T380 shared LU %';
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_shared_informal', 'T380 shared informal enterprise', 'T380', false, 1
FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
INSERT INTO public.import_380_shared_informal_upload (valid_from, valid_to, tax_ident, name, data_source_code)
SELECT '2023-01-01', 'infinity', (380200000 + n)::text, 'T380 shared informal ' || n, 'brreg'
FROM generate_series(1, 3) AS n;
CALL test.t380_to_processing('import_380_shared_informal');
\echo Shared informal analysis: three existing units, two enterprise dependencies, two whole-parent batches
SELECT count(DISTINCT establishment_id), count(DISTINCT enterprise_id), count(DISTINCT batch_seq),
       (SELECT count(*) FROM (SELECT enterprise_id FROM public.import_380_shared_informal_data
         GROUP BY enterprise_id HAVING count(DISTINCT batch_seq) = 1) AS parents)
FROM public.import_380_shared_informal_data;
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo Shared informal fanout: two complete enterprise leaves
SELECT d.state, d.child_mode,
       (SELECT count(*) FROM worker.tasks WHERE parent_id = d.id AND command = 'import_job_process_batch')
FROM worker.tasks AS d JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
WHERE j.slug = 'import_380_shared_informal' AND d.child_mode = 'concurrent';
CALL worker.process_tasks(p_queue => 'import', p_mode => 'concurrent');
CALL worker.process_tasks(p_queue => 'import', p_mode => 'serial');
\echo Shared informal final: three exact versions, two enterprise parents, two primary units
SELECT count(DISTINCT id), count(*), count(DISTINCT enterprise_id), count(*) FILTER (WHERE primary_for_enterprise),
       count(*) FILTER (WHERE valid_from = '2023-01-01' AND valid_until = 'infinity')
FROM public.establishment WHERE name LIKE 'T380 shared informal %';
\echo Retained formal children remain covered by complete legal-parent histories
WITH parent_histories AS (
    SELECT id, range_agg(valid_range) AS coverage FROM public.legal_unit GROUP BY id
)
SELECT count(DISTINCT es.id), count(*), count(*) FILTER (WHERE ph.coverage @> es.valid_range)
FROM public.establishment AS es JOIN parent_histories AS ph ON ph.id = es.legal_unit_id
WHERE es.name LIKE 'T380 ES %';
\echo Current shared-enterprise groups each retain one primary unit
SELECT 'legal_unit', count(*) FROM (
    SELECT enterprise_id FROM public.legal_unit
    WHERE name LIKE 'T380 %' AND valid_from <= '2023-01-01' AND '2023-01-01' < valid_until
    GROUP BY enterprise_id HAVING count(*) FILTER (WHERE primary_for_enterprise) = 1
) AS parents
UNION ALL
SELECT 'informal', count(*) FROM (
    SELECT enterprise_id FROM public.establishment
    WHERE (name LIKE 'T380 informal %' OR name LIKE 'T380 shared informal %')
      AND valid_from <= '2023-01-01' AND '2023-01-01' < valid_until
    GROUP BY enterprise_id HAVING count(*) FILTER (WHERE primary_for_enterprise) = 1
) AS parents;
\echo Custom handler retains serial processing and runs once per complete batch
RESET ROLE;
CREATE TABLE test.t380_custom_batches (batch_seq integer PRIMARY KEY);
GRANT SELECT, INSERT ON test.t380_custom_batches TO admin_user;
CREATE PROCEDURE test.t380_custom(p_job_id integer, p_batch_seq integer, p_step_code text)
LANGUAGE plpgsql AS $t380_custom$
BEGIN
    INSERT INTO test.t380_custom_batches VALUES (p_batch_seq);
END;
$t380_custom$;
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_380_custom', 'T380 custom handler', 'T380', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_380_custom_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT '2020-01-01', 'infinity', (380300000 + n)::text, 'T380 custom ' || n, '2100', 'AS', 'brreg'
FROM generate_series(1, 2) AS n;
CALL test.t380_to_processing('import_380_custom');
UPDATE public.import_job SET definition_snapshot = jsonb_set(
    definition_snapshot, '{import_step_list}',
    (definition_snapshot->'import_step_list') || jsonb_build_array(jsonb_build_object(
        'code', 't380_custom', 'name', 'Custom batch handler', 'priority', 100000,
        'is_holistic', false, 'process_procedure', 'test.t380_custom')))
WHERE slug = 'import_380_custom';
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
SELECT w.child_mode, j.state, j.imported_rows,
       (SELECT count(*) FROM public.import_380_custom_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.import_380_custom_data WHERE state = 'processing'),
       (SELECT count(*) FROM test.t380_custom_batches)
FROM public.import_job AS j JOIN worker.tasks AS w
  ON (w.payload->>'job_id')::integer = j.id AND w.command = 'import_job'
WHERE j.slug = 'import_380_custom';
CALL worker.process_tasks(p_queue => 'import');
SELECT j.state, j.total_rows, j.imported_rows,
       (SELECT count(*) FROM test.t380_custom_batches),
       (SELECT count(DISTINCT id) FROM public.legal_unit WHERE name LIKE 'T380 custom %')
FROM public.import_job AS j WHERE slug = 'import_380_custom';
\echo Finished jobs preserve exact input and imported counts
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug LIKE 'import_380_%' ORDER BY slug;
\echo Real worker protocol observations
SELECT observation FROM test.t380_observations ORDER BY seq;
ROLLBACK;
