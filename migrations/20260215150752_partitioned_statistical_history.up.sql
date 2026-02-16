-- Migration 20260215150752: partitioned_statistical_history
--
-- Add partition_seq to statistical_history for inline partition entries.
-- Root entries (partition_seq IS NULL) = aggregate results, queried by API/UI
-- Partition entries (partition_seq = 0..127) = per-partition partial results
--
-- On update, only dirty partitions are recomputed. Root entries are
-- recalculated by summing across all partition entries.
BEGIN;

-- =====================================================================
-- 1. Add partition_seq attribute to the type (cascades to typed table)
-- =====================================================================
ALTER TYPE public.statistical_history_type ADD ATTRIBUTE partition_seq integer CASCADE;

-- =====================================================================
-- 2. Convert existing unique constraints to partial (root entries only)
--    and add partition-entry unique constraints
-- =====================================================================

-- Drop existing unique indexes
DROP INDEX IF EXISTS public.statistical_history_year_key;
DROP INDEX IF EXISTS public.statistical_history_month_key;

-- Root entry unique constraints (partition_seq IS NULL = API-visible rows)
CREATE UNIQUE INDEX statistical_history_year_key
    ON public.statistical_history (resolution, year, unit_type)
    WHERE resolution = 'year'::public.history_resolution AND partition_seq IS NULL;

CREATE UNIQUE INDEX statistical_history_month_key
    ON public.statistical_history (resolution, year, month, unit_type)
    WHERE resolution = 'year-month'::public.history_resolution AND partition_seq IS NULL;

-- Partition entry unique constraints (one row per partition × period × unit_type)
CREATE UNIQUE INDEX statistical_history_partition_year_key
    ON public.statistical_history (partition_seq, resolution, year, unit_type)
    WHERE resolution = 'year'::public.history_resolution AND partition_seq IS NOT NULL;

CREATE UNIQUE INDEX statistical_history_partition_month_key
    ON public.statistical_history (partition_seq, resolution, year, month, unit_type)
    WHERE resolution = 'year-month'::public.history_resolution AND partition_seq IS NOT NULL;

-- =====================================================================
-- 3. Convert performance indexes to partial (root entries only)
-- =====================================================================
DROP INDEX IF EXISTS public.idx_history_resolution;
DROP INDEX IF EXISTS public.idx_statistical_history_year;
DROP INDEX IF EXISTS public.idx_statistical_history_month;
DROP INDEX IF EXISTS public.idx_statistical_history_stats_summary;

CREATE INDEX idx_history_resolution
    ON public.statistical_history (resolution)
    WHERE partition_seq IS NULL;
CREATE INDEX idx_statistical_history_year
    ON public.statistical_history (year)
    WHERE partition_seq IS NULL;
CREATE INDEX idx_statistical_history_month
    ON public.statistical_history (month)
    WHERE partition_seq IS NULL;
CREATE INDEX idx_statistical_history_stats_summary
    ON public.statistical_history USING GIN (stats_summary jsonb_path_ops)
    WHERE partition_seq IS NULL;

-- Index for efficient partition cleanup
CREATE INDEX idx_statistical_history_partition_seq
    ON public.statistical_history (partition_seq)
    WHERE partition_seq IS NOT NULL;

-- =====================================================================
-- 4. Update RLS policies to hide partition entries from API consumers
-- =====================================================================
DROP POLICY IF EXISTS statistical_history_authenticated_read ON public.statistical_history;
DROP POLICY IF EXISTS statistical_history_regular_user_read ON public.statistical_history;

CREATE POLICY statistical_history_authenticated_read ON public.statistical_history
    FOR SELECT TO authenticated USING (partition_seq IS NULL);
CREATE POLICY statistical_history_regular_user_read ON public.statistical_history
    FOR SELECT TO regular_user USING (partition_seq IS NULL);

-- admin_user keeps full access (USING (true)) for debugging

