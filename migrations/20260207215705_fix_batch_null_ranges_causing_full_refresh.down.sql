-- Down Migration 20260207215705: fix_batch_null_ranges_causing_full_refresh
BEGIN;

-- Restore original procedure that passes NULL ranges directly
CREATE OR REPLACE PROCEDURE worker.statistical_unit_refresh_batch(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $statistical_unit_refresh_batch$
DECLARE
    v_batch_seq INT := (payload->>'batch_seq')::INT;
    v_enterprise_ids INT[];
    v_legal_unit_ids INT[];
    v_establishment_ids INT[];
    v_enterprise_id_ranges int4multirange;
    v_legal_unit_id_ranges int4multirange;
    v_establishment_id_ranges int4multirange;
BEGIN
    -- Extract batch IDs from payload (no more explicit_*_ids merging)
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

    -- Call the refresh procedures for this batch
    CALL public.timepoints_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges
    );

    CALL public.timesegments_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges
    );

    -- Use concurrent-safe version for years
    CALL public.timesegments_years_refresh_concurrent();

    CALL public.timeline_establishment_refresh(p_unit_id_ranges => v_establishment_id_ranges);
    CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => v_legal_unit_id_ranges);
    CALL public.timeline_enterprise_refresh(p_unit_id_ranges => v_enterprise_id_ranges);

    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => v_establishment_id_ranges,
        p_legal_unit_id_ranges => v_legal_unit_id_ranges,
        p_enterprise_id_ranges => v_enterprise_id_ranges
    );
END;
$statistical_unit_refresh_batch$;

END;
