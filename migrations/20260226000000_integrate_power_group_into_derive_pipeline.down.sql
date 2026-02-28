-- Down Migration: Revert power_group pipeline integration
-- Restores all functions to their pre-migration signatures and drops new objects.

BEGIN;

-- ============================================================================
-- SECTION 0a: Revert derive_power_groups pipeline removal (Section 16 of up)
-- ============================================================================

-- Restore derive_power_groups as a Phase 1 pipeline command
UPDATE worker.command_registry
SET phase = 'is_deriving_statistical_units',
    after_procedure = NULL
WHERE command = 'derive_power_groups';

-- ============================================================================
-- SECTION 0b: Revert import system changes (Sections 15 of up)
-- ============================================================================

-- Remove power_group_link step from definitions
DELETE FROM public.import_definition_step
WHERE step_id = (SELECT id FROM public.import_step WHERE code = 'power_group_link');

-- Remove data columns for power_group_link
DELETE FROM public.import_data_column
WHERE step_id = (SELECT id FROM public.import_step WHERE code = 'power_group_link');

-- Remove the power_group_link import step
DELETE FROM public.import_step WHERE code = 'power_group_link';

-- Drop analyse/process procedures
DROP PROCEDURE IF EXISTS import.analyse_power_group_link(integer, integer, text);
DROP PROCEDURE IF EXISTS import.process_power_group_link(integer, integer, text);

-- Restore original import_job_processing_phase (no holistic support)
CREATE OR REPLACE FUNCTION admin.import_job_processing_phase(job import_job)
RETURNS boolean
LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_batch INTEGER;
    v_max_batch INTEGER;
    v_rows_processed INTEGER;
    error_message TEXT;
    error_context TEXT;
BEGIN
    -- Get the current batch to process (smallest batch_seq that still has unprocessed rows)
    EXECUTE format($$
        SELECT MIN(batch_seq), MAX(batch_seq)
        FROM public.%1$I
        WHERE batch_seq IS NOT NULL AND state = 'processing'
    $$, job.data_table_name) INTO v_current_batch, v_max_batch;

    IF v_current_batch IS NULL THEN
        RAISE DEBUG '[Job %] No more batches to process. Phase complete.', job.id;
        RETURN FALSE; -- No work found.
    END IF;

    RAISE DEBUG '[Job %] Processing batch % of % (max).', job.id, v_current_batch, v_max_batch;

    BEGIN
        CALL admin.import_job_process_batch(job, v_current_batch);

        -- Mark all rows in the batch that are not in an error state as 'processed'.
        EXECUTE format($$
            UPDATE public.%1$I
            SET state = 'processed'
            WHERE batch_seq = %2$L AND state != 'error'
        $$, job.data_table_name, v_current_batch);
        GET DIAGNOSTICS v_rows_processed = ROW_COUNT;

        RAISE DEBUG '[Job %] Batch % successfully processed. Marked % non-error rows as processed.',
            job.id, v_current_batch, v_rows_processed;

        -- Increment imported_rows counter directly instead of doing a full table scan.
        UPDATE public.import_job SET imported_rows = imported_rows + v_rows_processed WHERE id = job.id;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT,
                              error_context = PG_EXCEPTION_CONTEXT;
        RAISE WARNING '[Job %] Error processing batch %: %. Context: %. Marking batch rows as error and failing job.',
            job.id, v_current_batch, error_message, error_context;

        EXECUTE format($$
            UPDATE public.%1$I
            SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || %2$L
            WHERE batch_seq = %3$L
        $$, job.data_table_name,
            jsonb_build_object('process_batch_error', error_message, 'context', error_context),
            v_current_batch);

        UPDATE public.import_job
        SET error = jsonb_build_object('error_in_processing_batch', error_message, 'context', error_context)::TEXT,
            state = 'failed'
        WHERE id = job.id;

        RETURN FALSE; -- On error, do not reschedule.
    END;

    RETURN TRUE; -- Work was done.
END;
$function$;

-- Restore original import_job_process_batch (no holistic skip)
CREATE OR REPLACE PROCEDURE admin.import_job_process_batch(IN job import_job, IN p_batch_seq integer)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    targets JSONB;
    target_rec RECORD;
    proc_to_call REGPROC;
    error_message TEXT;
    v_should_disable_triggers BOOLEAN;
BEGIN
    RAISE DEBUG '[Job %] Processing batch_seq % through all process steps.', job.id, p_batch_seq;
    targets := job.definition_snapshot->'import_step_list';

    EXECUTE format(
        'SELECT EXISTS(SELECT 1 FROM public.%I dt WHERE dt.batch_seq = $1 AND dt.operation IS DISTINCT FROM %L)',
        job.data_table_name,
        'insert'
    )
    INTO v_should_disable_triggers
    USING p_batch_seq;

    IF v_should_disable_triggers THEN
        RAISE DEBUG '[Job %] Batch contains updates/replaces. Disabling FK triggers.', job.id;
        CALL admin.disable_temporal_triggers();
    ELSE
        RAISE DEBUG '[Job %] Batch is insert-only. Skipping trigger disable/enable.', job.id;
    END IF;

    FOR target_rec IN SELECT * FROM jsonb_populate_recordset(NULL::public.import_step, targets) ORDER BY priority
    LOOP
        proc_to_call := target_rec.process_procedure;
        IF proc_to_call IS NULL THEN
            CONTINUE;
        END IF;

        RAISE DEBUG '[Job %] Batch processing: Calling % for step %', job.id, proc_to_call, target_rec.code;

        EXECUTE format('CALL %s($1, $2, $3)', proc_to_call) USING job.id, p_batch_seq, target_rec.code;
    END LOOP;

    IF v_should_disable_triggers THEN
        RAISE DEBUG '[Job %] Re-enabling FK triggers.', job.id;
        CALL admin.enable_temporal_triggers();
    END IF;

    RAISE DEBUG '[Job %] Batch processing complete.', job.id;
END;
$procedure$;

-- ============================================================================
-- SECTION 0c: Restore collect_changes without PG ID computation (Section 14 of up)
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
    v_round_priority_base BIGINT;
BEGIN
    FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
        v_est_ids := v_est_ids + v_row.establishment_ids;
        v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
        v_ent_ids := v_ent_ids + v_row.enterprise_ids;
        v_valid_range := v_valid_range + v_row.edited_by_valid_range;
    END LOOP;

    UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange THEN

        SELECT priority INTO v_round_priority_base
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        IF v_valid_range = '{}'::datemultirange THEN
            SELECT COALESCE(range_agg(vr)::datemultirange, '{}'::datemultirange)
            INTO v_valid_range
            FROM (
                SELECT valid_range AS vr FROM public.establishment AS est
                  WHERE v_est_ids @> est.id
                UNION ALL
                SELECT valid_range AS vr FROM public.legal_unit AS lu
                  WHERE v_lu_ids @> lu.id
            ) AS units;
        END IF;

        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        PERFORM worker.enqueue_derive_statistical_unit(
            p_establishment_id_ranges := v_est_ids,
            p_legal_unit_id_ranges := v_lu_ids,
            p_enterprise_id_ranges := v_ent_ids,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until,
            p_round_priority_base := v_round_priority_base
        );
    END IF;
END;
$procedure$;

-- ============================================================================
-- SECTION 1: Drop trigger + function we created, restore original trigger
-- ============================================================================

DROP TRIGGER IF EXISTS a_legal_relationship_log_insert ON public.legal_relationship;
DROP TRIGGER IF EXISTS a_legal_relationship_log_update ON public.legal_relationship;
DROP TRIGGER IF EXISTS a_legal_relationship_log_delete ON public.legal_relationship;

