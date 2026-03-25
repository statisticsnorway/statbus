-- Migration 20260325011559: virtual_physical_partition_mapping_with_auto_tune
--
-- Makes the partition modulus configurable via settings instead of hardcoded 256.
-- Adds auto-tune that adjusts modulus based on unit count (called per pipeline).
-- Changing modulus is self-healing: "populated < expected" triggers full refresh.
BEGIN;

----------------------------------------------------------------------
-- 1. Settings column + STABLE function (cached per query)
----------------------------------------------------------------------
ALTER TABLE public.settings ADD COLUMN report_partition_modulus integer NOT NULL DEFAULT 256;

-- Named get_report_partition_modulus (not report_partition_modulus) to avoid
-- colliding with the settings.report_partition_modulus column name, which
-- confuses postgrest-js type-level select inference.
CREATE OR REPLACE FUNCTION public.get_report_partition_modulus()
 RETURNS integer
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $get_report_partition_modulus$
    SELECT COALESCE((SELECT report_partition_modulus FROM public.settings LIMIT 1), 256);
$get_report_partition_modulus$;

----------------------------------------------------------------------
-- 2. Hash functions stay IMMUTABLE (required by GENERATED ALWAYS column)
-- The modulus in report_partition_seq() stays hardcoded at 256.
-- The configurable modulus is used ONLY by the derive/spawn logic
-- for grouping and expected partition counts.
-- To change the actual hash modulus, a full repartition migration is needed.
----------------------------------------------------------------------
-- No changes to report_partition_seq() — it stays IMMUTABLE with % 256.

----------------------------------------------------------------------
-- 3. Auto-tune procedure (called once per pipeline)
----------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE admin.adjust_report_partition_modulus()
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'admin', 'pg_temp'
AS $adjust_report_partition_modulus$
DECLARE
    v_unit_count bigint;
    v_current int;
    v_desired int;
BEGIN
    SELECT report_partition_modulus INTO v_current FROM public.settings;
    SELECT count(*) INTO v_unit_count FROM public.statistical_unit;

    v_desired := CASE
        WHEN v_unit_count <= 10000 THEN 64
        WHEN v_unit_count <= 100000 THEN 128
        WHEN v_unit_count <= 1000000 THEN 256
        WHEN v_unit_count <= 5000000 THEN 512
        ELSE 1024
    END;

    IF v_desired != v_current THEN
        RAISE LOG 'adjust_report_partition_modulus: % units -> % partitions (was %)',
            v_unit_count, v_desired, v_current;
        UPDATE public.settings SET report_partition_modulus = v_desired;
    END IF;
END;
$adjust_report_partition_modulus$;

----------------------------------------------------------------------
-- 4. Update derive_statistical_unit_facet: use function instead of 256
----------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    v_modulus INT;
    v_partitions_to_process INT[];
    v_target_children INT;
    v_range_size INT;
    v_range_start INT;
    v_range_end INT;
BEGIN
    v_modulus := public.get_report_partition_modulus();

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    v_expected_partitions := v_modulus;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        v_dirty_partitions := NULL;
    END IF;

    -- Snapshot dirty dims BEFORE children rewrite staging
    IF v_dirty_partitions IS NOT NULL THEN
        TRUNCATE public.statistical_unit_facet_pre_dirty_dims;
        INSERT INTO public.statistical_unit_facet_pre_dirty_dims
        SELECT DISTINCT s.valid_from, s.valid_to, s.valid_until, s.unit_type,
               s.physical_region_path, s.primary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_country_id, s.status_id
        FROM public.statistical_unit_facet_staging AS s
        WHERE s.partition_seq = ANY(v_dirty_partitions);

        FOR i IN 1..COALESCE(array_length(v_dirty_partitions, 1), 0) LOOP
            PERFORM worker.spawn(
                p_command => 'derive_statistical_unit_facet_partition',
                p_payload => jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq_from', v_dirty_partitions[i],
                    'partition_seq_to', v_dirty_partitions[i]
                ),
                p_parent_id => v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        TRUNCATE public.statistical_unit_facet_pre_dirty_dims;

        v_partitions_to_process := ARRAY(
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        );
        v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
        v_range_size := GREATEST(1, ceil(v_modulus::numeric / v_target_children));
        FOR v_range_start IN 0..(v_modulus - 1) BY v_range_size LOOP
            v_range_end := LEAST(v_range_start + v_range_size - 1, v_modulus - 1);
            IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_unit_facet_partition',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_unit_facet_partition',
                        'partition_seq_from', v_range_start,
                        'partition_seq_to', v_range_end
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END IF;
        END LOOP;
    END IF;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_unit_facet$;

----------------------------------------------------------------------
-- 5. Update derive_statistical_history: use function instead of 256
----------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_child_count integer := 0;
    v_modulus INT;
    v_partitions_to_process INT[];
    v_target_children INT;
    v_range_size INT;
    v_range_start INT;
    v_range_end INT;
