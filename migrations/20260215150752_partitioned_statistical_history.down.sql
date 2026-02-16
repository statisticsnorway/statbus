-- Down Migration 20260215150752: partitioned_statistical_history
BEGIN;

-- Delete all partition entries (keep only root entries for clean state)
DELETE FROM public.statistical_history WHERE partition_seq IS NOT NULL;

-- Restore original derive_statistical_history_period (without partition_seq)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_period(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_history_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
BEGIN
    RAISE DEBUG 'Processing statistical_history for resolution=%, year=%, month=%',
                 v_resolution, v_year, v_month;

    DELETE FROM public.statistical_history
    WHERE resolution = v_resolution
      AND year = v_year
      AND month IS NOT DISTINCT FROM v_month;

    IF v_resolution = 'year' THEN
        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h
        ON CONFLICT (resolution, year, unit_type) WHERE resolution = 'year'::public.history_resolution
        DO UPDATE SET
            exists_count = EXCLUDED.exists_count, exists_change = EXCLUDED.exists_change,
            exists_added_count = EXCLUDED.exists_added_count, exists_removed_count = EXCLUDED.exists_removed_count,
            countable_count = EXCLUDED.countable_count, countable_change = EXCLUDED.countable_change,
            countable_added_count = EXCLUDED.countable_added_count, countable_removed_count = EXCLUDED.countable_removed_count,
            births = EXCLUDED.births, deaths = EXCLUDED.deaths,
            name_change_count = EXCLUDED.name_change_count,
            primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
            secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
            sector_change_count = EXCLUDED.sector_change_count,
            legal_form_change_count = EXCLUDED.legal_form_change_count,
            physical_region_change_count = EXCLUDED.physical_region_change_count,
            physical_country_change_count = EXCLUDED.physical_country_change_count,
            physical_address_change_count = EXCLUDED.physical_address_change_count,
            stats_summary = EXCLUDED.stats_summary;
    ELSIF v_resolution = 'year-month' THEN
        INSERT INTO public.statistical_history
        SELECT h.*
        FROM public.statistical_history_def(v_resolution, v_year, v_month) AS h
        ON CONFLICT (resolution, year, month, unit_type) WHERE resolution = 'year-month'::public.history_resolution
        DO UPDATE SET
            exists_count = EXCLUDED.exists_count, exists_change = EXCLUDED.exists_change,
            exists_added_count = EXCLUDED.exists_added_count, exists_removed_count = EXCLUDED.exists_removed_count,
            countable_count = EXCLUDED.countable_count, countable_change = EXCLUDED.countable_change,
            countable_added_count = EXCLUDED.countable_added_count, countable_removed_count = EXCLUDED.countable_removed_count,
            births = EXCLUDED.births, deaths = EXCLUDED.deaths,
            name_change_count = EXCLUDED.name_change_count,
            primary_activity_category_change_count = EXCLUDED.primary_activity_category_change_count,
            secondary_activity_category_change_count = EXCLUDED.secondary_activity_category_change_count,
            sector_change_count = EXCLUDED.sector_change_count,
            legal_form_change_count = EXCLUDED.legal_form_change_count,
            physical_region_change_count = EXCLUDED.physical_region_change_count,
            physical_country_change_count = EXCLUDED.physical_country_change_count,
            physical_address_change_count = EXCLUDED.physical_address_change_count,
            stats_summary = EXCLUDED.stats_summary;
    END IF;

    RAISE DEBUG 'Completed statistical_history for resolution=%, year=%, month=%',
                 v_resolution, v_year, v_month;
END;
$derive_statistical_history_period$;

-- Restore original derive_statistical_history (no partition × period cross-product)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_history$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_period record;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    PERFORM worker.enqueue_derive_statistical_unit_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until
    );

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        PERFORM worker.spawn(
            p_command := 'derive_statistical_history_period',
            p_payload := jsonb_build_object(
                'resolution', v_period.resolution::text,
                'year', v_period.year,
                'month', v_period.month
            ),
            p_parent_id := v_task_id
        );
        v_child_count := v_child_count + 1;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history: spawned % period children', v_child_count;
END;
$derive_statistical_history$;

-- Drop reduce infrastructure
DELETE FROM worker.command_registry WHERE command = 'statistical_history_reduce';
DROP PROCEDURE IF EXISTS worker.statistical_history_reduce(jsonb);
DROP FUNCTION IF EXISTS worker.enqueue_statistical_history_reduce(date, date);
DROP INDEX IF EXISTS worker.idx_tasks_statistical_history_reduce_dedup;

-- Restore original statistical_history_def (3-parameter, no partition filtering)
CREATE OR REPLACE FUNCTION public.statistical_history_def(
  p_resolution public.history_resolution,
  p_year integer,
  p_month integer
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
        WHERE from_to_overlaps(su.valid_from, su.valid_to, v_prev_start, v_curr_stop)
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
        NULL::integer AS partition_seq
    FROM demographics d
    LEFT JOIN LATERAL (
        SELECT COALESCE(public.jsonb_stats_summary_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.unit_type = d.unit_type AND lvc.used_for_counting
    ) ss ON true;
END;
$statistical_history_def$;

-- Drop the 4-parameter overload
DROP FUNCTION IF EXISTS public.statistical_history_def(public.history_resolution, integer, integer, integer);

-- Restore original indexes (not partial)
DROP INDEX IF EXISTS public.statistical_history_year_key;
DROP INDEX IF EXISTS public.statistical_history_month_key;
DROP INDEX IF EXISTS public.statistical_history_partition_year_key;
DROP INDEX IF EXISTS public.statistical_history_partition_month_key;
DROP INDEX IF EXISTS public.idx_history_resolution;
DROP INDEX IF EXISTS public.idx_statistical_history_year;
DROP INDEX IF EXISTS public.idx_statistical_history_month;
DROP INDEX IF EXISTS public.idx_statistical_history_stats_summary;
DROP INDEX IF EXISTS public.idx_statistical_history_partition_seq;

CREATE UNIQUE INDEX statistical_history_year_key
    ON public.statistical_history (resolution, year, unit_type)
    WHERE resolution = 'year'::public.history_resolution;
CREATE UNIQUE INDEX statistical_history_month_key
    ON public.statistical_history (resolution, year, month, unit_type)
    WHERE resolution = 'year-month'::public.history_resolution;
CREATE INDEX idx_history_resolution ON public.statistical_history (resolution);
CREATE INDEX idx_statistical_history_year ON public.statistical_history (year);
CREATE INDEX idx_statistical_history_month ON public.statistical_history (month);
CREATE INDEX idx_statistical_history_stats_summary ON public.statistical_history USING GIN (stats_summary jsonb_path_ops);

-- Restore original RLS (no partition_seq filter)
DROP POLICY IF EXISTS statistical_history_authenticated_read ON public.statistical_history;
DROP POLICY IF EXISTS statistical_history_regular_user_read ON public.statistical_history;
CREATE POLICY statistical_history_authenticated_read ON public.statistical_history
    FOR SELECT TO authenticated USING (true);
CREATE POLICY statistical_history_regular_user_read ON public.statistical_history
    FOR SELECT TO regular_user USING (true);

-- Remove partition_seq from type (cascades to table)
ALTER TYPE public.statistical_history_type DROP ATTRIBUTE partition_seq CASCADE;

END;