-- Restore original trigger function
CREATE OR REPLACE FUNCTION public.legal_relationship_queue_derive_power_groups()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $legal_relationship_queue_derive_power_groups$
BEGIN
    PERFORM worker.enqueue_derive_power_groups();
    RETURN NULL;
END;
$legal_relationship_queue_derive_power_groups$;

CREATE TRIGGER legal_relationship_derive_power_groups_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.legal_relationship
FOR EACH STATEMENT
EXECUTE FUNCTION public.legal_relationship_queue_derive_power_groups();

-- ============================================================================
-- SECTION 2: Drop new timeline_power_group infrastructure
-- ============================================================================

-- Must drop statistical_unit_def first since it references timeline_power_group
DROP VIEW IF EXISTS public.statistical_unit_def CASCADE;
DROP TABLE IF EXISTS public.timeline_power_group;
DROP VIEW IF EXISTS public.timeline_power_group_def;
DROP PROCEDURE IF EXISTS public.timeline_power_group_refresh(int4multirange);

-- ============================================================================
-- SECTION 3: Drop functions with new 4-param signatures
-- ============================================================================

DROP FUNCTION IF EXISTS public.timepoints_calculate(int4multirange, int4multirange, int4multirange, int4multirange);
DROP PROCEDURE IF EXISTS public.timepoints_refresh(int4multirange, int4multirange, int4multirange, int4multirange);
DROP PROCEDURE IF EXISTS public.timesegments_refresh(int4multirange, int4multirange, int4multirange, int4multirange);
DROP PROCEDURE IF EXISTS public.statistical_unit_refresh(int4multirange, int4multirange, int4multirange, int4multirange);
DROP FUNCTION IF EXISTS worker.enqueue_derive_statistical_unit(int4multirange, int4multirange, int4multirange, int4multirange, date, date, bigint);
DROP FUNCTION IF EXISTS worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, int4multirange, date, date, bigint, bigint);
DROP FUNCTION IF EXISTS worker.derive_power_groups(bigint, date, date);
DROP FUNCTION IF EXISTS worker.enqueue_derive_power_groups(bigint, date, date);

-- ============================================================================
-- SECTION 4: Restore original 3-param functions
-- ============================================================================

-- 4a. timepoints_calculate
CREATE OR REPLACE FUNCTION public.timepoints_calculate(p_establishment_id_ranges int4multirange, p_legal_unit_id_ranges int4multirange, p_enterprise_id_ranges int4multirange)
 RETURNS TABLE(unit_type statistical_unit_type, unit_id integer, timepoint date)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_es_ids INT[];
    v_lu_ids INT[];
    v_en_ids INT[];
