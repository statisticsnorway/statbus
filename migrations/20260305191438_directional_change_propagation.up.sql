-- Migration 20260305191438: directional_change_propagation
--
-- Optimization: In partial refresh, pass the original change ranges from
-- collect_changes through to each batch child. The batch child then uses
-- directional propagation to only refresh timelines for units whose source
-- data actually changed, rather than refreshing ALL units in the closed group.
--
-- Changes propagate strictly upward:
--   ES change → timeline_establishment(ES) + timeline_legal_unit(parent LU) + timeline_enterprise(parent EN)
--   LU change → timeline_legal_unit(LU) + timeline_enterprise(parent EN)
--   EN change → timeline_enterprise(EN)
--
-- get_closed_group_batches is UNCHANGED — all units in affected groups still
-- enter every batch for timepoints/timesegments/statistical_unit_refresh.
-- Only the timeline_*_refresh calls are scoped down.

BEGIN;

-- === 1. derive_statistical_unit: pass changed_* keys in partial refresh payloads ===

CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_power_group_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    v_orphan_power_group_ids INT[];
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
    v_power_group_count INT := 0;
    v_partition_count INT;
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all partitions
        -- NOTE: No changed_* keys — children fall back to full batch refresh
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
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

        -- PG batching: split all power groups across analytics_partition_count batches
        v_power_group_ids := ARRAY(SELECT id FROM public.power_group ORDER BY id);
        v_power_group_count := COALESCE(array_length(v_power_group_ids, 1), 0);
        IF v_power_group_count > 0 THEN
            SELECT analytics_partition_count INTO v_partition_count FROM public.settings;
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / v_partition_count));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command := 'statistical_unit_refresh_batch',
                    p_payload := jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id := p_task_id,
                    p_priority := v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));
        v_power_group_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_power_group_id_ranges, '{}'::int4multirange)) AS t(r));

        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs', array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs', array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs', array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan power_group IDs', array_length(v_orphan_power_group_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
            END IF;
        END IF;

        -- BATCHING: EST/LU/EN use closed-group batches
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0
           OR COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0
           OR COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
                p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
                p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
            );
            -- Dirty partition tracking
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings))
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;

            -- Spawn batch children with changed_* keys for directional propagation
            FOR v_batch IN SELECT * FROM _batches LOOP
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
                        'valid_until', p_valid_until,
                        -- Original change ranges for directional propagation
                        'changed_establishment_id_ranges', p_establishment_id_ranges::text,
                        'changed_legal_unit_id_ranges', p_legal_unit_id_ranges::text,
                        'changed_enterprise_id_ranges', p_enterprise_id_ranges::text
                    ),
                    p_parent_id := p_task_id,
                    p_priority := v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        -- PG batch: split affected power_group IDs across analytics_partition_count batches
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);

            -- Dirty partition tracking for PG
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq('power_group', pg_id, (SELECT analytics_partition_count FROM public.settings))
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            SELECT analytics_partition_count INTO v_partition_count FROM public.settings;
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / v_partition_count));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command := 'statistical_unit_refresh_batch',
                    p_payload := jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id := p_task_id,
                    p_priority := v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    -- Create/update Phase 1 row with unit counts
    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         v_power_group_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    -- Pre-create Phase 2 row with counts (pending, visible to user before phase 2 starts)
    INSERT INTO worker.pipeline_progress
        (phase, step, total, completed,
         affected_establishment_count, affected_legal_unit_count, affected_enterprise_count,
         affected_power_group_count, updated_at)
    VALUES
        ('is_deriving_reports', NULL, 0, 0,
         v_establishment_count, v_legal_unit_count, v_enterprise_count,
         v_power_group_count, clock_timestamp())
    ON CONFLICT (phase) DO UPDATE SET
        affected_establishment_count = EXCLUDED.affected_establishment_count,
        affected_legal_unit_count = EXCLUDED.affected_legal_unit_count,
        affected_enterprise_count = EXCLUDED.affected_enterprise_count,
        affected_power_group_count = EXCLUDED.affected_power_group_count,
        updated_at = EXCLUDED.updated_at;

    -- Notify frontend with accurate counts
    PERFORM worker.notify_pipeline_progress();

    -- Refresh derived data (used flags)
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- Pipeline routing: always flush then reports (no more derive_power_groups in pipeline)
    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base := p_round_priority_base
    );
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_round_priority_base := p_round_priority_base
    );
END;
$function$;


-- === 2. statistical_unit_refresh_batch: directional change propagation ===

CREATE OR REPLACE PROCEDURE worker.statistical_unit_refresh_batch(IN payload jsonb)
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

    -- Timepoints and timesegments always use the full batch ranges
    -- (all units in the closed group need correct time boundaries)
    CALL public.timepoints_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
    CALL public.timesegments_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
    CALL public.timesegments_years_refresh_concurrent();

    -- === DIRECTIONAL PROPAGATION for timeline refreshes ===
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

    -- statistical_unit_refresh always uses full batch ranges
    -- (all units in the closed group need stat_unit rows)
    CALL public.statistical_unit_refresh(
        p_establishment_id_ranges => COALESCE(v_establishment_id_ranges, '{}'::int4multirange),
        p_legal_unit_id_ranges => COALESCE(v_legal_unit_id_ranges, '{}'::int4multirange),
        p_enterprise_id_ranges => COALESCE(v_enterprise_id_ranges, '{}'::int4multirange),
        p_power_group_id_ranges => COALESCE(v_power_group_id_ranges, '{}'::int4multirange)
    );
END;
$statistical_unit_refresh_batch$;

END;
