-- Migration 20260309195139: optimize_get_closed_group_batches_replace_recursive_with_bridge_detection
--
-- Problem: get_closed_group_batches uses recursive transitive closure to find
-- connected enterprise components. When many IDs are affected (e.g., 763K LUs),
-- the recursive CTE processes ~1.1M enterprises and takes 2+ hours.
--
-- Fix: Replace recursive CTE with bridge detection + parallel hash joins.
-- Bridge detection: find LUs with different enterprise_ids across time periods
-- (the only source of enterprise connectivity). If no bridges exist (common),
-- skip graph computation entirely — group_id = enterprise_id.
--
-- Performance: 2h 21m → ~3 seconds (Norway, 1.1M enterprises).
--
-- Also changes signature from integer[] to int4multirange to avoid the
-- expensive array expansion in the caller (derive_statistical_unit).
BEGIN;

-- Drop the old function (different parameter types = different function)
DROP FUNCTION IF EXISTS public.get_closed_group_batches(integer, integer[], integer[], integer[], integer, integer);

CREATE FUNCTION public.get_closed_group_batches(
    p_target_batch_size integer DEFAULT 1000,
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_offset integer DEFAULT 0,
    p_limit integer DEFAULT NULL
)
RETURNS TABLE(
    batch_seq integer,
    group_ids integer[],
    enterprise_ids integer[],
    legal_unit_ids integer[],
    establishment_ids integer[],
    total_unit_count integer,
    has_more boolean
)
LANGUAGE plpgsql
AS $get_closed_group_batches$
DECLARE
    v_current_batch_seq INT := 1;
    v_current_batch_size INT := 0;
    v_group RECORD;
    v_filter_active BOOLEAN;
    v_batches_returned INT := 0;
    v_skipped INT := 0;
    v_has_more BOOLEAN := FALSE;
    v_has_bridges BOOLEAN;
