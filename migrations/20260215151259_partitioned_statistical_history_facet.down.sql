-- Down Migration 20260215151259: partitioned_statistical_history_facet
BEGIN;

-- Restore original derive_statistical_history_facet_period (without partition_seq)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_history_facet_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;
BEGIN
    RAISE DEBUG 'Processing statistical_history_facet for resolution=%, year=%, month=%',
                 v_resolution, v_year, v_month;

    DELETE FROM public.statistical_history_facet
    WHERE resolution = v_resolution
      AND year = v_year
      AND month IS NOT DISTINCT FROM v_month;

    INSERT INTO public.statistical_history_facet
    SELECT * FROM public.statistical_history_facet_def(v_resolution, v_year, v_month);

    RAISE DEBUG 'Completed statistical_history_facet for resolution=%, year=%, month=%',
                 v_resolution, v_year, v_month;
END;
$derive_statistical_history_facet_period$;

-- Restore original derive_statistical_history_facet (no partition × period cross-product)
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_task_id bigint;
    v_period record;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        PERFORM worker.spawn(
            p_command := 'derive_statistical_history_facet_period',
            p_payload := jsonb_build_object(
                'resolution', v_period.resolution::text,
                'year', v_period.year,
                'month', v_period.month
            ),
            p_parent_id := v_task_id
        );
        v_child_count := v_child_count + 1;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history_facet: spawned % period children', v_child_count;
END;
$derive_statistical_history_facet$;

-- Restore original dedup index (without partition_seq)
DROP INDEX IF EXISTS worker.idx_tasks_derive_history_facet_period_dedup;
CREATE UNIQUE INDEX idx_tasks_derive_history_facet_period_dedup
    ON worker.tasks (command, (payload->>'resolution'), (payload->>'year'), (payload->>'month'))
    WHERE command = 'derive_statistical_history_facet_period' AND state = 'pending';

-- Drop reduce infrastructure
DELETE FROM worker.command_registry WHERE command = 'statistical_history_facet_reduce';
DROP PROCEDURE IF EXISTS worker.statistical_history_facet_reduce(jsonb);
DROP FUNCTION IF EXISTS worker.enqueue_statistical_history_facet_reduce(date, date);
DROP INDEX IF EXISTS worker.idx_tasks_statistical_history_facet_reduce_dedup;

