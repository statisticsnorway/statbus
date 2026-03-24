-- Migration 20260324224225: incremental_timesegments_years_maintenance
--
-- Fix: timesegments_years_refresh_concurrent scans 3.1M timesegments (617ms)
-- per batch, called 65 times per pipeline = 40s wasted.
--
-- Principled fix: record years incrementally during timesegments_refresh
-- (O(batch_size)), cleanup obsolete years once per pipeline (1.2ms).
BEGIN;

-- 1. Add incremental year recording to timesegments_refresh
CREATE OR REPLACE PROCEDURE public.timesegments_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $timesegments_refresh$
DECLARE
    v_is_partial_refresh BOOLEAN;
    v_establishment_ids INT[]; v_legal_unit_ids INT[]; v_enterprise_ids INT[]; v_power_group_ids INT[];
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);
    IF NOT v_is_partial_refresh THEN
        ANALYZE public.timepoints;
        DELETE FROM public.timesegments;
        INSERT INTO public.timesegments SELECT * FROM public.timesegments_def;
        ANALYZE public.timesegments;
        -- Full refresh: record all years from the new timesegments
        INSERT INTO public.timesegments_years (year)
        SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
        FROM public.timesegments AS t
        ON CONFLICT (year) DO NOTHING;
    ELSE
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
        IF p_power_group_id_ranges IS NOT NULL THEN
            v_power_group_ids := public.int4multirange_to_array(p_power_group_id_ranges);
            DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
            INSERT INTO public.timesegments SELECT * FROM public.timesegments_def WHERE unit_type = 'power_group' AND unit_id = ANY(v_power_group_ids);
        END IF;
        -- Partial refresh: record years from the batch's timesegments (O(batch_size))
        -- Handles historical data: extracts actual years from whatever dates are processed.
        INSERT INTO public.timesegments_years (year)
        SELECT DISTINCT EXTRACT(year FROM t.valid_from)::int
        FROM public.timesegments AS t
        WHERE (p_establishment_id_ranges IS NOT NULL AND t.unit_type = 'establishment' AND t.unit_id = ANY(v_establishment_ids))
           OR (p_legal_unit_id_ranges IS NOT NULL AND t.unit_type = 'legal_unit' AND t.unit_id = ANY(v_legal_unit_ids))
           OR (p_enterprise_id_ranges IS NOT NULL AND t.unit_type = 'enterprise' AND t.unit_id = ANY(v_enterprise_ids))
           OR (p_power_group_id_ranges IS NOT NULL AND t.unit_type = 'power_group' AND t.unit_id = ANY(v_power_group_ids))
        ON CONFLICT (year) DO NOTHING;
    END IF;
END;
$timesegments_refresh$;