BEGIN
    -- Convert multiranges to arrays for btree-friendly queries
    IF p_establishment_id_ranges IS NOT NULL THEN
        v_es_ids := public.int4multirange_to_array(p_establishment_id_ranges);
    END IF;
    IF p_legal_unit_id_ranges IS NOT NULL THEN
        v_lu_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
    END IF;
    IF p_enterprise_id_ranges IS NOT NULL THEN
        v_en_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
    END IF;

    RETURN QUERY
    -- This function calculates all significant timepoints for a given set of statistical units.
    -- It is the core of the "gather and propagate" strategy. Uses = ANY(array) for btree index usage.
    -- Note: CTEs use src_unit_id to avoid ambiguity with return column unit_id in PL/pgSQL.
    WITH es_periods AS (
        -- 1. Gather all raw temporal periods related to the given establishments.
        SELECT id AS src_unit_id, valid_from, valid_until FROM public.establishment WHERE v_es_ids IS NULL OR id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.activity WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.location WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.contact WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.stat_for_unit WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
        UNION ALL SELECT establishment_id, valid_from, valid_until FROM public.person_for_unit WHERE v_es_ids IS NULL OR establishment_id = ANY(v_es_ids)
    ),
    lu_periods_base AS (
        -- 2. Gather periods directly related to the given legal units (NOT from their children yet).
        SELECT id AS src_unit_id, valid_from, valid_until FROM public.legal_unit WHERE v_lu_ids IS NULL OR id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.activity WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.location WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.contact WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.stat_for_unit WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
        UNION ALL SELECT legal_unit_id, valid_from, valid_until FROM public.person_for_unit WHERE v_lu_ids IS NULL OR legal_unit_id = ANY(v_lu_ids)
    ),
    -- This CTE represents all periods relevant to a legal unit, including those propagated up from its child establishments.
    lu_periods_with_children AS (
        SELECT src_unit_id, valid_from, valid_until FROM lu_periods_base
        UNION ALL
        -- Propagate from establishments to legal units, WITH TRIMMING to the lifespan of the link.
        SELECT es.legal_unit_id, GREATEST(p.valid_from, es.valid_from) AS valid_from, LEAST(p.valid_until, es.valid_until) AS valid_until
        FROM es_periods AS p JOIN public.establishment AS es ON p.src_unit_id = es.id
        WHERE (v_lu_ids IS NULL OR es.legal_unit_id = ANY(v_lu_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
    ),
    all_periods (src_unit_type, src_unit_id, valid_from, valid_until) AS (
        -- 3. Combine and trim all periods for all unit types.
        -- Establishment periods are trimmed to their own lifespan slices.
        SELECT 'establishment'::public.statistical_unit_type, e.id, GREATEST(p.valid_from, e.valid_from), LEAST(p.valid_until, e.valid_until)
        FROM es_periods p JOIN public.establishment e ON p.src_unit_id = e.id
        WHERE (v_es_ids IS NULL OR e.id = ANY(v_es_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, e.valid_from, e.valid_until)
        UNION ALL
        -- Legal Unit periods are from the comprehensive CTE, trimmed to their own lifespan slices.
        SELECT 'legal_unit', l.id, GREATEST(p.valid_from, l.valid_from), LEAST(p.valid_until, l.valid_until)
        FROM lu_periods_with_children p JOIN public.legal_unit l ON p.src_unit_id = l.id
        WHERE (v_lu_ids IS NULL OR l.id = ANY(v_lu_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, l.valid_from, l.valid_until)
        UNION ALL
        -- Enterprise periods are propagated from Legal Units (and their children), trimmed to the LU-EN link lifespan.
        SELECT 'enterprise', lu.enterprise_id, GREATEST(p.valid_from, lu.valid_from), LEAST(p.valid_until, lu.valid_until)
        FROM lu_periods_with_children p JOIN public.legal_unit lu ON p.src_unit_id = lu.id
        WHERE (v_en_ids IS NULL OR lu.enterprise_id = ANY(v_en_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, lu.valid_from, lu.valid_until)
        UNION ALL
        -- Enterprise periods are also propagated from directly-linked Establishments, trimmed to the EST-EN link lifespan.
        SELECT 'enterprise', es.enterprise_id, GREATEST(p.valid_from, es.valid_from), LEAST(p.valid_until, es.valid_until)
        FROM es_periods p JOIN public.establishment es ON p.src_unit_id = es.id
        WHERE es.enterprise_id IS NOT NULL AND (v_en_ids IS NULL OR es.enterprise_id = ANY(v_en_ids)) AND from_until_overlaps(p.valid_from, p.valid_until, es.valid_from, es.valid_until)
    ),
    unpivoted AS (
        -- 4. Unpivot valid periods into a single `timepoint` column, ensuring we don't create zero-duration segments.
        SELECT p.src_unit_type, p.src_unit_id, p.valid_from AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
        UNION
        SELECT p.src_unit_type, p.src_unit_id, p.valid_until AS timepoint FROM all_periods p WHERE p.valid_from < p.valid_until
    )
    -- 5. Deduplicate to get the final, unique set of change dates for each unit.
    SELECT DISTINCT up.src_unit_type, up.src_unit_id, up.timepoint
    FROM unpivoted up
    WHERE up.timepoint IS NOT NULL;
END;
$function$;

-- 4b. timepoints_refresh
CREATE OR REPLACE PROCEDURE public.timepoints_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    rec RECORD;
    v_en_batch INT[];
    v_lu_batch INT[];
    v_es_batch INT[];
    v_batch_size INT := 32768;
    v_total_enterprises INT;
    v_processed_count INT := 0;
    v_batch_num INT := 0;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_is_partial_refresh BOOLEAN;
    -- Arrays for btree-optimized queries
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL);

    -- Only ANALYZE for full refresh (sync points handle partial refresh ANALYZE)
    IF NOT v_is_partial_refresh THEN
        ANALYZE public.establishment, public.legal_unit, public.enterprise, public.activity, public.location, public.contact, public.stat_for_unit, public.person_for_unit;

        CREATE TEMP TABLE timepoints_new (LIKE public.timepoints) ON COMMIT DROP;

        SELECT count(*) INTO v_total_enterprises FROM public.enterprise;
        RAISE DEBUG 'Starting full timepoints refresh for % enterprises in batches of %...', v_total_enterprises, v_batch_size;

        FOR rec IN SELECT id FROM public.enterprise LOOP
            v_en_batch := array_append(v_en_batch, rec.id);

            IF array_length(v_en_batch, 1) >= v_batch_size THEN
                v_batch_start_time := clock_timestamp();
                v_processed_count := v_processed_count + array_length(v_en_batch, 1);
                v_batch_num := v_batch_num + 1;

                v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
                v_es_batch := ARRAY(
                    SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch)
                    UNION
                    SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch)
                );

                INSERT INTO timepoints_new
                SELECT * FROM public.timepoints_calculate(
                    public.array_to_int4multirange(v_es_batch),
                    public.array_to_int4multirange(v_lu_batch),
                    public.array_to_int4multirange(v_en_batch)
                ) ON CONFLICT DO NOTHING;

                v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
                v_batch_speed := v_batch_size / (v_batch_duration_ms / 1000.0);
                RAISE DEBUG 'Timepoints batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), v_batch_size, round(v_batch_duration_ms), round(v_batch_speed);

                v_en_batch := '{}';
            END IF;
        END LOOP;

        IF array_length(v_en_batch, 1) > 0 THEN
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_lu_batch := ARRAY(SELECT id FROM public.legal_unit WHERE enterprise_id = ANY(v_en_batch));
            v_es_batch := ARRAY(
                SELECT id FROM public.establishment WHERE legal_unit_id = ANY(v_lu_batch)
                UNION
                SELECT id FROM public.establishment WHERE enterprise_id = ANY(v_en_batch)
            );
            INSERT INTO timepoints_new
            SELECT * FROM public.timepoints_calculate(
                public.array_to_int4multirange(v_es_batch),
                public.array_to_int4multirange(v_lu_batch),
                public.array_to_int4multirange(v_en_batch)
            ) ON CONFLICT DO NOTHING;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_batch_speed := array_length(v_en_batch, 1) / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Timepoints final batch done. (% units, % ms, % units/s)', array_length(v_en_batch, 1), round(v_batch_duration_ms), round(v_batch_speed);
        END IF;

        RAISE DEBUG 'Populated staging table, now swapping data...';
        TRUNCATE public.timepoints;
        INSERT INTO public.timepoints SELECT DISTINCT * FROM timepoints_new;
        RAISE DEBUG 'Full timepoints refresh complete.';

        ANALYZE public.timepoints;
    ELSE
        -- Partial refresh: Use = ANY(array) for btree index optimization
        RAISE DEBUG 'Starting partial timepoints refresh...';

        -- Convert multiranges to arrays for btree-friendly queries
        IF p_establishment_id_ranges IS NOT NULL THEN
            v_establishment_ids := public.int4multirange_to_array(p_establishment_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            v_legal_unit_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            v_enterprise_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
            DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
        END IF;

        INSERT INTO public.timepoints SELECT * FROM public.timepoints_calculate(
            p_establishment_id_ranges,
            p_legal_unit_id_ranges,
            p_enterprise_id_ranges
        ) ON CONFLICT DO NOTHING;

        RAISE DEBUG 'Partial timepoints refresh complete.';
    END IF;
END;
$procedure$;

-- 4c. timesegments_refresh
CREATE OR REPLACE PROCEDURE public.timesegments_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_is_partial_refresh BOOLEAN;
    -- Arrays for btree-optimized queries
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timepoints;
        DELETE FROM public.timesegments;
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
        ANALYZE public.timesegments;
    ELSE
        -- Partial refresh: Use = ANY(array) for btree index optimization
        IF p_establishment_id_ranges IS NOT NULL THEN
            v_establishment_ids := public.int4multirange_to_array(p_establishment_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'establishment' AND unit_id = ANY(v_establishment_ids);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            v_legal_unit_ids := public.int4multirange_to_array(p_legal_unit_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_legal_unit_ids);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            v_enterprise_ids := public.int4multirange_to_array(p_enterprise_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'enterprise' AND unit_id = ANY(v_enterprise_ids);
        END IF;
    END IF;
END;
$procedure$;

-- ============================================================================
-- SECTION 5: Restore original enqueue and derive functions
-- ============================================================================

-- 5a. enqueue_derive_statistical_unit (original 6-param signature)
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_establishment_id_ranges int4multirange := COALESCE(p_establishment_id_ranges, '{}'::int4multirange);
  v_legal_unit_id_ranges int4multirange := COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange);
  v_enterprise_id_ranges int4multirange := COALESCE(p_enterprise_id_ranges, '{}'::int4multirange);
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  -- Round priority: use round base if provided, otherwise fall back to sequence
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

  v_payload := jsonb_build_object(
    'command', 'derive_statistical_unit',
    'establishment_id_ranges', v_establishment_id_ranges,
    'legal_unit_id_ranges', v_legal_unit_id_ranges,
    'enterprise_id_ranges', v_enterprise_id_ranges,
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );

  INSERT INTO worker.tasks AS t (
    command, payload, priority
  ) VALUES ('derive_statistical_unit', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_unit' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_unit',
      'establishment_id_ranges', (t.payload->>'establishment_id_ranges')::int4multirange + (EXCLUDED.payload->>'establishment_id_ranges')::int4multirange,
      'legal_unit_id_ranges', (t.payload->>'legal_unit_id_ranges')::int4multirange + (EXCLUDED.payload->>'legal_unit_id_ranges')::int4multirange,
      'enterprise_id_ranges', (t.payload->>'enterprise_id_ranges')::int4multirange + (EXCLUDED.payload->>'enterprise_id_ranges')::int4multirange,
      'valid_from', LEAST(
        (t.payload->>'valid_from')::date,
        (EXCLUDED.payload->>'valid_from')::date
      ),
      'valid_until', GREATEST(
        (t.payload->>'valid_until')::date,
        (EXCLUDED.payload->>'valid_until')::date
      ),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority),
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$;

-- 5b. enqueue_derive_power_groups (original no-param signature)
CREATE FUNCTION worker.enqueue_derive_power_groups()
RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_derive_power_groups$
DECLARE
    _task_id BIGINT;
    _payload JSONB;
BEGIN
    _payload := jsonb_build_object('command', 'derive_power_groups');

    INSERT INTO worker.tasks AS t (command, payload)
    VALUES ('derive_power_groups', _payload)
    ON CONFLICT (command)
    WHERE command = 'derive_power_groups' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        state = 'pending'::worker.task_state,
        priority = EXCLUDED.priority,
        processed_at = NULL,
        error = NULL
    RETURNING id INTO _task_id;

    PERFORM pg_notify('worker_tasks', 'analytics');

    RETURN _task_id;
END;
$enqueue_derive_power_groups$;

-- 5c. derive_statistical_unit function (pipeline-progress version with p_round_priority_base)
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    -- Unit count accumulators for pipeline progress
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Priority for children: use round base if available, otherwise nextval
    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all partitions
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
            -- Accumulate unit counts (O(1) per call — reads array metadata)
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_legal_unit_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_enterprise_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r)
        );

        -- =====================================================================
        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        -- =====================================================================
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(
                SELECT id FROM unnest(v_enterprise_ids) AS id
                EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids)
            );
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs',
                    array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(
                SELECT id FROM unnest(v_legal_unit_ids) AS id
                EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids)
            );
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs',
                    array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(
                SELECT id FROM unnest(v_establishment_ids) AS id
                EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids)
            );
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs',
                    array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;

        -- =====================================================================
        -- BATCHING: Only existing entities, partitioned with no overlap
        -- =====================================================================
        IF to_regclass('pg_temp._batches') IS NOT NULL THEN
            DROP TABLE _batches;
        END IF;
        CREATE TEMP TABLE _batches ON COMMIT DROP AS
        SELECT * FROM public.get_closed_group_batches(
            p_target_batch_size := 1000,
            p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
            p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
            p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
        );

        -- =====================================================================
        -- DIRTY PARTITION TRACKING
        -- =====================================================================
        INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
        SELECT DISTINCT public.report_partition_seq(
            t.unit_type, t.unit_id,
            (SELECT analytics_partition_count FROM public.settings)
        )
        FROM (
            SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id
            FROM _batches AS b
            UNION ALL
            SELECT 'legal_unit', unnest(b.legal_unit_ids)
            FROM _batches AS b
            UNION ALL
            SELECT 'establishment', unnest(b.establishment_ids)
            FROM _batches AS b
        ) AS t
        WHERE t.unit_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        RAISE DEBUG 'derive_statistical_unit: Tracked dirty facet partitions for closed group across % batches',
            (SELECT count(*) FROM _batches);

        -- Spawn batch children and accumulate unit counts
        FOR v_batch IN SELECT * FROM _batches
        LOOP
            -- Accumulate unit counts (O(1) per call — reads array metadata)
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count;

    -- Create/update Phase 1 row with unit counts
    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count, updated_at)
    VALUES
        ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        updated_at = EXCLUDED.updated_at;

    -- Pre-create Phase 2 row with counts (pending, visible to user before phase 2 starts)
    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count, updated_at)
    VALUES
        ('is_deriving_reports', NULL, 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        updated_at = EXCLUDED.updated_at;

    -- Refresh derived data (used flags) - always full refreshes, run synchronously
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- =========================================================================
    -- STAGING PATTERN: Enqueue flush task (runs after all batches complete)
    -- =========================================================================
    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base := p_round_priority_base
    );
    RAISE DEBUG 'derive_statistical_unit: Enqueued flush_staging task';

    -- Enqueue derive_reports as an "uncle" task (runs after flush completes)
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_round_priority_base := p_round_priority_base
    );

    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$function$;