BEGIN
    v_filter_active := (p_establishment_id_ranges IS NOT NULL
                       OR p_legal_unit_id_ranges IS NOT NULL
                       OR p_enterprise_id_ranges IS NOT NULL);

    -- Use temp table to accumulate IDs for batching (O(n) vs O(n²) array concat)
    IF to_regclass('pg_temp._batch_accumulator') IS NOT NULL THEN DROP TABLE _batch_accumulator; END IF;
    CREATE TEMP TABLE _batch_accumulator (
        group_id INT,
        enterprise_id INT,
        legal_unit_id INT,
        establishment_id INT
    ) ON COMMIT DROP;

    -- Bridge detection: check if any LU has different enterprise_ids across
    -- time periods. This is the ONLY source of enterprise connectivity.
    -- A single pass over legal_unit (~0.5s for 1.1M rows).
    SELECT EXISTS(
        SELECT 1
        FROM public.legal_unit
        WHERE enterprise_id IS NOT NULL
        GROUP BY id
        HAVING MIN(enterprise_id) <> MAX(enterprise_id)
        LIMIT 1
    ) INTO v_has_bridges;

    IF v_has_bridges THEN
        -- Rare case: bridges exist. Fall back to full transitive closure
        -- via get_enterprise_closed_groups() which handles this correctly.
        -- This is acceptable because bridges are extremely rare in practice.
        FOR v_group IN
            SELECT
                ecg.group_id,
                ecg.enterprise_ids,
                ecg.legal_unit_ids,
                ecg.establishment_ids,
                ecg.total_unit_count
            FROM public.get_enterprise_closed_groups() AS ecg
            WHERE NOT v_filter_active
               OR ecg.enterprise_ids && ARRAY(
                    SELECT generate_series(lower(r), upper(r)-1)
                    FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS r
                  )
               OR ecg.legal_unit_ids && ARRAY(
                    SELECT generate_series(lower(r), upper(r)-1)
                    FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS r
                  )
               OR ecg.establishment_ids && ARRAY(
                    SELECT generate_series(lower(r), upper(r)-1)
                    FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS r
                  )
            ORDER BY ecg.total_unit_count DESC, ecg.group_id
        LOOP
            IF v_current_batch_size > 0
               AND v_current_batch_size + v_group.total_unit_count > p_target_batch_size
            THEN
                IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
                    v_has_more := TRUE;
                    EXIT;
                END IF;
                IF v_skipped < p_offset THEN
                    v_skipped := v_skipped + 1;
                    v_current_batch_seq := v_current_batch_seq + 1;
                    v_current_batch_size := 0;
                    TRUNCATE _batch_accumulator;
                ELSE
                    SELECT v_current_batch_seq,
                        array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                        array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                        array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                        array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                        v_current_batch_size, FALSE
                    INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                    FROM _batch_accumulator ba;
                    RETURN NEXT;
                    v_batches_returned := v_batches_returned + 1;
                    v_current_batch_seq := v_current_batch_seq + 1;
                    v_current_batch_size := 0;
                    TRUNCATE _batch_accumulator;
                END IF;
            END IF;
            INSERT INTO _batch_accumulator (group_id) VALUES (v_group.group_id);
            INSERT INTO _batch_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
            INSERT INTO _batch_accumulator (legal_unit_id) SELECT UNNEST(v_group.legal_unit_ids);
            INSERT INTO _batch_accumulator (establishment_id) SELECT UNNEST(v_group.establishment_ids);
            v_current_batch_size := v_current_batch_size + v_group.total_unit_count;
        END LOOP;
    ELSE
        -- Common case: no bridges. Every enterprise is its own group.
        -- Use a single parallel hash join query — ~2.3s for 1.1M enterprises.
        -- group_id = enterprise_id since there are no connected components.
        FOR v_group IN
            SELECT
                en.id AS group_id,
                ARRAY[en.id] AS enterprise_ids,
                array_agg(DISTINCT lu.id ORDER BY lu.id)
                    FILTER (WHERE lu.id IS NOT NULL) AS legal_unit_ids,
                array_agg(DISTINCT es.id ORDER BY es.id)
                    FILTER (WHERE es.id IS NOT NULL) AS establishment_ids,
                (1 + COUNT(DISTINCT lu.id) + COUNT(DISTINCT es.id))::INT AS total_unit_count
            FROM public.enterprise AS en
            LEFT JOIN public.legal_unit AS lu ON lu.enterprise_id = en.id
            LEFT JOIN public.establishment AS es
                ON es.legal_unit_id = lu.id OR es.enterprise_id = en.id
            WHERE NOT v_filter_active
               OR en.id <@ COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
               OR lu.id <@ COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
               OR es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
            GROUP BY en.id
            ORDER BY total_unit_count DESC, en.id
        LOOP
            IF v_current_batch_size > 0
               AND v_current_batch_size + v_group.total_unit_count > p_target_batch_size
            THEN
                IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
                    v_has_more := TRUE;
                    EXIT;
                END IF;
                IF v_skipped < p_offset THEN
                    v_skipped := v_skipped + 1;
                    v_current_batch_seq := v_current_batch_seq + 1;
                    v_current_batch_size := 0;
                    TRUNCATE _batch_accumulator;
                ELSE
                    SELECT v_current_batch_seq,
                        array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                        array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                        array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                        array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                        v_current_batch_size, FALSE
                    INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
                    FROM _batch_accumulator ba;
                    RETURN NEXT;
                    v_batches_returned := v_batches_returned + 1;
                    v_current_batch_seq := v_current_batch_seq + 1;
                    v_current_batch_size := 0;
                    TRUNCATE _batch_accumulator;
                END IF;
            END IF;
            INSERT INTO _batch_accumulator (group_id) VALUES (v_group.group_id);
            INSERT INTO _batch_accumulator (enterprise_id) SELECT UNNEST(v_group.enterprise_ids);
            INSERT INTO _batch_accumulator (legal_unit_id) SELECT UNNEST(COALESCE(v_group.legal_unit_ids, ARRAY[]::INT[]));
            INSERT INTO _batch_accumulator (establishment_id) SELECT UNNEST(COALESCE(v_group.establishment_ids, ARRAY[]::INT[]));
            v_current_batch_size := v_current_batch_size + v_group.total_unit_count;
        END LOOP;
    END IF;

    -- Emit final batch
    IF v_current_batch_size > 0 AND NOT v_has_more THEN
        IF p_limit IS NOT NULL AND v_batches_returned >= p_limit THEN
            v_has_more := TRUE;
        ELSIF v_skipped < p_offset THEN
            v_has_more := FALSE;
        ELSE
            SELECT v_current_batch_seq,
                array_agg(DISTINCT ba.group_id ORDER BY ba.group_id) FILTER (WHERE ba.group_id IS NOT NULL),
                array_agg(DISTINCT ba.enterprise_id ORDER BY ba.enterprise_id) FILTER (WHERE ba.enterprise_id IS NOT NULL),
                array_agg(DISTINCT ba.legal_unit_id ORDER BY ba.legal_unit_id) FILTER (WHERE ba.legal_unit_id IS NOT NULL),
                array_agg(DISTINCT ba.establishment_id ORDER BY ba.establishment_id) FILTER (WHERE ba.establishment_id IS NOT NULL),
                v_current_batch_size, FALSE
            INTO batch_seq, group_ids, enterprise_ids, legal_unit_ids, establishment_ids, total_unit_count, has_more
            FROM _batch_accumulator ba;
            RETURN NEXT;
        END IF;
    END IF;