-- Restore original statistical_history_facet_def (3-parameter, no partition filtering)
CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(
  p_resolution public.history_resolution,
  p_year integer,
  p_month integer
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
        SELECT
            unit_id, unit_type, valid_from, valid_until,
            birth_date, death_date, used_for_counting, name,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id,
            physical_region_path, physical_country_id,
            physical_address_part1, physical_address_part2, physical_address_part3,
            physical_postcode, physical_postplace,
            unit_size_id, status_id, stats_summary
        FROM public.statistical_unit su
        WHERE daterange(su.valid_from, su.valid_until, '[)') && daterange(v_prev_start, v_curr_stop + 1, '[)')
    ),
    latest_curr AS (
        SELECT DISTINCT ON (unit_id, unit_type) *
        FROM units_in_period
        WHERE valid_from <= v_curr_stop AND valid_until > v_curr_start
        ORDER BY unit_id, unit_type, valid_from DESC, valid_until DESC
    ),
    latest_prev AS (
        SELECT DISTINCT ON (unit_id, unit_type) *
        FROM units_in_period
        WHERE valid_from <= v_prev_stop
        ORDER BY unit_id, unit_type, valid_from DESC, valid_until DESC
    ),
    stock_curr AS (
        SELECT * FROM latest_curr c
        WHERE c.valid_until > v_curr_stop
          AND COALESCE(c.birth_date, c.valid_from) <= v_curr_stop
          AND (c.death_date IS NULL OR c.death_date > v_curr_stop)
    ),
    stock_prev AS (
        SELECT * FROM latest_prev p
        WHERE p.valid_until > v_prev_stop
          AND COALESCE(p.birth_date, p.valid_from) <= v_prev_stop
          AND (p.death_date IS NULL OR p.death_date > v_prev_stop)
    ),
    stats_by_facet AS (
        SELECT
            unit_type::text || '|' ||
            COALESCE(primary_activity_category_path::text, '') || '|' ||
            COALESCE(secondary_activity_category_path::text, '') || '|' ||
            COALESCE(sector_path::text, '') || '|' ||
            COALESCE(legal_form_id::text, '') || '|' ||
            COALESCE(physical_region_path::text, '') || '|' ||
            COALESCE(physical_country_id::text, '') || '|' ||
            COALESCE(unit_size_id::text, '') || '|' ||
            COALESCE(status_id::text, '') AS facet_key,
            unit_type,
            primary_activity_category_path,
            secondary_activity_category_path,
            sector_path,
            legal_form_id,
            physical_region_path,
            physical_country_id,
            unit_size_id,
            status_id,
            COALESCE(public.jsonb_stats_summary_merge_agg(stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_curr
        WHERE used_for_counting
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
    ),
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            c.unit_id AS c_unit_id, c.used_for_counting AS c_used_for_counting,
            c.primary_activity_category_path AS c_pac_path,
            c.secondary_activity_category_path AS c_sac_path,
            c.sector_path AS c_sector_path, c.legal_form_id AS c_legal_form_id,
            c.physical_region_path AS c_region_path, c.physical_country_id AS c_country_id,
            c.physical_address_part1 AS c_addr1, c.physical_address_part2 AS c_addr2,
            c.physical_address_part3 AS c_addr3, c.physical_postcode AS c_postcode,
            c.physical_postplace AS c_postplace,
            c.unit_size_id AS c_size_id, c.status_id AS c_status_id, c.name AS c_name,
            p.unit_id AS p_unit_id, p.used_for_counting AS p_used_for_counting,
            p.primary_activity_category_path AS p_pac_path,
            p.secondary_activity_category_path AS p_sac_path,
            p.sector_path AS p_sector_path, p.legal_form_id AS p_legal_form_id,
            p.physical_region_path AS p_region_path, p.physical_country_id AS p_country_id,
            p.physical_address_part1 AS p_addr1, p.physical_address_part2 AS p_addr2,
            p.physical_address_part3 AS p_addr3, p.physical_postcode AS p_postcode,
            p.physical_postplace AS p_postplace,
            p.unit_size_id AS p_size_id, p.status_id AS p_status_id, p.name AS p_name,
            lvc.birth_date AS lvc_birth_date, lvc.death_date AS lvc_death_date,
            lvc.used_for_counting AS lvc_used_for_counting
        FROM stock_curr c
        FULL JOIN stock_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id)
                                 AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month,
            unit_type,
            COALESCE(c_pac_path, p_pac_path) AS primary_activity_category_path,
            COALESCE(c_sac_path, p_sac_path) AS secondary_activity_category_path,
            COALESCE(c_sector_path, p_sector_path) AS sector_path,
            COALESCE(c_legal_form_id, p_legal_form_id) AS legal_form_id,
            COALESCE(c_region_path, p_region_path) AS physical_region_path,
            COALESCE(c_country_id, p_country_id) AS physical_country_id,
            COALESCE(c_size_id, p_size_id) AS unit_size_id,
            COALESCE(c_status_id, p_status_id) AS status_id,
            unit_type::text || '|' ||
            COALESCE(COALESCE(c_pac_path, p_pac_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_sac_path, p_sac_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_sector_path, p_sector_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_legal_form_id, p_legal_form_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_region_path, p_region_path)::text, '') || '|' ||
            COALESCE(COALESCE(c_country_id, p_country_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_size_id, p_size_id)::text, '') || '|' ||
            COALESCE(COALESCE(c_status_id, p_status_id)::text, '') AS facet_key,
            count(c_unit_id)::integer AS exists_count,
            (count(c_unit_id) - count(p_unit_id))::integer AS exists_change,
            count(c_unit_id) FILTER (WHERE p_unit_id IS NULL)::integer AS exists_added_count,
            count(p_unit_id) FILTER (WHERE c_unit_id IS NULL)::integer AS exists_removed_count,
            count(c_unit_id) FILTER (WHERE c_used_for_counting)::integer AS countable_count,
            (count(c_unit_id) FILTER (WHERE c_used_for_counting) - count(p_unit_id) FILTER (WHERE p_used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE c_used_for_counting AND NOT COALESCE(p_used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE p_used_for_counting AND NOT COALESCE(c_used_for_counting, false))::integer AS countable_removed_count,
            count(*) FILTER (WHERE lvc_used_for_counting AND lvc_birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE lvc_used_for_counting AND lvc_death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_name IS DISTINCT FROM p_name)::integer AS name_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_pac_path IS DISTINCT FROM p_pac_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_sac_path IS DISTINCT FROM p_sac_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_sector_path IS DISTINCT FROM p_sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_legal_form_id IS DISTINCT FROM p_legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_region_path IS DISTINCT FROM p_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_country_id IS DISTINCT FROM p_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND
                (c_addr1, c_addr2, c_addr3, c_postcode, c_postplace) IS DISTINCT FROM
                (p_addr1, p_addr2, p_addr3, p_postcode, p_postplace))::integer AS physical_address_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_size_id IS DISTINCT FROM p_size_id)::integer AS unit_size_change_count,
            count(*) FILTER (WHERE p_used_for_counting AND c_used_for_counting AND c_status_id IS DISTINCT FROM p_status_id)::integer AS status_change_count
        FROM changed_units
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
    )
    SELECT
        d.p_resolution AS resolution,
        d.p_year AS year,
        d.p_month AS month,
        d.unit_type,
        d.primary_activity_category_path,
        d.secondary_activity_category_path,
        d.sector_path,
        d.legal_form_id,
        d.physical_region_path,
        d.physical_country_id,
        d.unit_size_id,
        d.status_id,
        d.exists_count,
        d.exists_change,
        d.exists_added_count,
        d.exists_removed_count,
        d.countable_count,
        d.countable_change,
        d.countable_added_count,
        d.countable_removed_count,
        d.births,
        d.deaths,
        d.name_change_count,
        d.primary_activity_category_change_count,
        d.secondary_activity_category_change_count,
        d.sector_change_count,
        d.legal_form_change_count,
        d.physical_region_change_count,
        d.physical_country_change_count,
        d.physical_address_change_count,
        d.unit_size_change_count,
        d.status_change_count,
        COALESCE(s.stats_summary, '{}'::jsonb) AS stats_summary
    FROM demographics d
    LEFT JOIN stats_by_facet s ON s.facet_key = d.facet_key;
END;
$statistical_history_facet_def$;

-- Drop the 4-parameter overload
DROP FUNCTION IF EXISTS public.statistical_history_facet_def(public.history_resolution, integer, integer, integer);

-- Drop the UNLOGGED partition table
DROP TABLE IF EXISTS public.statistical_history_facet_partitions;

END;
