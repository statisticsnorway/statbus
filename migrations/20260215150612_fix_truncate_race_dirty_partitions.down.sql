-- Down Migration 20260215150612: fix_truncate_race_dirty_partitions
BEGIN;

-- Restore original enqueue function (without dirty_partitions parameter)
DROP FUNCTION IF EXISTS worker.enqueue_statistical_unit_facet_reduce(date, date, int[]);
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_facet_reduce(
    p_valid_from date DEFAULT NULL, p_valid_until date DEFAULT NULL
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
        'valid_until', v_valid_until
    ))
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_facet_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
        ),
        state = 'pending'::worker.task_state
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$enqueue_statistical_unit_facet_reduce$;

-- Restore original derive_statistical_unit_facet (without dirty_partitions in payload)
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
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    SELECT COUNT(DISTINCT report_partition_seq) INTO v_expected_partitions
    FROM public.statistical_unit
    WHERE used_for_counting;

    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    PERFORM worker.enqueue_statistical_unit_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    IF v_dirty_partitions IS NULL THEN
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

-- Restore original reduce (with TRUNCATE)
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $statistical_unit_facet_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    RAISE DEBUG 'statistical_unit_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

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

    TRUNCATE public.statistical_unit_facet_dirty_partitions;

    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    RAISE DEBUG 'statistical_unit_facet_reduce: done, enqueued derive_statistical_history_facet';
END;
$statistical_unit_facet_reduce$;

END;