-- 2. Remove per-batch timesegments_years_refresh_concurrent call
CREATE OR REPLACE PROCEDURE worker.statistical_unit_refresh_batch(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_refresh_batch$
DECLARE
    v_batch_seq INT := (payload->>'batch_seq')::INT;
    v_enterprise_ids INT[];
    v_legal_unit_ids INT[];
    v_establishment_ids INT[];
    v_power_group_ids INT[];
    v_enterprise_id_ranges int4multirange;
    v_legal_unit_id_ranges int4multirange;
    v_establishment_id_ranges int4multirange;
    v_power_group_id_ranges int4multirange;
    v_changed_est_ranges int4multirange;
    v_changed_lu_ranges int4multirange;
    v_changed_en_ranges int4multirange;
    v_propagated_lu_ranges int4multirange;
    v_propagated_en_ranges int4multirange;
    v_effective_est int4multirange;
    v_effective_lu int4multirange;
    v_effective_en int4multirange;
    v_batch_est_count INT;
    v_batch_lu_count INT;
    v_batch_en_count INT;
    v_effective_est_count INT;
    v_effective_lu_count INT;
    v_effective_en_count INT;
BEGIN
    IF jsonb_typeof(payload->'enterprise_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_enterprise_ids FROM jsonb_array_elements_text(payload->'enterprise_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'legal_unit_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_legal_unit_ids FROM jsonb_array_elements_text(payload->'legal_unit_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'establishment_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_establishment_ids FROM jsonb_array_elements_text(payload->'establishment_ids') AS value;
    END IF;
    IF jsonb_typeof(payload->'power_group_ids') = 'array' THEN
        SELECT array_agg(value::INT) INTO v_power_group_ids FROM jsonb_array_elements_text(payload->'power_group_ids') AS value;
    END IF;

    v_enterprise_id_ranges := public.array_to_int4multirange(v_enterprise_ids);
    v_legal_unit_id_ranges := public.array_to_int4multirange(v_legal_unit_ids);
    v_establishment_id_ranges := public.array_to_int4multirange(v_establishment_ids);
    v_power_group_id_ranges := public.array_to_int4multirange(v_power_group_ids);

    v_batch_est_count := COALESCE(array_length(v_establishment_ids, 1), 0);
    v_batch_lu_count := COALESCE(array_length(v_legal_unit_ids, 1), 0);
    v_batch_en_count := COALESCE(array_length(v_enterprise_ids, 1), 0);

    RAISE DEBUG 'statistical_unit_refresh_batch: batch % with % enterprises, % legal_units, % establishments, % power_groups',
        v_batch_seq, v_batch_en_count, v_batch_lu_count, v_batch_est_count,
        COALESCE(array_length(v_power_group_ids, 1), 0);

    v_changed_est_ranges := (payload->>'changed_establishment_id_ranges')::int4multirange;
    v_changed_lu_ranges  := (payload->>'changed_legal_unit_id_ranges')::int4multirange;
    v_changed_en_ranges  := (payload->>'changed_enterprise_id_ranges')::int4multirange;

    IF v_changed_est_ranges IS NULL
       AND v_changed_lu_ranges IS NULL
       AND v_changed_en_ranges IS NULL
    THEN
        v_effective_est := v_establishment_id_ranges;
        v_effective_lu  := v_legal_unit_id_ranges;
        v_effective_en  := v_enterprise_id_ranges;

        RAISE DEBUG 'statistical_unit_refresh_batch: batch % no change ranges, using full batch ranges',
            v_batch_seq;
    ELSE
        v_effective_est := NULLIF(
            v_establishment_id_ranges * COALESCE(v_changed_est_ranges, '{}'::int4multirange),
            '{}'::int4multirange
        );

        SELECT range_agg(int4range(es.legal_unit_id, es.legal_unit_id, '[]'))
          INTO v_propagated_lu_ranges
          FROM public.establishment AS es
         WHERE es.id <@ COALESCE(v_changed_est_ranges, '{}'::int4multirange)
           AND es.legal_unit_id IS NOT NULL;

        v_effective_lu := NULLIF(
            v_legal_unit_id_ranges * (
                COALESCE(v_changed_lu_ranges, '{}'::int4multirange)
              + COALESCE(v_propagated_lu_ranges, '{}'::int4multirange)
            ),
            '{}'::int4multirange
        );

        SELECT range_agg(int4range(lu.enterprise_id, lu.enterprise_id, '[]'))
          INTO v_propagated_en_ranges
          FROM public.legal_unit AS lu
         WHERE lu.id <@ COALESCE(v_effective_lu, '{}'::int4multirange)
           AND lu.enterprise_id IS NOT NULL;

        v_effective_en := NULLIF(
            v_enterprise_id_ranges * (
                COALESCE(v_changed_en_ranges, '{}'::int4multirange)
              + COALESCE(v_propagated_en_ranges, '{}'::int4multirange)
            ),
            '{}'::int4multirange
        );

        v_effective_est_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_effective_est, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
        v_effective_lu_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_effective_lu, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
        v_effective_en_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_effective_en, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);

        RAISE LOG 'statistical_unit_refresh_batch: batch % directional propagation: ES %/% LU %/% EN %/%',
            v_batch_seq,
            v_effective_est_count, v_batch_est_count,
            v_effective_lu_count, v_batch_lu_count,
            v_effective_en_count, v_batch_en_count;
    END IF;

    CALL public.timepoints_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges,
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
    CALL public.timesegments_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges,
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
    -- timesegments_years_refresh_concurrent removed: years are now maintained
    -- incrementally by timesegments_refresh, with cleanup in flush_staging.

    IF v_effective_est IS NOT NULL THEN
        CALL public.timeline_establishment_refresh(p_unit_id_ranges => v_effective_est);
    END IF;
    IF v_effective_lu IS NOT NULL THEN
        CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => v_effective_lu);
    END IF;
    IF v_effective_en IS NOT NULL THEN
        CALL public.timeline_enterprise_refresh(p_unit_id_ranges => v_effective_en);
    END IF;
    IF v_power_group_id_ranges IS NOT NULL THEN
        CALL public.timeline_power_group_refresh(p_unit_id_ranges => v_power_group_id_ranges);
    END IF;

    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => COALESCE(v_effective_est, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_effective_lu, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_effective_en, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );

    p_info := jsonb_build_object(
        'batch_est_count', v_batch_est_count,
        'batch_lu_count', v_batch_lu_count,
        'batch_en_count', v_batch_en_count
    );
END;
$statistical_unit_refresh_batch$;

-- 3. Add cheap year cleanup to flush_staging (runs once after all batches)
CREATE OR REPLACE PROCEDURE worker.statistical_unit_flush_staging(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_flush_staging$
DECLARE
    v_staging_count bigint;
BEGIN
    -- Clean up obsolete years (1.2ms — uses composite index via date range check)
    DELETE FROM public.timesegments_years AS ty
    WHERE NOT EXISTS (
        SELECT 1 FROM public.timesegments AS t
        WHERE t.valid_from >= make_date(ty.year, 1, 1)
          AND t.valid_from < make_date(ty.year + 1, 1, 1)
        LIMIT 1
    );

    SELECT count(*) INTO v_staging_count FROM public.statistical_unit_staging;
    CALL public.statistical_unit_flush_staging();
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    p_info := jsonb_build_object('rows_flushed', v_staging_count);
END;
$statistical_unit_flush_staging$;

END;