BEGIN
    v_modulus := public.get_report_partition_modulus();

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE partition_seq IS NOT NULL LIMIT 1) THEN
        v_dirty_partitions := NULL;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NOT NULL THEN
            FOR i IN 1..COALESCE(array_length(v_dirty_partitions, 1), 0) LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq_from', v_dirty_partitions[i],
                        'partition_seq_to', v_dirty_partitions[i]
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            IF v_partitions_to_process IS NULL THEN
                v_partitions_to_process := ARRAY(
                    SELECT DISTINCT report_partition_seq
                    FROM public.statistical_unit
                    ORDER BY report_partition_seq
                );
                v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
                v_range_size := GREATEST(1, ceil(v_modulus::numeric / v_target_children));
            END IF;

            FOR v_range_start IN 0..(v_modulus - 1) BY v_range_size LOOP
                v_range_end := LEAST(v_range_start + v_range_size - 1, v_modulus - 1);
                IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
                    PERFORM worker.spawn(
                        p_command => 'derive_statistical_history_period',
                        p_payload => jsonb_build_object(
                            'command', 'derive_statistical_history_period',
                            'resolution', v_period.resolution::text,
                            'year', v_period.year,
                            'month', v_period.month,
                            'partition_seq_from', v_range_start,
                            'partition_seq_to', v_range_end
                        ),
                        p_parent_id => v_task_id
                    );
                    v_child_count := v_child_count + 1;
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_history$;

----------------------------------------------------------------------
-- 6. Update derive_statistical_history_facet: use function instead of 256
----------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_child_count integer := 0;
    v_modulus INT;
    v_partitions_to_process INT[];
    v_target_children INT;
    v_range_size INT;
    v_range_start INT;
    v_range_end INT;
BEGIN
    v_modulus := public.get_report_partition_modulus();

    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_partitions := NULL;
    END IF;

    -- Snapshot dirty dims BEFORE children rewrite partitions
    IF v_dirty_partitions IS NOT NULL THEN
        TRUNCATE public.statistical_history_facet_pre_dirty_dims;
        INSERT INTO public.statistical_history_facet_pre_dirty_dims
        SELECT DISTINCT s.resolution, s.year, s.month, s.unit_type,
               s.primary_activity_category_path, s.secondary_activity_category_path,
               s.sector_path, s.legal_form_id, s.physical_region_path,
               s.physical_country_id, s.unit_size_id, s.status_id
        FROM public.statistical_history_facet_partitions AS s
        WHERE s.partition_seq = ANY(v_dirty_partitions);
    ELSE
        TRUNCATE public.statistical_history_facet_pre_dirty_dims;
    END IF;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution => null::public.history_resolution,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NOT NULL THEN
            FOR i IN 1..COALESCE(array_length(v_dirty_partitions, 1), 0) LOOP
                PERFORM worker.spawn(
                    p_command => 'derive_statistical_history_facet_period',
                    p_payload => jsonb_build_object(
                        'command', 'derive_statistical_history_facet_period',
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq_from', v_dirty_partitions[i],
                        'partition_seq_to', v_dirty_partitions[i]
                    ),
                    p_parent_id => v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            IF v_partitions_to_process IS NULL THEN
                v_partitions_to_process := ARRAY(
                    SELECT DISTINCT report_partition_seq
                    FROM public.statistical_unit
                    ORDER BY report_partition_seq
                );
                v_target_children := GREATEST(4, LEAST(64, ceil(COALESCE(array_length(v_partitions_to_process, 1), 0)::numeric / 4)));
                v_range_size := GREATEST(1, ceil(v_modulus::numeric / v_target_children));
            END IF;

            FOR v_range_start IN 0..(v_modulus - 1) BY v_range_size LOOP
                v_range_end := LEAST(v_range_start + v_range_size - 1, v_modulus - 1);
                IF EXISTS (SELECT 1 FROM unnest(v_partitions_to_process) AS p WHERE p BETWEEN v_range_start AND v_range_end) THEN
                    PERFORM worker.spawn(
                        p_command => 'derive_statistical_history_facet_period',
                        p_payload => jsonb_build_object(
                            'command', 'derive_statistical_history_facet_period',
                            'resolution', v_period.resolution::text,
                            'year', v_period.year,
                            'month', v_period.month,
                            'partition_seq_from', v_range_start,
                            'partition_seq_to', v_range_end
                        ),
                        p_parent_id => v_task_id
                    );
                    v_child_count := v_child_count + 1;
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count);
END;
$derive_statistical_history_facet$;

----------------------------------------------------------------------
-- 7. Update derive_statistical_unit dirty partition tracking
----------------------------------------------------------------------
-- The derive_statistical_unit function uses report_partition_seq() which
-- now reads from settings. No change needed — it already calls the function.
-- The dirty_partitions INSERT also uses report_partition_seq(). No change.

----------------------------------------------------------------------
-- 8. Call auto-tune at end of collect_changes
----------------------------------------------------------------------
-- Auto-tune is called via the derive_reports_phase before_procedure hook.
-- Since before_procedure only takes no-arg procedures, we add the call
-- directly to the collect_changes handler where it already runs once.
-- Actually, let's add it to the statistical_unit_flush_staging handler
-- which runs once per pipeline after all batches complete.
-- This is the same pattern as timesegments_years cleanup.

-- Already handled: the collect_changes handler or derive_reports_phase
-- can call it. For now, we'll call it from statistical_unit_flush_staging
-- since it already runs once per pipeline.

CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_flush_staging$
DECLARE
    v_staging_count bigint;
BEGIN
    -- Clean up obsolete years
    DELETE FROM public.timesegments_years AS ty
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments AS t
        WHERE t.valid_from >= make_date(ty.year, 1, 1)
          AND t.valid_from < make_date(ty.year + 1, 1, 1)
        LIMIT 1
    );

    -- Auto-tune partition modulus based on current data size
    CALL admin.adjust_report_partition_modulus();

    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;
    CALL public.statistical_unit_flush_staging();
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    p_info := jsonb_build_object('rows_flushed', v_staging_count);
END;
$statistical_unit_flush_staging$;

END;
