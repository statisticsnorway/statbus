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

-- STATBUS-591: exercise the worker's public serial/concurrent scheduling boundary.
-- This transaction deliberately uses one connection. It proves fan-out, fan-in,
-- counters, replay and failure semantics, not cross-connection lock behaviour.
-- Exact step counts and implementation helper names are not part of this contract.
RESET ROLE;
CREATE TABLE test.t375_holistic (slug text PRIMARY KEY, processed_rows integer, imported_rows integer);
GRANT SELECT, INSERT ON test.t375_holistic TO admin_user;

CREATE PROCEDURE test.t375_to_processing(p_slug text)
LANGUAGE plpgsql AS $t375_to_processing$
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
            RAISE EXCEPTION 'Job % made no serial progress in state %', p_slug, v_state;
        END IF;
    END LOOP;
END;
$t375_to_processing$;

-- A real holistic process step witnesses the complete imported dataset before
-- finalization. Appending to this job's immutable snapshot isolates the fixture.
CREATE PROCEDURE test.t375_holistic(p_job_id integer, p_batch_seq integer, p_step_code text)
LANGUAGE plpgsql AS $t375_holistic$
DECLARE
    v_job public.import_job;
    v_processed integer;
BEGIN
    SELECT * INTO STRICT v_job FROM public.import_job WHERE id = p_job_id;
    EXECUTE format($$SELECT count(*) FROM public.%1$I WHERE state = 'processed'$$, v_job.data_table_name)
        INTO v_processed;
    IF p_batch_seq IS NOT NULL OR v_job.state <> 'processing_data'
       OR v_processed <> v_job.total_rows OR v_job.imported_rows <> v_job.total_rows
       OR EXISTS (SELECT FROM worker.tasks WHERE command = 'import_job_process_batch'
                  AND (payload->>'job_id')::integer = p_job_id AND state <> 'completed') THEN
        RAISE EXCEPTION 'Holistic step % ran before batch fan-in', p_step_code;
    END IF;
    INSERT INTO test.t375_holistic VALUES (v_job.slug, v_processed, v_job.imported_rows);
END;
$t375_holistic$;

CREATE PROCEDURE test.t375_add_holistic(p_slug text)
LANGUAGE plpgsql AS $t375_add_holistic$
BEGIN
    UPDATE public.import_job SET definition_snapshot = jsonb_set(
        definition_snapshot, '{import_step_list}',
        (definition_snapshot->'import_step_list') || jsonb_build_array(jsonb_build_object(
            'code', 't375_holistic', 'name', 'Observe complete batches',
            'priority', 100000, 'is_holistic', true,
            'process_procedure', 'test.t375_holistic')))
    WHERE slug = p_slug;
END;
$t375_add_holistic$;

-- Four genuinely new insert-only units exercise concurrent dispatch. Histories
-- naturally analyse as mixed operations and have a separate serial fixture below.
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_375_lu', 'T375 legal units', 'T375', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_375_lu_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT '2020-01-01', 'infinity',
       (375000000 + n)::text, 'T375 LU ' || n || ' 2020', '2100', 'AS', 'brreg'
FROM generate_series(1, 4) AS n;
CALL test.t375_to_processing('import_375_lu');
CALL test.t375_add_holistic('import_375_lu');
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');

\echo LU fanout: serial wrapper, waiting concurrent dispatcher, one leaf per batch, blocked serial continuation
SELECT w.child_mode, d.state, d.child_mode,
       (SELECT count(*) FROM worker.tasks WHERE parent_id = d.id AND command = 'import_job_process_batch'),
       (SELECT count(DISTINCT batch_seq) FROM public.import_375_lu_data WHERE state = 'processing'),
       (SELECT count(*) FROM worker.tasks WHERE parent_id = w.id AND command = 'import_job_process' AND state = 'pending'),
       j.state, j.imported_rows
FROM worker.tasks AS d JOIN worker.tasks AS w ON w.id = d.parent_id
JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
WHERE j.slug = 'import_375_lu' AND d.child_mode = 'concurrent';
\echo LU batch coverage: exactly one scheduled leaf matches each assigned processing batch
SELECT count(*)
FROM (SELECT DISTINCT batch_seq FROM public.import_375_lu_data WHERE state = 'processing') AS batches
JOIN (
    SELECT (t.payload->>'batch_seq')::integer AS batch_seq, count(*) AS leaves
    FROM worker.tasks AS t JOIN public.import_job AS j ON j.id = (t.payload->>'job_id')::integer
    WHERE j.slug = 'import_375_lu' AND t.command = 'import_job_process_batch'
    GROUP BY (t.payload->>'batch_seq')::integer
) AS scheduled USING (batch_seq)
WHERE scheduled.leaves = 1;

CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'concurrent');
\echo LU first leaf: exactly one unit, counter advanced once, holistic pending
SELECT j.state, j.imported_rows,
       (SELECT count(*) FROM public.import_375_lu_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.import_375_lu_data WHERE state = 'processing'),
       (SELECT count(DISTINCT id) FROM public.legal_unit WHERE name LIKE 'T375 LU %'),
       (SELECT count(*) FROM public.legal_unit WHERE name LIKE 'T375 LU %'),
       (SELECT count(*) FROM test.t375_holistic)
FROM public.import_job AS j WHERE slug = 'import_375_lu';

-- Model a worker recovery replay through the registered task protocol, not an
-- implementation helper. The completed first leaf is selected again before its
-- pending siblings. A processed batch is a successful zero-work replay.
RESET ROLE;
UPDATE worker.tasks SET state = 'interrupted', completed_at = NULL
WHERE command = 'import_job_process_batch' AND state = 'completed'
  AND (payload->>'job_id')::integer = (SELECT id FROM public.import_job WHERE slug = 'import_375_lu');
CALL test.set_user_from_email('test.admin@statbus.org');
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'concurrent');
\echo LU replay: one completed leaf, same imported row and version
SELECT j.imported_rows,
       (SELECT count(*) FROM public.import_375_lu_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.legal_unit WHERE name LIKE 'T375 LU %'),
       (SELECT count(*) FROM worker.tasks WHERE command = 'import_job_process_batch' AND state = 'completed'
        AND (payload->>'job_id')::integer = j.id)
FROM public.import_job AS j WHERE slug = 'import_375_lu';
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo LU serial barrier: continuation stays pending until every leaf completes
SELECT j.imported_rows, d.state,
       (SELECT count(*) FROM worker.tasks WHERE parent_id = w.id AND command = 'import_job_process' AND state = 'pending'),
       (SELECT count(*) FROM test.t375_holistic)
FROM worker.tasks AS d JOIN worker.tasks AS w ON w.id = d.parent_id
JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
WHERE j.slug = 'import_375_lu' AND d.child_mode = 'concurrent';
CALL worker.process_tasks(p_queue => 'import', p_mode => 'concurrent');
\echo LU fan-in: dispatcher completed, all rows imported, finalization still pending
SELECT j.state, j.imported_rows, d.state,
       (SELECT count(*) FROM public.import_375_lu_data WHERE state = 'processed'),
       (SELECT count(*) FROM test.t375_holistic)
FROM worker.tasks AS d JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
WHERE j.slug = 'import_375_lu' AND d.child_mode = 'concurrent';
CALL worker.process_tasks(p_queue => 'import', p_mode => 'serial');
\echo LU final: four units, four exact versions, four enterprises, holistic sees four
SELECT count(DISTINCT id), count(*),
       count(*) FILTER (WHERE valid_from = '2020-01-01' AND valid_until = 'infinity'),
       count(DISTINCT enterprise_id)
FROM public.legal_unit WHERE name LIKE 'T375 LU %';
SELECT slug, processed_rows, imported_rows FROM test.t375_holistic ORDER BY slug;

-- Formal establishments target already-known legal units, but the establishments
-- themselves are new. Two establishments share each legal unit, testing primary
-- establishment side effects within a whole-parent batch.
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_375_es', 'T375 formal establishments', 'T375', false, 1
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
INSERT INTO public.import_375_es_upload (valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, data_source_code)
SELECT '2020-01-01', 'infinity', (375100000 + n)::text,
       (375000000 + ((n - 1) / 2) + 1)::text, 'T375 ES ' || n, 'brreg'
FROM generate_series(1, 8) AS n;
CALL test.t375_to_processing('import_375_es');
CALL test.t375_add_holistic('import_375_es');
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo ES fanout: four parent groups, four leaves, eight new insert rows
SELECT d.state, d.child_mode,
       (SELECT count(*) FROM worker.tasks WHERE parent_id = d.id AND command = 'import_job_process_batch'),
       (SELECT count(DISTINCT batch_seq) FROM public.import_375_es_data),
       (SELECT count(*) FROM public.import_375_es_data WHERE operation = 'insert' AND state = 'processing')
