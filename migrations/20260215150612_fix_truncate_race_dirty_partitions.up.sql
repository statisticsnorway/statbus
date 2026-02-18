-- Migration 20260215150612: fix_truncate_race_dirty_partitions
--
-- Problem: statistical_unit_facet_reduce does TRUNCATE on dirty_partitions,
-- which clears partitions marked by concurrent/subsequent pipeline cycles.
-- Result: next cycle sees empty dirty list → falls back to full 128-partition refresh.
--
-- Fix: Replace TRUNCATE with targeted DELETE of only the partitions that were processed.
-- The dirty partitions are snapshot'd at the start of derive_statistical_unit_facet
-- and passed through the pipeline payload to reduce.
BEGIN;

-- =====================================================================
-- 1. Update derive_statistical_unit_facet to snapshot dirty partitions
--    into the payload passed to the reduce uncle task
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    v_i INT;
BEGIN
    -- Get own task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- =====================================================================
    -- INTEGRITY CHECK: Ensure partition table is fully populated.
    -- UNLOGGED table loses data on crash; also handles first-run case.
    -- If partition table is incomplete, force a full refresh.
    -- =====================================================================
    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    SELECT COUNT(DISTINCT report_partition_seq) INTO v_expected_partitions
    FROM public.statistical_unit
    WHERE used_for_counting;

    -- Snapshot dirty partitions (atomically read current state)
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        -- Partition table lost data (crash or first run) → force full refresh
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    -- Enqueue reduce task with the snapshot of dirty partitions in payload.
    -- This way reduce knows exactly which partitions to clear from dirty tracking.
    PERFORM worker.enqueue_statistical_unit_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_dirty_partitions => v_dirty_partitions
    );

    -- Spawn partition children
    IF v_dirty_partitions IS NULL THEN
        -- Full refresh: only partitions that have data
        RAISE DEBUG 'derive_statistical_unit_facet: Full refresh — spawning % partition children (populated)',
            v_expected_partitions;
        FOR v_i IN
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        LOOP
            PERFORM worker.spawn(
                p_command := 'derive_statistical_unit_facet_partition',
                p_payload := jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id := v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: only dirty partitions
        RAISE DEBUG 'derive_statistical_unit_facet: Partial refresh — spawning % dirty partition children',
            array_length(v_dirty_partitions, 1);
        FOREACH v_i IN ARRAY v_dirty_partitions LOOP
            PERFORM worker.spawn(
                p_command := 'derive_statistical_unit_facet_partition',
                p_payload := jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id := v_task_id
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit_facet: Spawned % partition children', v_child_count;
END;
$derive_statistical_unit_facet$;


-- =====================================================================
-- 2. Update enqueue_statistical_unit_facet_reduce to accept dirty_partitions
-- =====================================================================
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_facet_reduce(
    p_valid_from date DEFAULT NULL, p_valid_until date DEFAULT NULL,
    p_dirty_partitions int[] DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
AS $enqueue_statistical_unit_facet_reduce$
DECLARE
    v_task_id BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    INSERT INTO worker.tasks AS t (command, payload)
    VALUES ('statistical_unit_facet_reduce', jsonb_build_object(
        'command', 'statistical_unit_facet_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until,
        'dirty_partitions', p_dirty_partitions
    ))
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_facet_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
            -- On merge, union dirty partitions from both runs (NULL means full refresh)
            'dirty_partitions', CASE
                WHEN t.payload->'dirty_partitions' = 'null'::jsonb
                  OR EXCLUDED.payload->'dirty_partitions' = 'null'::jsonb
                THEN NULL  -- If either is full refresh, stay full refresh
                ELSE (
                    SELECT jsonb_agg(DISTINCT val ORDER BY val)
                    FROM (
                        SELECT jsonb_array_elements(t.payload->'dirty_partitions') AS val
                        UNION
                        SELECT jsonb_array_elements(EXCLUDED.payload->'dirty_partitions') AS val
                    ) AS combined
                )
            END
        ),
        state = 'pending'::worker.task_state
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$enqueue_statistical_unit_facet_reduce$;


-- =====================================================================
-- 3. Update statistical_unit_facet_reduce: targeted DELETE instead of TRUNCATE
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $statistical_unit_facet_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_dirty_partitions INT[];
BEGIN
    RAISE DEBUG 'statistical_unit_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Extract dirty partitions from payload (NULL = full refresh)
    IF payload->'dirty_partitions' IS NOT NULL AND payload->'dirty_partitions' != 'null'::jsonb THEN
        SELECT array_agg(val::int)
        INTO v_dirty_partitions
        FROM jsonb_array_elements_text(payload->'dirty_partitions') AS val;
    END IF;

    -- Full re-derive from partition table
    DELETE FROM public.statistical_unit_facet;

    INSERT INTO public.statistical_unit_facet
    SELECT sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
           sufp.physical_region_path, sufp.primary_activity_category_path,
           sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id,
           SUM(sufp.count)::BIGINT,
           jsonb_stats_summary_merge_agg(sufp.stats_summary)
    FROM public.statistical_unit_facet_staging AS sufp
    GROUP BY sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
             sufp.physical_region_path, sufp.primary_activity_category_path,
             sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id;

    -- Clear only the dirty partitions that were processed (not TRUNCATE!)
    IF v_dirty_partitions IS NOT NULL THEN
        DELETE FROM public.statistical_unit_facet_dirty_partitions
        WHERE partition_seq = ANY(v_dirty_partitions);
        RAISE DEBUG 'statistical_unit_facet_reduce: cleared % dirty partitions', array_length(v_dirty_partitions, 1);
    ELSE
        -- Full refresh: clear all
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
        RAISE DEBUG 'statistical_unit_facet_reduce: full refresh — truncated dirty partitions';
    END IF;

    -- Enqueue next phase: derive_statistical_history_facet
    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    RAISE DEBUG 'statistical_unit_facet_reduce: done, enqueued derive_statistical_history_facet';
END;
$statistical_unit_facet_reduce$;

END;