END;
$get_closed_group_batches$;

-- Update derive_statistical_unit to pass multiranges directly
-- instead of expanding to arrays first.
-- Only modifying the partial-refresh path (lines 84-143 of the current function).
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_power_group_id_ranges int4multirange DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL,
    p_task_id bigint DEFAULT NULL,
    p_round_priority_base bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit$
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
        -- Partial refresh: expand multiranges to arrays only for orphan cleanup
        -- (orphan cleanup needs = ANY() which requires arrays)
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
        -- Pass multiranges directly — no array expansion needed here
        IF p_establishment_id_ranges IS NOT NULL
           OR p_legal_unit_id_ranges IS NOT NULL
           OR p_enterprise_id_ranges IS NOT NULL THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_id_ranges := NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges := NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges := NULLIF(p_enterprise_id_ranges, '{}'::int4multirange)
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

            -- Compute effective (directional) counts across all batches for pipeline_progress
            -- Uses directional propagation: only count units in the upward direction from changes
            <<effective_counts>>
            DECLARE
                v_all_batch_est_ranges int4multirange;
                v_all_batch_lu_ranges int4multirange;
                v_all_batch_en_ranges int4multirange;
                v_propagated_lu int4multirange;
                v_propagated_en int4multirange;
                v_eff_est int4multirange;
                v_eff_lu int4multirange;
                v_eff_en int4multirange;
            BEGIN
                v_all_batch_est_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(establishment_ids) AS id FROM _batches) AS t);
                v_all_batch_lu_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(legal_unit_ids) AS id FROM _batches) AS t);
                v_all_batch_en_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(enterprise_ids) AS id FROM _batches) AS t);

                -- Level 1: ES = directly changed ESs ∩ all batches
                v_eff_est := NULLIF(
                    COALESCE(v_all_batch_est_ranges, '{}'::int4multirange)
                    * COALESCE(p_establishment_id_ranges, '{}'::int4multirange),
                    '{}'::int4multirange);

                -- Level 2: LU = (changed LUs + parents of changed ESs) ∩ all batches
                SELECT range_agg(int4range(es.legal_unit_id, es.legal_unit_id, '[]'))
                  INTO v_propagated_lu
                  FROM public.establishment AS es
                 WHERE es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
                   AND es.legal_unit_id IS NOT NULL;
                v_eff_lu := NULLIF(
                    COALESCE(v_all_batch_lu_ranges, '{}'::int4multirange)
                    * (COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_lu, '{}'::int4multirange)),
                    '{}'::int4multirange);

                -- Level 3: EN = (changed ENs + parents of effective LUs) ∩ all batches
                SELECT range_agg(int4range(lu.enterprise_id, lu.enterprise_id, '[]'))
                  INTO v_propagated_en
                  FROM public.legal_unit AS lu
                 WHERE lu.id <@ COALESCE(v_eff_lu, '{}'::int4multirange)
                   AND lu.enterprise_id IS NOT NULL;
                v_eff_en := NULLIF(
                    COALESCE(v_all_batch_en_ranges, '{}'::int4multirange)
                    * (COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_en, '{}'::int4multirange)),
                    '{}'::int4multirange);

                -- Count effective units (not batch totals) for pipeline_progress
                v_establishment_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_est, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_legal_unit_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_lu, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_enterprise_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_en, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
            END effective_counts;

            -- Spawn batch children with changed_* keys for directional propagation
            FOR v_batch IN SELECT * FROM _batches LOOP
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
$derive_statistical_unit$;

END;
