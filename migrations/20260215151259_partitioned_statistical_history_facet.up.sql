-- Migration 20260215151259: partitioned_statistical_history_facet
--
-- Partition-aware analytics for statistical_history_facet using UNLOGGED partition table.
-- Partition entries go into a separate UNLOGGED table (fast writes, no WAL overhead).
-- Reduce aggregates from partition table into main table using TRUNCATE (zero dead tuples).
-- Main table stays unchanged — no partition_seq column, no index changes, no RLS changes.
BEGIN;

-- =====================================================================
-- 1. Create UNLOGGED partition table for intermediate computation
-- =====================================================================
CREATE UNLOGGED TABLE public.statistical_history_facet_partitions (
    partition_seq integer NOT NULL,
    resolution public.history_resolution,
    year integer,
    month integer,
    unit_type public.statistical_unit_type,
    primary_activity_category_path public.ltree,
    secondary_activity_category_path public.ltree,
    sector_path public.ltree,
    legal_form_id integer,
    physical_region_path public.ltree,
    physical_country_id integer,
    unit_size_id integer,
    status_id integer,
    exists_count integer,
    exists_change integer,
    exists_added_count integer,
    exists_removed_count integer,
    countable_count integer,
    countable_change integer,
    countable_added_count integer,
    countable_removed_count integer,
    births integer,
    deaths integer,
    name_change_count integer,
    primary_activity_category_change_count integer,
    secondary_activity_category_change_count integer,
    sector_change_count integer,
    legal_form_change_count integer,
    physical_region_change_count integer,
    physical_country_change_count integer,
    physical_address_change_count integer,
    unit_size_change_count integer,
    status_change_count integer,
    stats_summary jsonb,
    UNIQUE NULLS NOT DISTINCT (partition_seq, resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id)
);

CREATE INDEX idx_shf_partitions_seq ON public.statistical_history_facet_partitions (partition_seq);

-- =====================================================================
-- 2. Update statistical_history_facet_def to accept partition_seq filter
-- =====================================================================
-- The function accepts p_partition_seq for filtering but returns the
-- unchanged type (no partition_seq column in output).
CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(
  p_resolution public.history_resolution,
  p_year integer,
  p_month integer,
  p_partition_seq integer DEFAULT NULL
)
RETURNS SETOF public.statistical_history_facet_type
LANGUAGE plpgsql
AS $statistical_history_facet_def$
DECLARE
    v_curr_start date;
    v_curr_stop date;
    v_prev_start date;
    v_prev_stop date;
