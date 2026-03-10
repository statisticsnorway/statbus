-- Down Migration 20260309201135: remove_dead_derive_statistical_unit_impl_and_continue
-- Restores the dead code and get_enterprise_closed_groups function.
BEGIN;

-- Restore batches_per_wave column
ALTER TABLE worker.command_registry ADD COLUMN IF NOT EXISTS batches_per_wave INTEGER;
UPDATE worker.command_registry SET batches_per_wave = 10 WHERE command = 'derive_statistical_unit';

-- Restore command_registry entry for _continue
INSERT INTO worker.command_registry (command, handler_procedure, queue, phase)
VALUES ('derive_statistical_unit_continue', 'worker.derive_statistical_unit_continue', 'analytics', 'is_deriving_statistical_units')
ON CONFLICT DO NOTHING;

-- Restore get_enterprise_closed_groups
CREATE OR REPLACE FUNCTION public.get_enterprise_closed_groups()
 RETURNS TABLE(group_id integer, enterprise_ids integer[], enterprise_count integer, legal_unit_ids integer[], legal_unit_count integer, establishment_ids integer[], establishment_count integer, total_unit_count integer)
 LANGUAGE sql
 STABLE
AS $get_enterprise_closed_groups$
WITH RECURSIVE
-- Build enterprise connectivity graph from LU temporal data
enterprise_edges AS (
    SELECT DISTINCT a.enterprise_id AS from_en, b.enterprise_id AS to_en
    FROM public.legal_unit a
    JOIN public.legal_unit b ON a.id = b.id
    WHERE a.enterprise_id IS NOT NULL AND b.enterprise_id IS NOT NULL
    UNION
    SELECT id, id FROM public.enterprise
),
-- Compute transitive closure
transitive_closure(from_en, to_en) AS (
    SELECT from_en, to_en FROM enterprise_edges
    UNION
    SELECT tc.from_en, e.to_en
    FROM transitive_closure tc
    JOIN enterprise_edges e ON tc.to_en = e.from_en
),
-- Assign group_id = minimum reachable enterprise_id
enterprise_to_group AS (
    SELECT from_en AS enterprise_id, MIN(to_en) AS group_id
    FROM transitive_closure
    GROUP BY from_en
),
-- Collect per group
group_enterprises AS (
    SELECT
        group_id,
        array_agg(DISTINCT enterprise_id ORDER BY enterprise_id) AS enterprise_ids,
        COUNT(DISTINCT enterprise_id)::INT AS enterprise_count
    FROM enterprise_to_group
    GROUP BY group_id
),
group_legal_units AS (
    SELECT
        eg.group_id,
        array_agg(DISTINCT lu.id ORDER BY lu.id) AS legal_unit_ids,
        COUNT(DISTINCT lu.id)::INT AS legal_unit_count
    FROM enterprise_to_group eg
    JOIN public.legal_unit lu ON lu.enterprise_id = eg.enterprise_id
    GROUP BY eg.group_id
),
group_establishments AS (
    SELECT
        eg.group_id,
        array_agg(DISTINCT es.id ORDER BY es.id) AS establishment_ids,
        COUNT(DISTINCT es.id)::INT AS establishment_count
    FROM enterprise_to_group eg
    LEFT JOIN public.legal_unit lu ON lu.enterprise_id = eg.enterprise_id
    LEFT JOIN public.establishment es ON
        es.enterprise_id = eg.enterprise_id OR es.legal_unit_id = lu.id
    WHERE es.id IS NOT NULL
    GROUP BY eg.group_id
)
SELECT
    ge.group_id,
    ge.enterprise_ids,
    ge.enterprise_count,
    COALESCE(glu.legal_unit_ids, ARRAY[]::INT[]) AS legal_unit_ids,
    COALESCE(glu.legal_unit_count, 0) AS legal_unit_count,
    COALESCE(ges.establishment_ids, ARRAY[]::INT[]) AS establishment_ids,
    COALESCE(ges.establishment_count, 0) AS establishment_count,
    (ge.enterprise_count + COALESCE(glu.legal_unit_count, 0) + COALESCE(ges.establishment_count, 0))::INT AS total_unit_count
FROM group_enterprises ge
LEFT JOIN group_legal_units glu ON glu.group_id = ge.group_id
LEFT JOIN group_establishments ges ON ges.group_id = ge.group_id
ORDER BY ge.group_id;
$get_enterprise_closed_groups$;

-- Restore get_closed_group_batches with bridge fallback via get_enterprise_closed_groups
DROP FUNCTION IF EXISTS public.get_closed_group_batches(integer, int4multirange, int4multirange, int4multirange, integer, integer);

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
            LEFT JOIN public.establishment AS es ON es.legal_unit_id = lu.id
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