FROM worker.tasks AS d JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
WHERE j.slug = 'import_375_es' AND d.child_mode = 'concurrent';
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'concurrent');
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo ES first leaf: two establishments of one parent, serial continuation blocked
SELECT j.state, j.imported_rows,
       (SELECT count(*) FROM public.import_375_es_data WHERE state = 'processed'),
       (SELECT count(*) FROM test.t375_holistic WHERE slug = j.slug)
FROM public.import_job AS j WHERE slug = 'import_375_es';
CALL worker.process_tasks(p_queue => 'import', p_mode => 'concurrent');
CALL worker.process_tasks(p_queue => 'import', p_mode => 'serial');
\echo ES final: eight units and versions, four parents, exactly one primary per parent
SELECT count(DISTINCT id), count(*), count(DISTINCT legal_unit_id),
       count(*) FILTER (WHERE primary_for_legal_unit)
FROM public.establishment WHERE name LIKE 'T375 ES %';
SELECT count(*) AS parents_with_two_establishments_and_one_primary
FROM (SELECT legal_unit_id FROM public.establishment WHERE name LIKE 'T375 ES %'
      GROUP BY legal_unit_id HAVING count(DISTINCT id) = 2 AND count(*) FILTER (WHERE primary_for_legal_unit) = 1) AS parents;
SELECT slug, processed_rows, imported_rows FROM test.t375_holistic ORDER BY slug;

-- Reusing an establishment target retains serial processing independently of
-- the formal job's otherwise-concurrent mode and its distinct legal-unit groups.
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_375_es_reused', 'T375 reused establishments', 'T375', false, 1
FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates';
INSERT INTO public.import_375_es_reused_upload
    (valid_from, valid_to, tax_ident, legal_unit_tax_ident, name, data_source_code)
SELECT '2020-01-01', 'infinity', (375100000 + 2 * n - 1)::text,
       (375000000 + n)::text, 'T375 ES reused ' || n, 'brreg'
FROM generate_series(1, 4) AS n;
CALL test.t375_to_processing('import_375_es_reused');
\echo Reused ES analysis: four existing establishment targets across four parent batches
SELECT count(DISTINCT establishment_id), count(DISTINCT legal_unit_id), count(DISTINCT batch_seq)
FROM public.import_375_es_reused_data;
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo Reused ES job: serial wrapper imports one row before the remaining three
SELECT w.child_mode, j.state, j.imported_rows,
       (SELECT count(*) FROM public.import_375_es_reused_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.import_375_es_reused_data WHERE state = 'processing')
FROM public.import_job AS j JOIN worker.tasks AS w ON (w.payload->>'job_id')::integer = j.id AND w.command = 'import_job'
WHERE j.slug = 'import_375_es_reused';
CALL worker.process_tasks(p_queue => 'import');
\echo Reused ES final: four existing units have their requested replacement versions
SELECT count(DISTINCT id), count(*) FROM public.establishment WHERE name LIKE 'T375 ES reused %';

-- A clean new history is naturally mixed: its first row inserts and subsequent
-- versions replace. Preserve those analysis results and verify serial fallback.
-- Interleaving histories and size 1 also exercises whole-unit batch assignment.
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_375_history', 'T375 clean new histories', 'T375', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_375_history_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT y || '-01-01', CASE WHEN y = 2022 THEN 'infinity' ELSE y || '-12-31' END,
       (375400000 + n)::text, 'T375 history ' || n || ' ' || y, '2100', 'AS', 'brreg'
FROM generate_series(2020, 2022) AS y CROSS JOIN generate_series(1, 4) AS n ORDER BY y, n;
CALL test.t375_to_processing('import_375_history');
\echo History analysis: four inserts and eight non-inserts in four whole-unit batches
SELECT count(*) FILTER (WHERE operation = 'insert'), count(*) FILTER (WHERE operation <> 'insert'),
       count(DISTINCT founding_row_id), count(DISTINCT batch_seq)
FROM public.import_375_history_data;
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo History job: serial wrapper imports one complete three-row history per invocation
SELECT w.child_mode, j.state, j.imported_rows,
       (SELECT count(*) FROM public.import_375_history_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.import_375_history_data WHERE state = 'processing')
FROM public.import_job AS j JOIN worker.tasks AS w ON (w.payload->>'job_id')::integer = j.id AND w.command = 'import_job'
WHERE j.slug = 'import_375_history';
CALL worker.process_tasks(p_queue => 'import');
\echo History final: four units retain all twelve exact yearly versions
SELECT count(DISTINCT id), count(*),
       count(*) FILTER (WHERE valid_from IN ('2020-01-01', '2021-01-01', '2022-01-01')
                         AND valid_until = CASE extract(year FROM valid_from)::integer
                             WHEN 2020 THEN '2021-01-01'::date WHEN 2021 THEN '2022-01-01'::date ELSE 'infinity'::date END)