-- =====================================================================
-- 5. Update statistical_history_def to accept partition_seq parameter
-- =====================================================================
CREATE OR REPLACE FUNCTION public.statistical_history_def(
  p_resolution public.history_resolution,
  p_year integer,
  p_month integer,
  p_partition_seq integer DEFAULT NULL
)
RETURNS SETOF public.statistical_history_type
LANGUAGE plpgsql
AS $statistical_history_def$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    -- Manually calculate the date ranges for the current and previous periods.
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE -- 'year-month'
        v_curr_start := make_date(p_year, p_month, 1);
        v_curr_stop  := (v_curr_start + interval '1 month') - interval '1 day';
        v_prev_stop  := v_curr_start - interval '1 day';
        v_prev_start := date_trunc('month', v_prev_stop)::date;
    END IF;

    RETURN QUERY
    WITH
    units_in_period AS (
        SELECT *
        FROM public.statistical_unit su
        WHERE from_to_overlaps(su.valid_from, su.valid_to, v_prev_start, v_curr_stop)
          -- When computing a single partition, filter by report_partition_seq
          AND (p_partition_seq IS NULL OR su.report_partition_seq = p_partition_seq)
    ),
    latest_versions_curr AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        SELECT * FROM latest_versions_curr lvc
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            c AS curr,
            p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type,
            count((curr).unit_id)::integer AS exists_count,
            (count((curr).unit_id) - count((prev).unit_id))::integer AS exists_change,
            count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL)::integer AS exists_added_count,
            count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL)::integer AS exists_removed_count,
            count((curr).unit_id) FILTER (WHERE (curr).used_for_counting)::integer AS countable_count,
            (count((curr).unit_id) FILTER (WHERE (curr).used_for_counting) - count((prev).unit_id) FILTER (WHERE (prev).used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE (curr).used_for_counting AND NOT COALESCE((prev).used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND NOT COALESCE((curr).used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).name IS DISTINCT FROM (prev).name)::integer AS name_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).primary_activity_category_path IS DISTINCT FROM (prev).primary_activity_category_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).secondary_activity_category_path IS DISTINCT FROM (prev).secondary_activity_category_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).sector_path IS DISTINCT FROM (prev).sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).legal_form_id IS DISTINCT FROM (prev).legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_region_path IS DISTINCT FROM (prev).physical_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).physical_country_id IS DISTINCT FROM (prev).physical_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace))::integer AS physical_address_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4
    )
    SELECT
        d.p_resolution AS resolution, d.p_year AS year, d.p_month AS month, d.unit_type,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count, d.secondary_activity_category_change_count,
        d.sector_change_count, d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        ss.stats_summary,
        p_partition_seq  -- Pass through the partition_seq
    FROM demographics d
    LEFT JOIN LATERAL (
        SELECT COALESCE(public.jsonb_stats_summary_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.unit_type = d.unit_type AND lvc.used_for_counting
    ) ss ON true;
END;
$statistical_history_def$;

-- Drop the old 3-parameter overload (replaced by 4-parameter version with DEFAULT)
DROP FUNCTION IF EXISTS public.statistical_history_def(public.history_resolution, integer, integer);

-- =====================================================================
-- 6. New: statistical_history_reduce procedure (uncle task)
-- =====================================================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_statistical_history_reduce_dedup
    ON worker.tasks (command)
    WHERE command = 'statistical_history_reduce' AND state = 'pending';

CREATE FUNCTION worker.enqueue_statistical_history_reduce(
    p_valid_from date DEFAULT NULL, p_valid_until date DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
AS $enqueue_statistical_history_reduce$
DECLARE
    v_task_id BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    INSERT INTO worker.tasks AS t (command, payload)
    VALUES ('statistical_history_reduce', jsonb_build_object(
        'command', 'statistical_history_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until
    ))
    ON CONFLICT (command)
    WHERE command = 'statistical_history_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_history_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
        ),
        state = 'pending'::worker.task_state
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$enqueue_statistical_history_reduce$;


CREATE PROCEDURE worker.statistical_history_reduce(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $statistical_history_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    RAISE DEBUG 'statistical_history_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Delete existing root entries
    DELETE FROM public.statistical_history WHERE partition_seq IS NULL;

    -- Recalculate root entries by summing across all partition entries
    INSERT INTO public.statistical_history (
        resolution, year, month, unit_type,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        stats_summary,
        partition_seq
    )
    SELECT
        resolution, year, month, unit_type,
        SUM(exists_count)::integer,
        SUM(exists_change)::integer,
        SUM(exists_added_count)::integer,
        SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer,
        SUM(countable_change)::integer,
        SUM(countable_added_count)::integer,
        SUM(countable_removed_count)::integer,
        SUM(births)::integer,
        SUM(deaths)::integer,
        SUM(name_change_count)::integer,
        SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer,
        SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer,
        SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer,
        SUM(physical_address_change_count)::integer,
        public.jsonb_stats_summary_merge_agg(stats_summary),
        NULL  -- partition_seq = NULL = root entry
    FROM public.statistical_history
    WHERE partition_seq IS NOT NULL
    GROUP BY resolution, year, month, unit_type;

    -- Enqueue next phase: derive_statistical_unit_facet
    PERFORM worker.enqueue_derive_statistical_unit_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    RAISE DEBUG 'statistical_history_reduce: done, enqueued derive_statistical_unit_facet';
END;
$statistical_history_reduce$;

-- Register the new command
INSERT INTO worker.command_registry (command, handler_procedure, description, queue)
VALUES ('statistical_history_reduce', 'worker.statistical_history_reduce',
        'Aggregate partition entries into root entries for statistical_history', 'analytics')
ON CONFLICT (command) DO UPDATE SET handler_procedure = EXCLUDED.handler_procedure;


-- =====================================================================
-- 7. Update derive_statistical_history to spawn period × partition children
--    and enqueue reduce uncle task
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_history$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_partition INT;
    v_child_count integer := 0;
BEGIN
    -- Get own task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- Read dirty partitions (snapshot)
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    -- If no partition entries exist yet (first run), force full refresh
    IF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE partition_seq IS NOT NULL LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history: No partition entries exist, forcing full refresh';
    END IF;

    -- Enqueue reduce uncle task (runs after children complete)
    PERFORM worker.enqueue_statistical_history_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    -- Spawn one child per period × partition combination
    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NULL THEN
            -- Full refresh: all populated partitions (include all units, not just
            -- used_for_counting, because exists_count tracks all units)
            FOR v_partition IN
                SELECT DISTINCT report_partition_seq
                FROM public.statistical_unit
                ORDER BY report_partition_seq
            LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_period',
                    p_payload := jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id := v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            -- Partial refresh: only dirty partitions
            FOREACH v_partition IN ARRAY v_dirty_partitions LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_period',
                    p_payload := jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id := v_task_id
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history: spawned % period×partition children (dirty_partitions=%)',
        v_child_count, v_dirty_partitions;
END;
$derive_statistical_history$;


-- =====================================================================
-- 8. Update derive_statistical_history_period to be partition-aware
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_history_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_partition_seq integer := (payload->>'partition_seq')::integer;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;

    IF v_partition_seq IS NOT NULL THEN
        -- Partition-aware: delete and reinsert for this specific partition × period
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq = v_partition_seq;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month, v_partition_seq) AS h;
    ELSE
        -- Legacy non-partitioned path (backwards compatible for full refresh without partitions)
        DELETE FROM public.statistical_history
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq IS NULL;

        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;
END;
$derive_statistical_history_period$;


-- =====================================================================
-- 9. Remove the old statistical_history_derive function (replaced by
--    worker procedure + reduce pattern)
-- =====================================================================
-- Keep the function for now — it's still referenced by the optimize_analytics_batching
-- migration's derive_statistical_history procedure. The new procedure replaces it.

END;