-- 5d. derive_statistical_unit procedure (pipeline-progress version)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_round_priority_base bigint = (payload->>'round_priority_base')::bigint;
    v_task_id BIGINT;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY processed_at DESC NULLS LAST, id DESC
    LIMIT 1;

    PERFORM worker.derive_statistical_unit(
        p_establishment_id_ranges := v_establishment_id_ranges,
        p_legal_unit_id_ranges := v_legal_unit_id_ranges,
        p_enterprise_id_ranges := v_enterprise_id_ranges,
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until,
        p_task_id := v_task_id,
        p_round_priority_base := v_round_priority_base
    );
END;
$procedure$;

-- 5e. derive_power_groups function (original from power_group_worker_infrastructure)
CREATE FUNCTION worker.derive_power_groups()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_power_groups$
DECLARE
    _cluster RECORD;
    _power_group power_group;
    _created_count integer := 0;
    _updated_count integer := 0;
    _linked_count integer := 0;
    _row_count integer;
    _current_user_id integer;
BEGIN
    RAISE DEBUG '[derive_power_groups] Starting power group derivation';

    -- Disable the trigger that re-enqueues derive_power_groups when we update legal_relationship.power_group_id
    -- Without this, every UPDATE below fires the trigger -> enqueues a new task -> infinite loop
    ALTER TABLE public.legal_relationship DISABLE TRIGGER legal_relationship_derive_power_groups_trigger;

    -- Find a user for edit tracking
    SELECT id INTO _current_user_id
    FROM auth.user
    WHERE email = session_user
       OR session_user = 'postgres';

    IF _current_user_id IS NULL THEN
        SELECT id INTO _current_user_id
        FROM auth.user
        WHERE role_id = (SELECT id FROM auth.role WHERE name = 'super_user')
        LIMIT 1;
    END IF;

    IF _current_user_id IS NULL THEN
        RAISE EXCEPTION 'No user found for power group derivation';
    END IF;

    -- Step 1: For each cluster (identified by root_legal_unit_id), find or create power_group
    -- and assign to relationships
    FOR _cluster IN
        SELECT DISTINCT root_legal_unit_id
        FROM public.legal_relationship_cluster
    LOOP
        -- Check if any relationship in this cluster already has a power_group assigned
        SELECT pg.* INTO _power_group
        FROM public.power_group AS pg
        JOIN public.legal_relationship AS lr ON lr.power_group_id = pg.id
        JOIN public.legal_relationship_cluster AS lrc ON lrc.legal_relationship_id = lr.id
        WHERE lrc.root_legal_unit_id = _cluster.root_legal_unit_id
        LIMIT 1;

        IF NOT FOUND THEN
            -- Create new power_group for this cluster
            INSERT INTO public.power_group (
                edit_by_user_id
            ) VALUES (
                _current_user_id
            )
            RETURNING * INTO _power_group;

            _created_count := _created_count + 1;
            RAISE DEBUG '[derive_power_groups] Created power_group % for root LU %',
                _power_group.ident, _cluster.root_legal_unit_id;
        ELSE
            _updated_count := _updated_count + 1;
        END IF;

        -- Step 2: Assign power_group_id to all relationships in this cluster
        UPDATE public.legal_relationship AS lr
        SET power_group_id = _power_group.id
        FROM public.legal_relationship_cluster AS lrc
        WHERE lr.id = lrc.legal_relationship_id
          AND lrc.root_legal_unit_id = _cluster.root_legal_unit_id
          AND (lr.power_group_id IS DISTINCT FROM _power_group.id);

        GET DIAGNOSTICS _row_count = ROW_COUNT;
        _linked_count := _linked_count + _row_count;
    END LOOP;

    -- Step 3: Handle cluster merges - when one cluster acquires another
    WITH cluster_sizes AS (
        SELECT
            lr.power_group_id,
            COUNT(*) AS rel_count
        FROM public.legal_relationship AS lr
        WHERE lr.power_group_id IS NOT NULL
        GROUP BY lr.power_group_id
    ),
    merge_candidates AS (
        SELECT DISTINCT
            lrc.root_legal_unit_id,
            lr.power_group_id AS current_pg_id,
            cs.rel_count
        FROM public.legal_relationship_cluster AS lrc
        JOIN public.legal_relationship AS lr ON lr.id = lrc.legal_relationship_id
        JOIN cluster_sizes AS cs ON cs.power_group_id = lr.power_group_id
        WHERE lr.power_group_id IS NOT NULL
    ),
    clusters_with_multiple_pgs AS (
        SELECT
            root_legal_unit_id,
            array_agg(current_pg_id ORDER BY rel_count DESC, current_pg_id) AS pg_ids
        FROM merge_candidates
        GROUP BY root_legal_unit_id
        HAVING COUNT(DISTINCT current_pg_id) > 1
    )
    UPDATE public.legal_relationship AS lr
    SET power_group_id = cwmp.pg_ids[1]
    FROM public.legal_relationship_cluster AS lrc
    JOIN clusters_with_multiple_pgs AS cwmp ON cwmp.root_legal_unit_id = lrc.root_legal_unit_id
    WHERE lr.id = lrc.legal_relationship_id
      AND lr.power_group_id != cwmp.pg_ids[1];

    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[derive_power_groups] Merged % relationships into surviving power groups', _row_count;
    END IF;

    -- Step 4: Clear power_group_id from relationships that are not primary-influencer
    UPDATE public.legal_relationship AS lr
    SET power_group_id = NULL
    WHERE lr.power_group_id IS NOT NULL
      AND lr.primary_influencer_only IS NOT TRUE;

    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[derive_power_groups] Cleared power_group from % non-primary-influencer relationships', _row_count;
    END IF;

    RAISE DEBUG '[derive_power_groups] Completed: created=%, updated=%, linked=%',
        _created_count, _updated_count, _linked_count;

    -- Re-enable the trigger so future DML on legal_relationship queues derivation normally
    ALTER TABLE public.legal_relationship ENABLE TRIGGER legal_relationship_derive_power_groups_trigger;
