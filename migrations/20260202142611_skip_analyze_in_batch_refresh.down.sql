BEGIN;

-- ============================================================================
-- 0. Remove derive_statistical_unit_continue command and related objects
-- ============================================================================

-- Drop the continuation procedure
DROP PROCEDURE IF EXISTS worker.derive_statistical_unit_continue(jsonb);

-- Drop the impl function
DROP FUNCTION IF EXISTS worker.derive_statistical_unit_impl(int4multirange, int4multirange, int4multirange, date, date, bigint, int);

-- Remove the command from registry
DELETE FROM worker.command_registry WHERE command = 'derive_statistical_unit_continue';

-- ============================================================================
-- Revert chunked fan-out changes
-- ============================================================================

-- Drop the modified function first
DROP FUNCTION IF EXISTS worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date, bigint);

-- Restore original derive_statistical_unit function (without chunking)
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_task_id bigint DEFAULT NULL::bigint
)
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
    v_uncle_priority BIGINT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL 
                         AND p_legal_unit_id_ranges IS NULL 
                         AND p_enterprise_id_ranges IS NULL);
    
    v_child_priority := nextval('public.worker_task_priority_seq');
    v_uncle_priority := nextval('public.worker_task_priority_seq');
    
    IF v_is_full_refresh THEN
        FOR v_batch IN 
            SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
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
        
        FOR v_batch IN 
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            )
        LOOP
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'explicit_enterprise_ids', v_enterprise_ids,
                    'explicit_legal_unit_ids', v_legal_unit_ids,
                    'explicit_establishment_ids', v_establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
        
        IF v_batch_count = 0 AND (
            COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 OR
            COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 OR
            COALESCE(array_length(v_establishment_ids, 1), 0) > 0
        ) THEN
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', 1,
                    'enterprise_ids', ARRAY[]::INT[],
                    'legal_unit_ids', ARRAY[]::INT[],
                    'establishment_ids', ARRAY[]::INT[],
                    'explicit_enterprise_ids', v_enterprise_ids,
                    'explicit_legal_unit_ids', v_legal_unit_ids,
                    'explicit_establishment_ids', v_establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := 1;
            RAISE DEBUG 'derive_statistical_unit: No groups matched, spawned cleanup-only batch';
        END IF;
    END IF;
    
    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %', v_batch_count, p_task_id;

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );
    
    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$function$;

-- Restore original procedure wrapper
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $procedure$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
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
        p_task_id := v_task_id
    );
END;
$procedure$;