-- Restore derive_statistical_unit_impl
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit_impl(
    p_establishment_id_ranges int4multirange DEFAULT NULL,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL,
    p_enterprise_id_ranges int4multirange DEFAULT NULL,
    p_valid_from date DEFAULT NULL,
    p_valid_until date DEFAULT NULL,
    p_task_id bigint DEFAULT NULL,
    p_batch_offset integer DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit_impl$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_batches_per_wave INT;
    v_has_more BOOLEAN := FALSE;
BEGIN
    -- Get batches_per_wave setting from command_registry
    SELECT COALESCE(batches_per_wave, 10) INTO v_batches_per_wave
    FROM worker.command_registry
    WHERE command = 'derive_statistical_unit';

    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Priority for children: same as current task (will run next due to structured concurrency)
    v_child_priority := nextval('public.worker_task_priority_seq');

    -- SYNC POINT: Run ANALYZE on derived tables if this is a continuation (offset > 0)
    IF p_batch_offset > 0 THEN
        RAISE DEBUG 'derive_statistical_unit_impl: Running ANALYZE sync point (offset=%)', p_batch_offset;
        CALL public.analyze_derived_tables();
    END IF;

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children with offset/limit
        -- Request one extra batch to detect if there's more
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_offset := p_batch_offset,
                p_limit := v_batches_per_wave + 1  -- +1 to detect more
            )
        LOOP
            -- Check if we've processed enough for this wave
            IF v_batch_count >= v_batches_per_wave THEN
                v_has_more := TRUE;
                EXIT;  -- Stop, don't process extra batch
            END IF;

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

        -- Spawn batch children for affected groups with offset/limit
        -- Request one extra batch to detect if there's more
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size := 1000,
                p_establishment_id_ranges := NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges := NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges := NULLIF(p_enterprise_id_ranges, '{}'::int4multirange),
                p_offset := p_batch_offset,
                p_limit := v_batches_per_wave + 1  -- +1 to detect more
            )
        LOOP
            -- Check if we've processed enough for this wave
            IF v_batch_count >= v_batches_per_wave THEN
                v_has_more := TRUE;
                EXIT;  -- Stop, don't process extra batch
            END IF;

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

        -- If no batches were created but we have explicit IDs, spawn a cleanup-only batch
        IF v_batch_count = 0 AND p_batch_offset = 0 AND (
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
            RAISE DEBUG 'derive_statistical_unit_impl: No groups matched, spawned cleanup-only batch';
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit_impl: Spawned % batch children (offset=%, has_more=%)', v_batch_count, p_batch_offset, v_has_more;

    -- If there are more batches, enqueue continuation as uncle (NOT deduplicated)
    IF v_has_more THEN
        -- Enqueue continuation command with next offset (runs after current children complete)
        INSERT INTO worker.tasks (command, priority, payload)
        VALUES (
            'derive_statistical_unit_continue',  -- Different command, no deduplication conflict
            v_child_priority,  -- Same priority - runs after this task's children complete
            jsonb_build_object(
                'command', 'derive_statistical_unit_continue',
                'establishment_id_ranges', p_establishment_id_ranges::text,
                'legal_unit_id_ranges', p_legal_unit_id_ranges::text,
                'enterprise_id_ranges', p_enterprise_id_ranges::text,
                'valid_from', p_valid_from,
                'valid_until', p_valid_until,
                'batch_offset', p_batch_offset + v_batches_per_wave
            )
        );
        RAISE DEBUG 'derive_statistical_unit_impl: Enqueued continuation with offset=%', p_batch_offset + v_batches_per_wave;
    ELSE
        -- Final wave: run final ANALYZE and enqueue derive_reports

        -- Refresh derived data (used flags) - always full refreshes, run synchronously
        PERFORM public.activity_category_used_derive();
        PERFORM public.region_used_derive();
        PERFORM public.sector_used_derive();
        PERFORM public.data_source_used_derive();
        PERFORM public.legal_form_used_derive();
        PERFORM public.country_used_derive();

        -- Enqueue derive_reports (runs after all statistical_unit work completes)
        PERFORM worker.enqueue_derive_reports(
            p_valid_from := p_valid_from,
            p_valid_until := p_valid_until
        );

        -- Run final ANALYZE before derive_reports
        CALL public.analyze_derived_tables();

        RAISE DEBUG 'derive_statistical_unit_impl: Final wave complete, enqueued derive_reports';
    END IF;
END;
$derive_statistical_unit_impl$;

-- Restore derive_statistical_unit_continue procedure
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_continue(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_continue$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_batch_offset int = COALESCE((payload->>'batch_offset')::int, 0);
    v_task_id BIGINT;
BEGIN
    -- Get current task ID from the tasks table (the one being processed)
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY processed_at DESC NULLS LAST, id DESC
    LIMIT 1;

    -- Call the impl function with the batch_offset from payload
    PERFORM worker.derive_statistical_unit_impl(
        p_establishment_id_ranges := v_establishment_id_ranges,
        p_legal_unit_id_ranges := v_legal_unit_id_ranges,
        p_enterprise_id_ranges := v_enterprise_id_ranges,
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until,
        p_task_id := v_task_id,
        p_batch_offset := v_batch_offset
    );
END;
$derive_statistical_unit_continue$;

END;