END;
$derive_power_groups$;

-- 5f. derive_power_groups procedure (original wrapper)
CREATE OR REPLACE PROCEDURE worker.derive_power_groups(payload JSONB)
SECURITY DEFINER
SET search_path = public, worker, pg_temp
LANGUAGE plpgsql
AS $procedure$
BEGIN
    PERFORM worker.derive_power_groups();
END;
$procedure$;

-- ============================================================================
-- SECTION 6: Restore original statistical_unit_refresh_batch
-- ============================================================================

CREATE OR REPLACE PROCEDURE worker.statistical_unit_refresh_batch(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_batch_seq INT := (payload->>'batch_seq')::INT;
    v_enterprise_ids INT[];
    v_legal_unit_ids INT[];
    v_establishment_ids INT[];
    v_enterprise_id_ranges int4multirange;
    v_legal_unit_id_ranges int4multirange;
    v_establishment_id_ranges int4multirange;
BEGIN
    -- Extract batch IDs from payload
    IF jsonb_typeof(payload->'enterprise_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_enterprise_ids
        FROM jsonb_array_elements_text(payload->'enterprise_ids') AS value;
    END IF;

    IF jsonb_typeof(payload->'legal_unit_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_legal_unit_ids
        FROM jsonb_array_elements_text(payload->'legal_unit_ids') AS value;
    END IF;

    IF jsonb_typeof(payload->'establishment_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_establishment_ids
        FROM jsonb_array_elements_text(payload->'establishment_ids') AS value;
    END IF;

    v_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids);
    v_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids);
    v_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids);

    RAISE DEBUG 'Processing batch % with % enterprises, % legal_units, % establishments',
        v_batch_seq,
        COALESCE(array_length(v_enterprise_ids, 1), 0),
        COALESCE(array_length(v_legal_unit_ids, 1), 0),
        COALESCE(array_length(v_establishment_ids, 1), 0);

    -- Call refresh procedures for this batch.
    -- IMPORTANT: Use COALESCE to pass empty multirange '{}' instead of NULL.
    -- NULL is interpreted as "full refresh" which runs ANALYZE, acquiring
    -- ShareUpdateExclusiveLock that serializes all concurrent batch workers.
    CALL public.timepoints_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange)
    );

    CALL public.timesegments_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange)
    );

    -- Use concurrent-safe version for years
    CALL public.timesegments_years_refresh_concurrent();

    -- Timeline refreshes: skip when no IDs for that unit type (avoids full refresh)
    IF v_establishment_id_ranges IS NOT NULL THEN
        CALL public.timeline_establishment_refresh(p_unit_id_ranges => v_establishment_id_ranges);
    END IF;
    IF v_legal_unit_id_ranges IS NOT NULL THEN
        CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => v_legal_unit_id_ranges);
    END IF;
    IF v_enterprise_id_ranges IS NOT NULL THEN
        CALL public.timeline_enterprise_refresh(p_unit_id_ranges => v_enterprise_id_ranges);
    END IF;

    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange)
    );
END;
$procedure$;

-- ============================================================================
-- SECTION 7: Restore original statistical_unit_refresh (3-param)
-- ============================================================================

CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

        -- Create temp table WITHOUT valid_range (it's GENERATED in the target)
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;
        ALTER TABLE statistical_unit_new DROP COLUMN IF EXISTS valid_range;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'establishment' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Establishment SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'legal_unit' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Legal unit SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM public.statistical_unit_def
            WHERE unit_type = 'enterprise' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        TRUNCATE public.statistical_unit;
        -- Use explicit column list for final insert (temp table has no valid_range)
        INSERT INTO public.statistical_unit (
            unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
            primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
            secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
            activity_category_paths, sector_id, sector_path, sector_code, sector_name,
            data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
            physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
            physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
            physical_latitude, physical_longitude, physical_altitude, domestic,
            postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
            postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
            postal_latitude, postal_longitude, postal_altitude,
            web_address, email_address, phone_number, landline, mobile_number, fax_number,
            unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
            last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
            related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
            related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
            related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
            stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
        )
        SELECT
            unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
            primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
            secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
            activity_category_paths, sector_id, sector_path, sector_code, sector_name,
            data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
            physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
            physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
            physical_latitude, physical_longitude, physical_altitude, domestic,
            postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
            postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
            postal_latitude, postal_longitude, postal_altitude,
            web_address, email_address, phone_number, landline, mobile_number, fax_number,
            unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
            last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
            related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
            related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
            related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
            stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
        FROM statistical_unit_new;

        ANALYZE public.statistical_unit;
    ELSE
        -- =====================================================================
        -- PARTIAL REFRESH: Write only to staging table.
        -- Main table is NOT modified here - flush_staging handles the atomic swap.
        -- This means worker crash leaves main table complete (with old data).
        -- =====================================================================

        IF p_establishment_id_ranges IS NOT NULL THEN
            -- Delete from staging to handle multiple updates to same unit within a derive cycle
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            -- Insert to staging table (explicit columns - staging doesn't have valid_range)
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.statistical_unit_staging (
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            )
            SELECT
                unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
                primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
                secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
                activity_category_paths, sector_id, sector_path, sector_code, sector_name,
                data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
                physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
                physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
                physical_latitude, physical_longitude, physical_altitude, domestic,
                postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
                postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
                postal_latitude, postal_longitude, postal_altitude,
                web_address, email_address, phone_number, landline, mobile_number, fax_number,
                unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
                last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
                related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
                related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
                related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
                stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths
            FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges);
        END IF;
    END IF;
END;
$procedure$;

-- ============================================================================
-- SECTION 8: Restore original statistical_unit_def view (without power_group)
-- ============================================================================

-- Must DROP CASCADE because statistical_unit_refresh references it
DROP VIEW IF EXISTS public.statistical_unit_def CASCADE;

CREATE OR REPLACE VIEW public.statistical_unit_def WITH (security_invoker = on) AS
WITH external_idents_agg AS (
    SELECT all_idents.unit_type,
        all_idents.unit_id,
        jsonb_object_agg(all_idents.type_code, all_idents.ident) AS external_idents
    FROM ( SELECT 'establishment'::statistical_unit_type AS unit_type,
                ei.establishment_id AS unit_id,
                eit.code AS type_code,
                COALESCE(ei.ident, ei.idents::text::character varying) AS ident
            FROM external_ident ei
                JOIN external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id IS NOT NULL
            UNION ALL
            SELECT 'legal_unit'::statistical_unit_type,
                ei.legal_unit_id,
                eit.code,
                COALESCE(ei.ident, ei.idents::text::character varying)
            FROM external_ident ei
                JOIN external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id IS NOT NULL
            UNION ALL
            SELECT 'enterprise'::statistical_unit_type,
                ei.enterprise_id,
                eit.code,
                COALESCE(ei.ident, ei.idents::text::character varying)
            FROM external_ident ei
                JOIN external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.enterprise_id IS NOT NULL
            UNION ALL
            SELECT 'power_group'::statistical_unit_type,
                ei.power_group_id,
                eit.code,
                COALESCE(ei.ident, ei.idents::text::character varying)
            FROM external_ident ei
                JOIN external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.power_group_id IS NOT NULL
    ) all_idents
    GROUP BY all_idents.unit_type, all_idents.unit_id
), tag_paths_agg AS (
    SELECT all_tags.unit_type,
        all_tags.unit_id,
        array_agg(all_tags.path ORDER BY all_tags.path) AS tag_paths
    FROM ( SELECT 'establishment'::statistical_unit_type AS unit_type,
                tfu.establishment_id AS unit_id,
                t.path
            FROM tag_for_unit tfu
                JOIN tag t ON tfu.tag_id = t.id
            WHERE tfu.establishment_id IS NOT NULL
            UNION ALL
            SELECT 'legal_unit'::statistical_unit_type,
                tfu.legal_unit_id,
                t.path
            FROM tag_for_unit tfu
                JOIN tag t ON tfu.tag_id = t.id
            WHERE tfu.legal_unit_id IS NOT NULL
            UNION ALL
            SELECT 'enterprise'::statistical_unit_type,
                tfu.enterprise_id,
                t.path
            FROM tag_for_unit tfu
                JOIN tag t ON tfu.tag_id = t.id
            WHERE tfu.enterprise_id IS NOT NULL
            UNION ALL
            SELECT 'power_group'::statistical_unit_type,
                tfu.power_group_id,
                t.path
            FROM tag_for_unit tfu
                JOIN tag t ON tfu.tag_id = t.id
            WHERE tfu.power_group_id IS NOT NULL
    ) all_tags
    GROUP BY all_tags.unit_type, all_tags.unit_id
), data AS (
    SELECT
        timeline_establishment.unit_type, timeline_establishment.unit_id,
        timeline_establishment.valid_from, timeline_establishment.valid_to, timeline_establishment.valid_until,
        timeline_establishment.name, timeline_establishment.birth_date, timeline_establishment.death_date, timeline_establishment.search,
        timeline_establishment.primary_activity_category_id, timeline_establishment.primary_activity_category_path, timeline_establishment.primary_activity_category_code,
        timeline_establishment.secondary_activity_category_id, timeline_establishment.secondary_activity_category_path, timeline_establishment.secondary_activity_category_code,
        timeline_establishment.activity_category_paths,
        timeline_establishment.sector_id, timeline_establishment.sector_path, timeline_establishment.sector_code, timeline_establishment.sector_name,
        timeline_establishment.data_source_ids, timeline_establishment.data_source_codes,
        timeline_establishment.legal_form_id, timeline_establishment.legal_form_code, timeline_establishment.legal_form_name,
        timeline_establishment.physical_address_part1, timeline_establishment.physical_address_part2, timeline_establishment.physical_address_part3,
        timeline_establishment.physical_postcode, timeline_establishment.physical_postplace,
        timeline_establishment.physical_region_id, timeline_establishment.physical_region_path, timeline_establishment.physical_region_code,
        timeline_establishment.physical_country_id, timeline_establishment.physical_country_iso_2,
        timeline_establishment.physical_latitude, timeline_establishment.physical_longitude, timeline_establishment.physical_altitude,
        timeline_establishment.domestic,
        timeline_establishment.postal_address_part1, timeline_establishment.postal_address_part2, timeline_establishment.postal_address_part3,
        timeline_establishment.postal_postcode, timeline_establishment.postal_postplace,
        timeline_establishment.postal_region_id, timeline_establishment.postal_region_path, timeline_establishment.postal_region_code,
        timeline_establishment.postal_country_id, timeline_establishment.postal_country_iso_2,
        timeline_establishment.postal_latitude, timeline_establishment.postal_longitude, timeline_establishment.postal_altitude,
        timeline_establishment.web_address, timeline_establishment.email_address,
        timeline_establishment.phone_number, timeline_establishment.landline, timeline_establishment.mobile_number, timeline_establishment.fax_number,
        timeline_establishment.unit_size_id, timeline_establishment.unit_size_code,
        timeline_establishment.status_id, timeline_establishment.status_code,
        timeline_establishment.used_for_counting,
        timeline_establishment.last_edit_comment, timeline_establishment.last_edit_by_user_id, timeline_establishment.last_edit_at,
        timeline_establishment.has_legal_unit,
        timeline_establishment.related_establishment_ids, timeline_establishment.excluded_establishment_ids, timeline_establishment.included_establishment_ids,
        timeline_establishment.related_legal_unit_ids, timeline_establishment.excluded_legal_unit_ids, timeline_establishment.included_legal_unit_ids,
        timeline_establishment.related_enterprise_ids, timeline_establishment.excluded_enterprise_ids, timeline_establishment.included_enterprise_ids,
        timeline_establishment.stats, timeline_establishment.stats_summary,
        NULL::integer AS primary_establishment_id, NULL::integer AS primary_legal_unit_id
    FROM timeline_establishment
    UNION ALL
    SELECT
        timeline_legal_unit.unit_type, timeline_legal_unit.unit_id,
        timeline_legal_unit.valid_from, timeline_legal_unit.valid_to, timeline_legal_unit.valid_until,
        timeline_legal_unit.name, timeline_legal_unit.birth_date, timeline_legal_unit.death_date, timeline_legal_unit.search,
        timeline_legal_unit.primary_activity_category_id, timeline_legal_unit.primary_activity_category_path, timeline_legal_unit.primary_activity_category_code,
        timeline_legal_unit.secondary_activity_category_id, timeline_legal_unit.secondary_activity_category_path, timeline_legal_unit.secondary_activity_category_code,
        timeline_legal_unit.activity_category_paths,
        timeline_legal_unit.sector_id, timeline_legal_unit.sector_path, timeline_legal_unit.sector_code, timeline_legal_unit.sector_name,
        timeline_legal_unit.data_source_ids, timeline_legal_unit.data_source_codes,
        timeline_legal_unit.legal_form_id, timeline_legal_unit.legal_form_code, timeline_legal_unit.legal_form_name,
        timeline_legal_unit.physical_address_part1, timeline_legal_unit.physical_address_part2, timeline_legal_unit.physical_address_part3,
        timeline_legal_unit.physical_postcode, timeline_legal_unit.physical_postplace,
        timeline_legal_unit.physical_region_id, timeline_legal_unit.physical_region_path, timeline_legal_unit.physical_region_code,
        timeline_legal_unit.physical_country_id, timeline_legal_unit.physical_country_iso_2,
        timeline_legal_unit.physical_latitude, timeline_legal_unit.physical_longitude, timeline_legal_unit.physical_altitude,
        timeline_legal_unit.domestic,
        timeline_legal_unit.postal_address_part1, timeline_legal_unit.postal_address_part2, timeline_legal_unit.postal_address_part3,
        timeline_legal_unit.postal_postcode, timeline_legal_unit.postal_postplace,
        timeline_legal_unit.postal_region_id, timeline_legal_unit.postal_region_path, timeline_legal_unit.postal_region_code,
        timeline_legal_unit.postal_country_id, timeline_legal_unit.postal_country_iso_2,
        timeline_legal_unit.postal_latitude, timeline_legal_unit.postal_longitude, timeline_legal_unit.postal_altitude,
        timeline_legal_unit.web_address, timeline_legal_unit.email_address,
        timeline_legal_unit.phone_number, timeline_legal_unit.landline, timeline_legal_unit.mobile_number, timeline_legal_unit.fax_number,
        timeline_legal_unit.unit_size_id, timeline_legal_unit.unit_size_code,
        timeline_legal_unit.status_id, timeline_legal_unit.status_code,
        timeline_legal_unit.used_for_counting,
        timeline_legal_unit.last_edit_comment, timeline_legal_unit.last_edit_by_user_id, timeline_legal_unit.last_edit_at,
        timeline_legal_unit.has_legal_unit,
        timeline_legal_unit.related_establishment_ids, timeline_legal_unit.excluded_establishment_ids, timeline_legal_unit.included_establishment_ids,
        timeline_legal_unit.related_legal_unit_ids, timeline_legal_unit.excluded_legal_unit_ids, timeline_legal_unit.included_legal_unit_ids,
        timeline_legal_unit.related_enterprise_ids, timeline_legal_unit.excluded_enterprise_ids, timeline_legal_unit.included_enterprise_ids,
        NULL::jsonb AS stats, timeline_legal_unit.stats_summary,
        NULL::integer AS primary_establishment_id, NULL::integer AS primary_legal_unit_id
    FROM timeline_legal_unit
    UNION ALL
    SELECT
        timeline_enterprise.unit_type, timeline_enterprise.unit_id,
        timeline_enterprise.valid_from, timeline_enterprise.valid_to, timeline_enterprise.valid_until,
        timeline_enterprise.name, timeline_enterprise.birth_date, timeline_enterprise.death_date, timeline_enterprise.search,
        timeline_enterprise.primary_activity_category_id, timeline_enterprise.primary_activity_category_path, timeline_enterprise.primary_activity_category_code,
        timeline_enterprise.secondary_activity_category_id, timeline_enterprise.secondary_activity_category_path, timeline_enterprise.secondary_activity_category_code,
        timeline_enterprise.activity_category_paths,
        timeline_enterprise.sector_id, timeline_enterprise.sector_path, timeline_enterprise.sector_code, timeline_enterprise.sector_name,
        timeline_enterprise.data_source_ids, timeline_enterprise.data_source_codes,
        timeline_enterprise.legal_form_id, timeline_enterprise.legal_form_code, timeline_enterprise.legal_form_name,
        timeline_enterprise.physical_address_part1, timeline_enterprise.physical_address_part2, timeline_enterprise.physical_address_part3,
        timeline_enterprise.physical_postcode, timeline_enterprise.physical_postplace,
        timeline_enterprise.physical_region_id, timeline_enterprise.physical_region_path, timeline_enterprise.physical_region_code,
        timeline_enterprise.physical_country_id, timeline_enterprise.physical_country_iso_2,
        timeline_enterprise.physical_latitude, timeline_enterprise.physical_longitude, timeline_enterprise.physical_altitude,
        timeline_enterprise.domestic,
        timeline_enterprise.postal_address_part1, timeline_enterprise.postal_address_part2, timeline_enterprise.postal_address_part3,
        timeline_enterprise.postal_postcode, timeline_enterprise.postal_postplace,
        timeline_enterprise.postal_region_id, timeline_enterprise.postal_region_path, timeline_enterprise.postal_region_code,
        timeline_enterprise.postal_country_id, timeline_enterprise.postal_country_iso_2,
        timeline_enterprise.postal_latitude, timeline_enterprise.postal_longitude, timeline_enterprise.postal_altitude,
        timeline_enterprise.web_address, timeline_enterprise.email_address,
        timeline_enterprise.phone_number, timeline_enterprise.landline, timeline_enterprise.mobile_number, timeline_enterprise.fax_number,
        timeline_enterprise.unit_size_id, timeline_enterprise.unit_size_code,
        timeline_enterprise.status_id, timeline_enterprise.status_code,
        timeline_enterprise.used_for_counting,
        timeline_enterprise.last_edit_comment, timeline_enterprise.last_edit_by_user_id, timeline_enterprise.last_edit_at,
        timeline_enterprise.has_legal_unit,
        timeline_enterprise.related_establishment_ids, timeline_enterprise.excluded_establishment_ids, timeline_enterprise.included_establishment_ids,
        timeline_enterprise.related_legal_unit_ids, timeline_enterprise.excluded_legal_unit_ids, timeline_enterprise.included_legal_unit_ids,
        timeline_enterprise.related_enterprise_ids, timeline_enterprise.excluded_enterprise_ids, timeline_enterprise.included_enterprise_ids,
        NULL::jsonb AS stats, timeline_enterprise.stats_summary,
        timeline_enterprise.primary_establishment_id, timeline_enterprise.primary_legal_unit_id
    FROM timeline_enterprise
)
SELECT data.unit_type, data.unit_id,
    data.valid_from, data.valid_to, data.valid_until,
    COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
    data.name, data.birth_date, data.death_date, data.search,
    data.primary_activity_category_id, data.primary_activity_category_path, data.primary_activity_category_code,
    data.secondary_activity_category_id, data.secondary_activity_category_path, data.secondary_activity_category_code,
    data.activity_category_paths,
    data.sector_id, data.sector_path, data.sector_code, data.sector_name,
    data.data_source_ids, data.data_source_codes,
    data.legal_form_id, data.legal_form_code, data.legal_form_name,
    data.physical_address_part1, data.physical_address_part2, data.physical_address_part3,
    data.physical_postcode, data.physical_postplace,
    data.physical_region_id, data.physical_region_path, data.physical_region_code,
    data.physical_country_id, data.physical_country_iso_2,
    data.physical_latitude, data.physical_longitude, data.physical_altitude,
    data.domestic,
    data.postal_address_part1, data.postal_address_part2, data.postal_address_part3,
    data.postal_postcode, data.postal_postplace,
    data.postal_region_id, data.postal_region_path, data.postal_region_code,
    data.postal_country_id, data.postal_country_iso_2,
    data.postal_latitude, data.postal_longitude, data.postal_altitude,
    data.web_address, data.email_address,
    data.phone_number, data.landline, data.mobile_number, data.fax_number,
    data.unit_size_id, data.unit_size_code,
    data.status_id, data.status_code,
    data.used_for_counting,
    data.last_edit_comment, data.last_edit_by_user_id, data.last_edit_at,
    data.has_legal_unit,
    data.related_establishment_ids, data.excluded_establishment_ids, data.included_establishment_ids,
    data.related_legal_unit_ids, data.excluded_legal_unit_ids, data.included_legal_unit_ids,
    data.related_enterprise_ids, data.excluded_enterprise_ids, data.included_enterprise_ids,
    data.stats, data.stats_summary,
    array_length(data.included_establishment_ids, 1) AS included_establishment_count,
    array_length(data.included_legal_unit_ids, 1) AS included_legal_unit_count,
    array_length(data.included_enterprise_ids, 1) AS included_enterprise_count,
    COALESCE(tpa.tag_paths, ARRAY[]::ltree[]) AS tag_paths
FROM data
    LEFT JOIN external_idents_agg eia1 ON eia1.unit_type = data.unit_type AND eia1.unit_id = data.unit_id
    LEFT JOIN external_idents_agg eia2 ON eia2.unit_type = 'establishment'::statistical_unit_type AND eia2.unit_id = data.primary_establishment_id
    LEFT JOIN external_idents_agg eia3 ON eia3.unit_type = 'legal_unit'::statistical_unit_type AND eia3.unit_id = data.primary_legal_unit_id
    LEFT JOIN tag_paths_agg tpa ON tpa.unit_type = data.unit_type AND tpa.unit_id = data.unit_id;

-- ============================================================================
-- SECTION 9: Restore original log_base_change (without legal_relationship)
-- ============================================================================

CREATE OR REPLACE FUNCTION worker.log_base_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    -- Column mapping based on table name
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id';
            v_has_valid_range := FALSE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    -- Add valid_range to column list
    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    -- Build source query based on operation
    CASE TG_OP
        WHEN 'INSERT' THEN
            v_source := format('SELECT %s FROM new_rows', v_columns);
        WHEN 'DELETE' THEN
            v_source := format('SELECT %s FROM old_rows', v_columns);
        WHEN 'UPDATE' THEN
            v_source := format('SELECT %s FROM old_rows UNION ALL SELECT %s FROM new_rows',
                               v_columns, v_columns);
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- Aggregate into multiranges
    -- CRITICAL: Use FILTER (WHERE col IS NOT NULL) to avoid int4range(NULL,NULL,'[]')
    -- which produces unbounded range (,) meaning ALL integers, not empty.
    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_valid_range;

    -- Only insert if there's actually something to record
    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, edited_by_valid_range)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_valid_range);
    END IF;

    RETURN NULL;