-- Restore original get_closed_group_batches (without offset/limit)
CREATE OR REPLACE FUNCTION public.get_closed_group_batches(
    p_target_batch_size integer DEFAULT 1000,
    p_establishment_ids integer[] DEFAULT NULL::integer[],
    p_legal_unit_ids integer[] DEFAULT NULL::integer[],
    p_enterprise_ids integer[] DEFAULT NULL::integer[]
)
RETURNS TABLE(
    batch_seq integer, 
    group_ids integer[], 
    enterprise_ids integer[], 
    legal_unit_ids integer[], 
    establishment_ids integer[], 
    total_unit_count integer
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_batch_seq INT := 1;
    v_current_batch_size INT := 0;
    v_group RECORD;
    v_filter_active BOOLEAN;
BEGIN
    v_filter_active := (p_establishment_ids IS NOT NULL 
                       OR p_legal_unit_ids IS NOT NULL 
                       OR p_enterprise_ids IS NOT NULL);
    
    IF to_regclass('pg_temp._batch_accumulator') IS NOT NULL THEN DROP TABLE _batch_accumulator; END IF;
    CREATE TEMP TABLE _batch_accumulator (
        group_id INT,
        enterprise_id INT,
        legal_unit_id INT,
        establishment_id INT
    ) ON COMMIT DROP;
    
    FOR v_group IN 
        WITH 
        all_groups AS (
            SELECT * FROM public.get_enterprise_closed_groups()
        ),
        affected_enterprise_ids AS (
            SELECT UNNEST(p_enterprise_ids) AS enterprise_id
            WHERE p_enterprise_ids IS NOT NULL
            UNION
            SELECT DISTINCT lu.enterprise_id
            FROM public.legal_unit lu
            WHERE lu.id = ANY(p_legal_unit_ids) AND p_legal_unit_ids IS NOT NULL
            UNION
            SELECT DISTINCT COALESCE(lu.enterprise_id, es.enterprise_id)
            FROM public.establishment es
            LEFT JOIN public.legal_unit lu ON es.legal_unit_id = lu.id
            WHERE es.id = ANY(p_establishment_ids) AND p_establishment_ids IS NOT NULL
        ),
        affected_groups AS (
            SELECT DISTINCT g.group_id
            FROM all_groups g
            CROSS JOIN affected_enterprise_ids ae
            WHERE ae.enterprise_id = ANY(g.enterprise_ids)
        )
        SELECT 
            g.group_id,
            g.enterprise_ids,
            g.legal_unit_ids,
            g.establishment_ids,
            g.total_unit_count
        FROM all_groups g
        WHERE NOT v_filter_active OR g.group_id IN (SELECT group_id FROM affected_groups)
        ORDER BY g.total_unit_count DESC, g.group_id
    LOOP
        IF v_current_batch_size > 0 
           AND v_current_batch_size + v_group.total_unit_count > p_target_batch_size 
        THEN
            SELECT 
                v_current_batch_seq,
                array_agg(DISTINCT ba.group_id ORDER BY ba.group_id),
                array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                v_current_batch_size
            INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count
            FROM _batch_accumulator ba;
            RETURN NEXT;
            
            v_current_batch_seq := v_current_batch_seq + 1;
            v_current_batch_size := 0;
            TRUNCATE _batch_accumulator;
        END IF;
        
        INSERT INTO _batch_accumulator (group_id) VALUES (v_group.group_id);
        INSERT INTO _batch_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
        INSERT INTO _batch_accumulator (legal_unit_id) SELECT UNNEST(v_group.legal_unit_ids);
        INSERT INTO _batch_accumulator (establishment_id) SELECT UNNEST(v_group.establishment_ids);
        
        v_current_batch_size := v_current_batch_size + v_group.total_unit_count;
    END LOOP;
    
    IF v_current_batch_size > 0 THEN
        SELECT 
            v_current_batch_seq,
            array_agg(DISTINCT ba.group_id ORDER BY ba.group_id),
            array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
            array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
            array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
            v_current_batch_size
        INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count
        FROM _batch_accumulator ba;
        RETURN NEXT;
    END IF;
END;
$function$;

-- Drop the analyze_derived_tables helper
DROP PROCEDURE IF EXISTS public.analyze_derived_tables();

-- Remove batches_per_wave column
ALTER TABLE worker.command_registry DROP COLUMN IF EXISTS batches_per_wave;

-- Restore original refresh procedures with ANALYZE

CREATE OR REPLACE PROCEDURE public.timepoints_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
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
BEGIN
    ANALYZE public.establishment, public.legal_unit, public.enterprise, public.activity, public.location, public.contact, public.stat_for_unit, public.person_for_unit;

    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
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
                RAISE DEBUG 'Timepoints batch %/% for enterprises done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), v_batch_size, round(v_batch_duration_ms), round(v_batch_speed);

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
            RAISE DEBUG 'Timepoints final batch %/% for enterprises done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_enterprises::decimal / v_batch_size), array_length(v_en_batch, 1), round(v_batch_duration_ms), round(v_batch_speed);
        END IF;

        RAISE DEBUG 'Populated staging table, now swapping data...';
        TRUNCATE public.timepoints;
        INSERT INTO public.timepoints SELECT DISTINCT * FROM timepoints_new;
        RAISE DEBUG 'Full timepoints refresh complete.';
    ELSE
        RAISE DEBUG 'Starting partial timepoints refresh...';
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;

        INSERT INTO public.timepoints SELECT * FROM public.timepoints_calculate(
            p_establishment_id_ranges,
            p_legal_unit_id_ranges,
            p_enterprise_id_ranges
        ) ON CONFLICT DO NOTHING;

        RAISE DEBUG 'Partial timepoints refresh complete.';
    END IF;

    ANALYZE public.timepoints;
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.timesegments_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $procedure$
BEGIN
    ANALYZE public.timepoints;

    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        DELETE FROM public.timesegments;
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
    ELSE
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
        END IF;
    END IF;

    ANALYZE public.timesegments;
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.timeline_refresh(
    IN p_target_table text,
    IN p_unit_type public.statistical_unit_type,
    IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 65536;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
BEGIN
    IF p_unit_id_ranges IS NOT NULL THEN
        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange', p_target_table, p_unit_type, p_unit_id_ranges);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange',
                       p_target_table, v_def_view_name, p_unit_type, p_unit_id_ranges);
    ELSE
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing % for % units in batches of %...', p_target_table, v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;

            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG '% batch %/% done. (% units, % ms, % units/s)', p_target_table, v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;
    END IF;

    EXECUTE format('ANALYZE public.%I', p_target_table);
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.timeline_establishment_refresh(
    IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $procedure$
BEGIN
    ANALYZE public.timesegments, public.establishment, public.activity, public.location, public.contact, public.stat_for_unit;
    CALL public.timeline_refresh('timeline_establishment', 'establishment', p_unit_id_ranges);
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.timeline_legal_unit_refresh(
    IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $procedure$
BEGIN
    ANALYZE public.timesegments, public.legal_unit, public.activity, public.location, public.contact, public.stat_for_unit, public.timeline_establishment;
    CALL public.timeline_refresh('timeline_legal_unit', 'legal_unit', p_unit_id_ranges);
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.timeline_enterprise_refresh(
    IN p_unit_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    p_target_table text := 'timeline_enterprise';
    p_unit_type public.statistical_unit_type := 'enterprise';
    v_batch_size INT := 32768;
    v_def_view_name text := p_target_table || '_def';
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT := 0;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
BEGIN
    ANALYZE public.timesegments, public.enterprise, public.timeline_legal_unit, public.timeline_establishment;

    IF p_unit_id_ranges IS NOT NULL THEN
        EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange', p_target_table, p_unit_type, p_unit_id_ranges);
        EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id <@ %L::int4multirange',
                       p_target_table, v_def_view_name, p_unit_type, p_unit_id_ranges);
    ELSE
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = p_unit_type;
        IF v_min_id IS NULL THEN RETURN; END IF;

        RAISE DEBUG 'Refreshing enterprise timeline for % units in batches of %...', v_total_units, v_batch_size;
        FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('DELETE FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, p_unit_type, v_start_id, v_end_id);
            EXECUTE format('INSERT INTO public.%I SELECT * FROM public.%I WHERE unit_type = %L AND unit_id BETWEEN %L AND %L',
                           p_target_table, v_def_view_name, p_unit_type, v_start_id, v_end_id);

            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise timeline batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP;
    END IF;

    EXECUTE format('ANALYZE public.%I', p_target_table);
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
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
BEGIN
    ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;

        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'establishment' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Establishment SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'legal_unit' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Legal unit SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises in batches of %...', v_total_units, v_batch_size;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_start_time := clock_timestamp();
            v_batch_num := v_batch_num + 1;
            v_start_id := i; v_end_id := i + v_batch_size - 1;
            INSERT INTO statistical_unit_new SELECT * FROM public.statistical_unit_def
            WHERE unit_type = 'enterprise' AND unit_id BETWEEN v_start_id AND v_end_id;
            v_batch_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start_time))) * 1000;
            v_current_batch_size := v_batch_size;
            v_batch_speed := v_current_batch_size / (v_batch_duration_ms / 1000.0);
            RAISE DEBUG 'Enterprise SU batch %/% done. (% units, % ms, % units/s)', v_batch_num, ceil(v_total_units::decimal / v_batch_size), v_current_batch_size, round(v_batch_duration_ms), round(v_batch_speed);
        END LOOP; END IF;

        TRUNCATE public.statistical_unit;
        INSERT INTO public.statistical_unit SELECT * FROM statistical_unit_new;
    ELSE
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.statistical_unit 
            SELECT * FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges);
        END IF;
    END IF;

    ANALYZE public.statistical_unit;
END;
$procedure$;

END;
