-- Migration 20260203094412: optimize_statistical_history_facet_def_remove_lateral_join
--
-- PERF: Replace O(n²) LATERAL JOIN with O(n) pre-aggregated CTE for stats_summary.
--
-- The original query used a LATERAL JOIN that scanned latest_versions_curr (33,874 rows)
-- for each of the 17,960 demographic groups, resulting in ~608 million row comparisons.
--
-- The optimized version pre-aggregates stats_summary by facet dimensions in a separate CTE,
-- then joins with a regular LEFT JOIN. This reduces execution time from ~128s to ~15s (8.3x speedup).
BEGIN;

CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(p_resolution public.history_resolution, p_year integer, p_month integer)
 RETURNS SETOF public.statistical_history_facet_type
 LANGUAGE plpgsql
AS $statistical_history_facet_def$
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
        -- Get a broad candidate pool of all unit versions that were valid at any point
        -- during the previous or current periods, using inclusive date ranges.
        -- PERF: Use native daterange && operator instead of from_to_overlaps() function.
        -- This allows PostgreSQL to use the GIST exclusion index for fast range overlap queries,
        -- reducing query time from ~130s to ~17s (7x improvement).
        -- FIX: Use valid_until (indexed) instead of valid_to (derived, not indexed).
        SELECT *
        FROM public.statistical_unit su
        WHERE daterange(su.valid_from, su.valid_until, '[)') && daterange(v_prev_start, v_curr_stop + 1, '[)')
    ),
    latest_versions_curr AS (
        -- Find the single, most recent version of each unit that was active at any point
        -- during the *current* period. This represents all entities with economic activity.
        -- FIX: Use valid_until > v_curr_start for half-open interval semantics [valid_from, valid_until)
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_until > v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    latest_versions_prev AS (
        -- Find the single, most recent version of each unit that was active at any point
        -- during the *previous* period.
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    stock_at_end_of_curr AS (
        -- This CTE defines the "stock" of existing units for demographic counts.
        -- It filters `latest_versions_curr` to only those units that survived past the end of the current period.
        SELECT * FROM latest_versions_curr lvc
        WHERE lvc.valid_until > v_curr_stop
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    stock_at_end_of_prev AS (
        -- This CTE defines the "stock" of existing units at the end of the previous period.
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    changed_units AS (
        -- This CTE creates a unified view of the stock across both periods to analyze changes.
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
    -- PERF: Pre-aggregate stats_summary by facet dimensions instead of using LATERAL JOIN.
    -- This reduces complexity from O(demographics × latest_versions_curr) to O(latest_versions_curr).
    stats_by_facet AS (
        SELECT
            lvc.unit_type,
            lvc.primary_activity_category_path,
            lvc.secondary_activity_category_path,
            lvc.sector_path,
            lvc.legal_form_id,
            lvc.physical_region_path,
            lvc.physical_country_id,
            lvc.unit_size_id,
            lvc.status_id,
            COALESCE(public.jsonb_stats_summary_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.used_for_counting
        GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month,
            unit_type,
            -- Facet dimensions
            COALESCE((curr).primary_activity_category_path, (prev).primary_activity_category_path) AS primary_activity_category_path,
            COALESCE((curr).secondary_activity_category_path, (prev).secondary_activity_category_path) AS secondary_activity_category_path,
            COALESCE((curr).sector_path, (prev).sector_path) AS sector_path,
            COALESCE((curr).legal_form_id, (prev).legal_form_id) AS legal_form_id,
            COALESCE((curr).physical_region_path, (prev).physical_region_path) AS physical_region_path,
            COALESCE((curr).physical_country_id, (prev).physical_country_id) AS physical_country_id,
            COALESCE((curr).unit_size_id, (prev).unit_size_id) AS unit_size_id,
            COALESCE((curr).status_id, (prev).status_id) AS status_id,

            -- Category 1: Existence Demographics
            count((curr).unit_id)::integer AS exists_count,
            (count((curr).unit_id) - count((prev).unit_id))::integer AS exists_change,
            count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL)::integer AS exists_added_count,
            count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL)::integer AS exists_removed_count,

            -- Category 2: Countable Demographics
            count((curr).unit_id) FILTER (WHERE (curr).used_for_counting)::integer AS countable_count,
            (count((curr).unit_id) FILTER (WHERE (curr).used_for_counting) - count((prev).unit_id) FILTER (WHERE (prev).used_for_counting))::integer AS countable_change,
            count(*) FILTER (WHERE (curr).used_for_counting AND NOT COALESCE((prev).used_for_counting, false))::integer AS countable_added_count,
            count(*) FILTER (WHERE (prev).used_for_counting AND NOT COALESCE((curr).used_for_counting, false))::integer AS countable_removed_count,

            -- Category 3: Vital Statistics (Events for units active and countable during the period)
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).birth_date BETWEEN v_curr_start AND v_curr_stop)::integer AS births,
            count(*) FILTER (WHERE (last_version_in_curr).used_for_counting AND (last_version_in_curr).death_date BETWEEN v_curr_start AND v_curr_stop)::integer AS deaths,

            -- Category 4: Change Statistics (for units countable in both periods)
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
        -- PERF: Use regular LEFT JOIN instead of LATERAL JOIN.
        -- The stats_by_facet CTE pre-aggregates by the same facet dimensions,
        -- so we can join directly instead of re-scanning for each demographic row.
        COALESCE(sbf.stats_summary, '{}'::jsonb) AS stats_summary
    FROM demographics d
    LEFT JOIN stats_by_facet sbf ON
        sbf.unit_type = d.unit_type
        AND sbf.primary_activity_category_path IS NOT DISTINCT FROM d.primary_activity_category_path
        AND sbf.secondary_activity_category_path IS NOT DISTINCT FROM d.secondary_activity_category_path
        AND sbf.sector_path IS NOT DISTINCT FROM d.sector_path
        AND sbf.legal_form_id IS NOT DISTINCT FROM d.legal_form_id
        AND sbf.physical_region_path IS NOT DISTINCT FROM d.physical_region_path
        AND sbf.physical_country_id IS NOT DISTINCT FROM d.physical_country_id
        AND sbf.unit_size_id IS NOT DISTINCT FROM d.unit_size_id
        AND sbf.status_id IS NOT DISTINCT FROM d.status_id;

END;
$statistical_history_facet_def$;

END;