END;
$function$;

-- ============================================================================
-- SECTION 10: Restore original get_statistical_unit_data_partial (without power_group)
-- ============================================================================

CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    -- PERF: Convert multirange to array once for efficient = ANY() filtering
    v_ids INT[] := public.int4multirange_to_array(p_id_ranges);
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT
            t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.establishment_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT
            t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.legal_unit_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT
            t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.physical_latitude, t.physical_longitude, t.physical_altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.postal_latitude, t.postal_longitude, t.postal_altitude,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings)) AS report_partition_seq
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.enterprise_id = t.unit_id
        ) eia1 ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.establishment_id = t.primary_establishment_id
        ) eia2 ON true
        LEFT JOIN LATERAL (
            SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents
            FROM public.external_ident ei
            JOIN public.external_ident_type eit ON ei.type_id = eit.id
            WHERE ei.legal_unit_id = t.primary_legal_unit_id
        ) eia3 ON true
        LEFT JOIN LATERAL (
            SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths
            FROM public.tag_for_unit tfu
            JOIN public.tag ON tfu.tag_id = tag.id
            WHERE tfu.enterprise_id = t.unit_id
        ) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$function$;

-- ============================================================================
-- SECTION 11: Revoke grants on dropped objects (cleanup)
-- ============================================================================

