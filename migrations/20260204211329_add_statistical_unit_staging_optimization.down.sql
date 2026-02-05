-- Down migration: Remove staging table optimization for statistical_unit
--
-- Reverts to direct INSERT into statistical_unit (with sorted inserts for deadlock prevention)

BEGIN;

-- ============================================================================
-- Part 1: Restore original derive_statistical_unit (without flush enqueue)
-- ============================================================================

DROP FUNCTION IF EXISTS worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date, BIGINT);

CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
  p_establishment_id_ranges int4multirange DEFAULT NULL,
  p_legal_unit_id_ranges int4multirange DEFAULT NULL,
  p_enterprise_id_ranges int4multirange DEFAULT NULL,
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL,
  p_task_id BIGINT DEFAULT NULL  -- Current task ID for spawning children
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit$
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

    -- Priority for children: same as current task (will run next due to structured concurrency)
    v_child_priority := nextval('public.worker_task_priority_seq');
    -- Priority for uncle (derive_reports): lower priority (higher number), runs after parent completes
    v_uncle_priority := nextval('public.worker_task_priority_seq');

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children
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
                p_parent_id := p_task_id,  -- Child of current task
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

        -- Spawn batch children for affected groups
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
                    -- Pass explicitly requested IDs for cleanup of deleted entities
                    'explicit_enterprise_ids', v_enterprise_ids,
                    'explicit_legal_unit_ids', v_legal_unit_ids,
                    'explicit_establishment_ids', v_establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,  -- Child of current task
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;

        -- If no batches were created but we have explicit IDs, spawn a cleanup-only batch
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

    -- Refresh derived data (used flags)
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- Enqueue derive_reports (no flush_staging in original)
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$derive_statistical_unit$;


-- ============================================================================
-- Part 2: Restore original statistical_unit_refresh (direct INSERT with ORDER BY)
-- ============================================================================

CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(
    IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange
)
LANGUAGE plpgsql
AS $statistical_unit_refresh$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT;
    v_total_units INT;
    v_batch_start_time timestamptz;
    v_batch_duration_ms numeric;
    v_batch_speed numeric;
    v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL);

    IF NOT v_is_partial_refresh THEN
        -- Full refresh with ANALYZE
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise;

        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;

        -- Establishments
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

        -- Legal Units
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

        -- Enterprises
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

        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh with SORTED INSERTS to prevent B-tree page lock deadlocks
        -- ORDER BY ensures all concurrent batches acquire page locks in the same direction
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id <@ p_establishment_id_ranges;
            INSERT INTO public.statistical_unit
            SELECT * FROM import.get_statistical_unit_data_partial('establishment', p_establishment_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id <@ p_legal_unit_id_ranges;
            INSERT INTO public.statistical_unit
            SELECT * FROM import.get_statistical_unit_data_partial('legal_unit', p_legal_unit_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id <@ p_enterprise_id_ranges;
            INSERT INTO public.statistical_unit
            SELECT * FROM import.get_statistical_unit_data_partial('enterprise', p_enterprise_id_ranges)
            ORDER BY unit_type, unit_id, valid_from;  -- CRITICAL: Deterministic order prevents deadlocks
        END IF;
    END IF;
END;
$statistical_unit_refresh$;


-- ============================================================================
-- Part 3: Remove flush infrastructure
-- ============================================================================

-- Remove command registration
DELETE FROM worker.command_registry WHERE command = 'statistical_unit_flush_staging';

-- Drop worker handler
DROP PROCEDURE IF EXISTS worker.statistical_unit_flush_staging(JSONB);

-- Drop enqueue function
DROP FUNCTION IF EXISTS worker.enqueue_statistical_unit_flush_staging();

-- Drop dedup index
DROP INDEX IF EXISTS worker.idx_tasks_flush_staging_dedup;

-- Drop flush procedure
DROP PROCEDURE IF EXISTS public.statistical_unit_flush_staging();


-- ============================================================================
-- Part 4: Remove index management functions
-- ============================================================================

DROP FUNCTION IF EXISTS admin.create_statistical_unit_ui_indices();
DROP FUNCTION IF EXISTS admin.drop_statistical_unit_ui_indices();


-- ============================================================================
-- Part 5: Remove staging table
-- ============================================================================

DROP TABLE IF EXISTS public.statistical_unit_staging;


-- ============================================================================
-- Part 6: Restore old get_closed_group_batches (4-parameter version)
-- ============================================================================
-- This restores the function that was dropped to fix overload ambiguity.
-- Note: This version does NOT have offset/limit or has_more.

CREATE OR REPLACE FUNCTION public.get_closed_group_batches(
    p_target_batch_size INT DEFAULT 1000,
    p_establishment_ids INT[] DEFAULT NULL,
    p_legal_unit_ids INT[] DEFAULT NULL,
    p_enterprise_ids INT[] DEFAULT NULL
)
RETURNS TABLE (
    batch_seq INT,
    group_ids INT[],
    enterprise_ids INT[],
    legal_unit_ids INT[],
    establishment_ids INT[],
    total_unit_count INT
)
LANGUAGE plpgsql
VOLATILE
AS $get_closed_group_batches$
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
$get_closed_group_batches$;

END;