FROM public.legal_unit WHERE name LIKE 'T375 history %';

-- A job mixing an update with an insert retains the serial processing contract.
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_375_mixed', 'T375 mixed operations', 'T375', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_375_mixed_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
VALUES ('2022-01-01', 'infinity', '375000001', 'T375 mixed existing', '2100', 'AS', 'brreg'),
       ('2020-01-01', 'infinity', '375000101', 'T375 mixed new', '2100', 'AS', 'brreg');
CALL test.t375_to_processing('import_375_mixed');
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo Mixed job: serial wrapper, one processed row and one pending processing row
SELECT w.child_mode, j.state, j.imported_rows,
       (SELECT count(*) FROM public.import_375_mixed_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.import_375_mixed_data WHERE state = 'processing')
FROM public.import_job AS j JOIN worker.tasks AS w ON (w.payload->>'job_id')::integer = j.id AND w.command = 'import_job'
WHERE j.slug = 'import_375_mixed';
CALL worker.process_tasks(p_queue => 'import');
\echo Mixed final: both target units have their requested final names
SELECT count(DISTINCT id), count(*) FROM public.legal_unit WHERE name IN ('T375 mixed existing', 'T375 mixed new');

-- Existing target units stay serial even when input intervals do not overlap
-- their current histories. Analysis resolves their target IDs before processing.
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_375_reused', 'T375 reused targets', 'T375', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_375_reused_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT '2019-01-01', '2019-12-31', (375000000 + n)::text, 'T375 earlier ' || n, '2100', 'AS', 'brreg'
FROM generate_series(1, 4) AS n;
CALL test.t375_to_processing('import_375_reused');
\echo Reused targets: four rows resolve to four existing units
SELECT count(*), count(DISTINCT legal_unit_id)
FROM public.import_375_reused_data;
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo Reused job: serial wrapper, exactly one row imported before remaining serial work
SELECT w.child_mode, j.state, j.imported_rows,
       (SELECT count(*) FROM public.import_375_reused_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.import_375_reused_data WHERE state = 'processing')
FROM public.import_job AS j JOIN worker.tasks AS w ON (w.payload->>'job_id')::integer = j.id AND w.command = 'import_job'
WHERE j.slug = 'import_375_reused';
CALL worker.process_tasks(p_queue => 'import');
\echo Reused final: four additional versions on the four original units
SELECT count(DISTINCT id), count(*) FROM public.legal_unit WHERE name LIKE 'T375 earlier %';

-- Informal establishments are outside the initial concurrent eligibility set,
-- even when all rows create new units with independent enterprise parents.
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_375_informal', 'T375 informal establishments', 'T375', false, 1
FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates';
INSERT INTO public.import_375_informal_upload (valid_from, valid_to, tax_ident, name, data_source_code)
SELECT '2020-01-01', 'infinity', (375300000 + n)::text, 'T375 informal ' || n, 'brreg'
FROM generate_series(1, 4) AS n;
CALL test.t375_to_processing('import_375_informal');
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo Informal job: serial wrapper, one imported row and three remaining processing rows
SELECT w.child_mode, j.state, j.imported_rows,
       (SELECT count(*) FROM public.import_375_informal_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.import_375_informal_data WHERE state = 'processing')
FROM public.import_job AS j JOIN worker.tasks AS w ON (w.payload->>'job_id')::integer = j.id AND w.command = 'import_job'
WHERE j.slug = 'import_375_informal';
CALL worker.process_tasks(p_queue => 'import');
\echo Informal final: four establishments, four versions, four enterprise parents
SELECT count(DISTINCT id), count(*), count(DISTINCT enterprise_id)
FROM public.establishment WHERE name LIKE 'T375 informal %';

-- A fixture row-state trigger raises after the real domain writes. The whole
-- leaf transaction must roll back before failure propagates through fan-in.
-- Installing it after dispatch leaves the scheduler's eligibility input genuine.
CALL test.remove_pg_temp_for_tx_user_switch();
RESET ROLE;
CREATE TABLE test.t375_job_states (seq integer GENERATED ALWAYS AS IDENTITY, state public.import_job_state);
GRANT SELECT, INSERT ON test.t375_job_states TO admin_user;
GRANT USAGE ON SEQUENCE test.t375_job_states_seq_seq TO admin_user;
CREATE FUNCTION test.t375_record_job_state() RETURNS trigger
LANGUAGE plpgsql AS $t375_record_job_state$
BEGIN
    INSERT INTO test.t375_job_states (state) VALUES (NEW.state);
    RETURN NEW;