-- No action needed: objects were dropped, grants go with them.
-- Grants on existing objects (statistical_unit_def) are preserved through recreation.

-- ============================================================================
-- SECTION 12: Clean up any power_group data from statistical_unit
-- ============================================================================

DELETE FROM public.statistical_unit WHERE unit_type = 'power_group';
DELETE FROM public.statistical_unit_staging WHERE unit_type = 'power_group';
DELETE FROM public.timesegments WHERE unit_type = 'power_group';
DELETE FROM public.timepoints WHERE unit_type = 'power_group';

-- ============================================================================
-- SECTION 13: Revert pipeline_progress changes
-- ============================================================================

-- Remove phase from derive_power_groups command
UPDATE worker.command_registry SET phase = NULL WHERE command = 'derive_power_groups';

-- Drop affected_power_group_count column
ALTER TABLE worker.pipeline_progress DROP COLUMN IF EXISTS affected_power_group_count;

-- Restore notify_start without affected_power_group_count
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_start()
LANGUAGE plpgsql
AS $procedure$
BEGIN
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = EXCLUDED.step, total = 0, completed = 0,
    affected_establishment_count = NULL, affected_legal_unit_count = NULL,
    affected_enterprise_count = NULL, updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);
END;
$procedure$;

-- Restore is_deriving_statistical_units without power_group count
CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', pp.phase IS NOT NULL,
    'step', pp.step,
    'total', COALESCE(pp.total, 0),
    'completed', COALESCE(pp.completed, 0),
    'affected_establishment_count', pp.affected_establishment_count,
    'affected_legal_unit_count', pp.affected_legal_unit_count,
    'affected_enterprise_count', pp.affected_enterprise_count
  )
  FROM (SELECT NULL) AS dummy
  LEFT JOIN worker.pipeline_progress AS pp ON pp.phase = 'is_deriving_statistical_units';
$function$;

-- Restore is_deriving_reports without power_group count
CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', pp.phase IS NOT NULL,
    'step', pp.step,
    'total', COALESCE(pp.total, 0),
    'completed', COALESCE(pp.completed, 0),
    'affected_establishment_count', pp.affected_establishment_count,
    'affected_legal_unit_count', pp.affected_legal_unit_count,
    'affected_enterprise_count', pp.affected_enterprise_count
  )
  FROM (SELECT NULL) AS dummy
  LEFT JOIN worker.pipeline_progress AS pp ON pp.phase = 'is_deriving_reports';
$function$;

-- Restore pipeline_progress_on_child_completed without power_group count
CREATE OR REPLACE PROCEDURE worker.pipeline_progress_on_child_completed(
    IN p_phase worker.pipeline_phase,
    IN p_parent_task_id BIGINT
)
LANGUAGE plpgsql
AS $pipeline_progress_on_child_completed$
BEGIN
    UPDATE worker.pipeline_progress
    SET completed = completed + 1,
        updated_at = clock_timestamp()
    WHERE phase = p_phase;

    PERFORM pg_notify('worker_status',
        json_build_object(
            'type', 'pipeline_progress',
            'phases', COALESCE(
                (SELECT json_agg(json_build_object(
                    'phase', pp.phase, 'step', pp.step,
                    'total', pp.total, 'completed', pp.completed,
                    'affected_establishment_count', pp.affected_establishment_count,
                    'affected_legal_unit_count', pp.affected_legal_unit_count,
                    'affected_enterprise_count', pp.affected_enterprise_count
                )) FROM worker.pipeline_progress AS pp),
                '[]'::json
            )
        )::text
    );
END;
$pipeline_progress_on_child_completed$;
END;
