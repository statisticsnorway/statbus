```sql
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
    v_power_group_ids INT[];
    v_enterprise_id_ranges int4multirange;
    v_legal_unit_id_ranges int4multirange;
    v_establishment_id_ranges int4multirange;
    v_power_group_id_ranges int4multirange;
    -- Directional propagation variables
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
    -- Extract batch arrays from payload (all units in the closed group)
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

    -- === DIRECTIONAL PROPAGATION — compute effective ranges BEFORE any refresh calls ===
    -- Extract original change ranges from payload (NULL if absent = full refresh fallback)
    v_changed_est_ranges := (payload->>'changed_establishment_id_ranges')::int4multirange;
    v_changed_lu_ranges  := (payload->>'changed_legal_unit_id_ranges')::int4multirange;
    v_changed_en_ranges  := (payload->>'changed_enterprise_id_ranges')::int4multirange;

    IF v_changed_est_ranges IS NULL
       AND v_changed_lu_ranges IS NULL
       AND v_changed_en_ranges IS NULL
    THEN
        -- No change ranges in payload → full refresh path or backward compat.
        -- Use batch ranges unchanged (current behavior).
        v_effective_est := v_establishment_id_ranges;
        v_effective_lu  := v_legal_unit_id_ranges;
        v_effective_en  := v_enterprise_id_ranges;

        RAISE DEBUG 'statistical_unit_refresh_batch: batch % no change ranges, using full batch ranges',
            v_batch_seq;
    ELSE
        -- === DIRECTIONAL PROPAGATION ===
        -- COALESCE NULLs to empty so intersection/union algebra works cleanly.
        -- NULLIF at the end converts empty results back to NULL for IS NOT NULL guards.

        -- Level 1: ES timelines — only directly changed ESs within this batch
        v_effective_est := NULLIF(
            v_establishment_id_ranges * COALESCE(v_changed_est_ranges, '{}'::int4multirange),
            '{}'::int4multirange
        );

        -- Level 2: LU timelines — directly changed LUs + parents of changed ESs
        -- NOTE: establishment is temporal. An ES can have different legal_unit_ids across
        -- time periods, so this returns ALL historical parent LUs. This is correct —
        -- the LU timeline is rebuilt from all its ESs' timelines.
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

        -- Level 3: EN timelines — directly changed ENs + parents of effective LUs
        -- NOTE: legal_unit is temporal. A LU can have different enterprise_ids across
        -- time periods (that's how closed groups form). This returns ALL historical
        -- parent ENs. MUST NOT filter by time — would miss historical relationships.
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

        -- Log the savings from directional propagation
        v_effective_est_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_effective_est, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
        v_effective_lu_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_effective_lu, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
        v_effective_en_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_effective_en, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);

        RAISE LOG 'statistical_unit_refresh_batch: batch % directional propagation: ES %/% LU %/% EN %/%',
            v_batch_seq,
            v_effective_est_count, v_batch_est_count,
            v_effective_lu_count, v_batch_lu_count,
            v_effective_en_count, v_batch_en_count;
    END IF;

    -- Timepoints/timesegments use BATCH ranges (not effective ranges) because:
    -- timepoints_calculate's CTE chain builds enterprise timepoints from LU periods,
    -- and LU periods from ES periods. Scoping to effective ranges would miss unchanged
    -- LUs/ESs that enterprises depend on (e.g., when an LU moves between enterprises,
    -- the old enterprise needs ALL its remaining LUs' timepoints).
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
    CALL public.timesegments_years_refresh_concurrent();

    -- Timeline refreshes: use effective ranges (scoped by directional propagation)
    IF v_effective_est IS NOT NULL THEN
        CALL public.timeline_establishment_refresh(p_unit_id_ranges => v_effective_est);
    END IF;
    IF v_effective_lu IS NOT NULL THEN
        CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => v_effective_lu);
    END IF;
    IF v_effective_en IS NOT NULL THEN
        CALL public.timeline_enterprise_refresh(p_unit_id_ranges => v_effective_en);
    END IF;
    -- Power groups: independent hierarchy, no propagation needed
    IF v_power_group_id_ranges IS NOT NULL THEN
        CALL public.timeline_power_group_refresh(p_unit_id_ranges => v_power_group_id_ranges);
    END IF;

    -- statistical_unit_refresh: use effective ranges (only units that changed)
    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => COALESCE(v_effective_est, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_effective_lu, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_effective_en, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
END;
$procedure$
```