END;
$t375_record_job_state$;
CREATE TRIGGER t375_record_job_state AFTER UPDATE OF state ON public.import_job
FOR EACH ROW WHEN (NEW.slug = 'import_375_fail' AND OLD.state IS DISTINCT FROM NEW.state)
EXECUTE FUNCTION test.t375_record_job_state();

CREATE FUNCTION test.t375_batch_failure() RETURNS trigger
LANGUAGE plpgsql AS $t375_batch_failure$
BEGIN
    RAISE EXCEPTION 'T375 intentional batch tail failure';
END;
$t375_batch_failure$;
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review, processing_batch_size)
SELECT id, 'import_375_fail', 'T375 failing batch', 'T375', false, 1
FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
INSERT INTO public.import_375_fail_upload
    (valid_from, valid_to, tax_ident, name, sector_code, legal_form_code, data_source_code)
SELECT '2020-01-01', 'infinity', (375200000 + n)::text, 'T375 failure ' || n, '2100', 'AS', 'brreg'
FROM generate_series(1, 4) AS n;
CALL test.t375_to_processing('import_375_fail');
CALL test.t375_add_holistic('import_375_fail');
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'serial');
\echo Failure fanout: four eligible leaves wait before the injected batch tail failure
SELECT d.state, d.child_mode,
       (SELECT count(*) FROM worker.tasks WHERE parent_id = d.id AND command = 'import_job_process_batch')
FROM worker.tasks AS d JOIN public.import_job AS j ON j.id = (d.payload->>'job_id')::integer
WHERE j.slug = 'import_375_fail' AND d.child_mode = 'concurrent';
RESET ROLE;
CREATE TRIGGER t375_batch_failure BEFORE UPDATE OF state ON public.import_375_fail_data
FOR EACH ROW WHEN (NEW.state = 'processed') EXECUTE FUNCTION test.t375_batch_failure();
CALL test.set_user_from_email('test.admin@statbus.org');
CALL worker.process_tasks(p_batch_size => 1, p_queue => 'import', p_mode => 'concurrent');
\echo Failed leaf: durable job failure and task failure before remaining siblings drain
SELECT j.state, j.imported_rows,
       (SELECT bool_or(state = 'failed') FROM worker.tasks WHERE command = 'import_job_process_batch'
        AND (payload->>'job_id')::integer = j.id),
       (SELECT count(*) FROM public.legal_unit WHERE name LIKE 'T375 failure %')
FROM public.import_job AS j WHERE slug = 'import_375_fail';
CALL worker.process_tasks(p_queue => 'import');
\echo Failed batch: job and wrapper failed, zero imported, error recorded, holistic unrun
SELECT j.state, w.state, j.imported_rows, j.error IS NOT NULL,
       (SELECT count(*) FROM test.t375_holistic WHERE slug = j.slug),
       (SELECT count(*) FROM public.import_375_fail_data WHERE state = 'processed'),
       (SELECT count(*) FROM public.legal_unit WHERE name LIKE 'T375 failure %')
FROM public.import_job AS j JOIN worker.tasks AS w ON (w.payload->>'job_id')::integer = j.id AND w.command = 'import_job'
WHERE j.slug = 'import_375_fail';
\echo Failed job transitions: processing_data leads to failed rather than finished
SELECT array_agg(state ORDER BY seq) FROM test.t375_job_states;

\echo Finished totals: successful jobs preserve exact input and imported row counts
SELECT slug, state, total_rows, imported_rows FROM public.import_job
WHERE slug IN ('import_375_lu', 'import_375_es', 'import_375_es_reused', 'import_375_mixed', 'import_375_reused', 'import_375_informal', 'import_375_history') ORDER BY slug;
\echo Final registry totals: thirteen enterprises, nine legal units with twenty-two versions, twelve establishments
SELECT (SELECT count(*) FROM public.enterprise),
       (SELECT count(DISTINCT id) FROM public.legal_unit),
       (SELECT count(*) FROM public.legal_unit),
       (SELECT count(DISTINCT id) FROM public.establishment),
       (SELECT count(*) FROM public.establishment);
ROLLBACK;