BEGIN
    IF p_resolution = 'year'::public.history_resolution THEN
        v_curr_start := make_date(p_year, 1, 1);
        v_curr_stop  := make_date(p_year, 12, 31);
        v_prev_start := make_date(p_year - 1, 1, 1);
        v_prev_stop  := make_date(p_year - 1, 12, 31);
    ELSE
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
        WHERE daterange(su.valid_from, su.valid_to, '[)') && daterange(v_prev_start, v_curr_stop + 1, '[)')
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
            c AS curr, p AS prev,
            lvc AS last_version_in_curr
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type,
            COALESCE((curr).primary_activity_category_path, (prev).primary_activity_category_path) AS primary_activity_category_path,
            COALESCE((curr).secondary_activity_category_path, (prev).secondary_activity_category_path) AS secondary_activity_category_path,
            COALESCE((curr).sector_path, (prev).sector_path) AS sector_path,
            COALESCE((curr).legal_form_id, (prev).legal_form_id) AS legal_form_id,
            COALESCE((curr).physical_region_path, (prev).physical_region_path) AS physical_region_path,
            COALESCE((curr).physical_country_id, (prev).physical_country_id) AS physical_country_id,
            COALESCE((curr).unit_size_id, (prev).unit_size_id) AS unit_size_id,
            COALESCE((curr).status_id, (prev).status_id) AS status_id,
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
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace))::integer AS physical_address_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).unit_size_id IS DISTINCT FROM (prev).unit_size_id)::integer AS unit_size_change_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND (curr).used_for_counting AND (curr).status_id IS DISTINCT FROM (prev).status_id)::integer AS status_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    )
    SELECT
        d.p_resolution, d.p_year, d.p_month, d.unit_type,
        d.primary_activity_category_path, d.secondary_activity_category_path,
        d.sector_path, d.legal_form_id, d.physical_region_path,
        d.physical_country_id, d.unit_size_id, d.status_id,
        d.exists_count, d.exists_change, d.exists_added_count, d.exists_removed_count,
        d.countable_count, d.countable_change, d.countable_added_count, d.countable_removed_count,
        d.births, d.deaths,
        d.name_change_count, d.primary_activity_category_change_count,
        d.secondary_activity_category_change_count, d.sector_change_count,
        d.legal_form_change_count, d.physical_region_change_count,
        d.physical_country_change_count, d.physical_address_change_count,
        d.unit_size_change_count, d.status_change_count,
        ss.stats_summary
    FROM demographics d
    LEFT JOIN LATERAL (
        SELECT COALESCE(public.jsonb_stats_summary_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
         FROM latest_versions_curr lvc
         WHERE lvc.unit_type = d.unit_type
           AND lvc.used_for_counting
           AND lvc.primary_activity_category_path IS NOT DISTINCT FROM d.primary_activity_category_path
           AND lvc.secondary_activity_category_path IS NOT DISTINCT FROM d.secondary_activity_category_path
           AND lvc.sector_path IS NOT DISTINCT FROM d.sector_path
           AND lvc.legal_form_id IS NOT DISTINCT FROM d.legal_form_id
           AND lvc.physical_region_path IS NOT DISTINCT FROM d.physical_region_path
           AND lvc.physical_country_id IS NOT DISTINCT FROM d.physical_country_id
           AND lvc.unit_size_id IS NOT DISTINCT FROM d.unit_size_id
           AND lvc.status_id IS NOT DISTINCT FROM d.status_id
    ) ss ON true;
END;
$statistical_history_facet_def$;

-- Drop the old 3-parameter overload
DROP FUNCTION IF EXISTS public.statistical_history_facet_def(public.history_resolution, integer, integer);

-- =====================================================================
-- 3. Create statistical_history_facet_reduce procedure
-- =====================================================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_statistical_history_facet_reduce_dedup
    ON worker.tasks (command)
    WHERE command = 'statistical_history_facet_reduce' AND state = 'pending';

CREATE FUNCTION worker.enqueue_statistical_history_facet_reduce(
    p_valid_from date DEFAULT NULL, p_valid_until date DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql
AS $enqueue_statistical_history_facet_reduce$
DECLARE
    v_task_id BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    INSERT INTO worker.tasks AS t (command, payload)
    VALUES ('statistical_history_facet_reduce', jsonb_build_object(
        'command', 'statistical_history_facet_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until
    ))
    ON CONFLICT (command)
    WHERE command = 'statistical_history_facet_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_history_facet_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
        ),
        state = 'pending'::worker.task_state
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$enqueue_statistical_history_facet_reduce$;


CREATE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $statistical_history_facet_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    RAISE DEBUG 'statistical_history_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- TRUNCATE is instant (no dead tuples, no per-row WAL), unlike DELETE which
    -- accumulates ~800K dead tuples per cycle causing progressive slowdown.
    TRUNCATE public.statistical_history_facet;

    -- Aggregate from UNLOGGED partition table into main LOGGED table
    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        SUM(unit_size_change_count)::integer, SUM(status_change_count)::integer,
        public.jsonb_stats_summary_merge_agg(stats_summary)
    FROM public.statistical_history_facet_partitions
    GROUP BY resolution, year, month, unit_type,
             primary_activity_category_path, secondary_activity_category_path,
             sector_path, legal_form_id, physical_region_path,
             physical_country_id, unit_size_id, status_id;

    RAISE DEBUG 'statistical_history_facet_reduce: done';
END;
$statistical_history_facet_reduce$;

INSERT INTO worker.command_registry (command, handler_procedure, description, queue)
VALUES ('statistical_history_facet_reduce', 'worker.statistical_history_facet_reduce',
        'Aggregate partition entries into root entries for statistical_history_facet', 'analytics')
ON CONFLICT (command) DO UPDATE SET handler_procedure = EXCLUDED.handler_procedure;


-- =====================================================================
-- 4. Update dedup index to include partition_seq (period × partition children)
-- =====================================================================
DROP INDEX IF EXISTS worker.idx_tasks_derive_history_facet_period_dedup;
CREATE UNIQUE INDEX idx_tasks_derive_history_facet_period_dedup
    ON worker.tasks (command, (payload->>'resolution'), (payload->>'year'), (payload->>'month'), ((payload->>'partition_seq')::integer))
    WHERE command = 'derive_statistical_history_facet_period' AND state = 'pending';

-- =====================================================================
-- 5. Update derive_statistical_history_facet: period × partition children
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_partition INT;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- Read dirty partitions
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    -- If no partition entries exist yet (UNLOGGED data lost or first run), force full refresh
    IF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history_facet: No partition entries exist, forcing full refresh';
    END IF;

    -- Enqueue reduce uncle task
    PERFORM worker.enqueue_statistical_history_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    -- Spawn period × partition children
    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NULL THEN
            -- Include all partitions (not just used_for_counting) because
            -- statistical_history_facet tracks exists_count for all units
            FOR v_partition IN
                SELECT DISTINCT report_partition_seq
                FROM public.statistical_unit
                ORDER BY report_partition_seq
            LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_facet_period',
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
            FOREACH v_partition IN ARRAY v_dirty_partitions LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_facet_period',
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

    RAISE DEBUG 'derive_statistical_history_facet: spawned % period×partition children', v_child_count;
END;
$derive_statistical_history_facet$;


-- =====================================================================
-- 6. Update derive_statistical_history_facet_period: write to partition table
-- =====================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_history_facet_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
    v_partition_seq integer := (payload->>'partition_seq')::integer;
BEGIN
    RAISE DEBUG 'Processing statistical_history_facet for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;

    IF v_partition_seq IS NOT NULL THEN
        -- Delete and reinsert for this partition × period in the UNLOGGED partition table
        DELETE FROM public.statistical_history_facet_partitions
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month
          AND partition_seq = v_partition_seq;

        INSERT INTO public.statistical_history_facet_partitions (
            partition_seq,
            resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path,
            physical_country_id, unit_size_id, status_id,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths,
            name_change_count, primary_activity_category_change_count,
            secondary_activity_category_change_count, sector_change_count,
            legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            unit_size_change_count, status_change_count,
            stats_summary
        )
        SELECT v_partition_seq, h.*
        FROM public.statistical_history_facet_def(v_resolution, v_year, v_month, v_partition_seq) AS h;
    ELSE
        -- Legacy non-partitioned path: write directly to main table
        DELETE FROM public.statistical_history_facet
        WHERE resolution = v_resolution
          AND year = v_year
          AND month IS NOT DISTINCT FROM v_month;

        INSERT INTO public.statistical_history_facet
        SELECT h.*
        FROM public.statistical_history_facet_def(v_resolution, v_year, v_month) AS h;
    END IF;

    RAISE DEBUG 'Completed statistical_history_facet for resolution=%, year=%, month=%, partition_seq=%',
                 v_resolution, v_year, v_month, v_partition_seq;
END;
$derive_statistical_history_facet_period$;

END;
