BEGIN;

SELECT pg_catalog.set_config('search_path', 'public', false);

DROP VIEW IF EXISTS public.statistical_history_def;
DROP FUNCTION IF EXISTS public.statistical_history_def(public.history_resolution, integer, integer);
DROP TYPE IF EXISTS public.statistical_history_type;

-- This type defines the SCHEMA for the `statistical_history` table.
CREATE TYPE public.statistical_history_type AS (
    resolution public.history_resolution,
    year integer,
    month integer,
    unit_type public.statistical_unit_type,
    --
    -- The Statbus Demographic Model ("End of Day" Stock)
    -- A unit's `death_date` is the last full day it was alive. Its first day of being dead is the next day.
    -- The "stock" at a period's end (e.g., Dec 31st) is measured based on the state at the *end* of that day.
    -- Therefore, a unit dying on the last day of the period is EXCLUDED from that period's final stock count.
    -- This stock is the basis for all demographic calculations below.

    -- Category 1: Existence Demographics (All units, regardless of status)
    -- How many units exist at the end of the period?
    exists_count integer,
    -- Net change in the number of existing units from the previous period.
    exists_change integer,
    -- How many units were added to the stock this period (churn).
    exists_added_count integer,
    -- How many units were removed from the stock this period (churn).
    exists_removed_count integer,

    -- Category 2: Countable Demographics (Units with `status.used_for_counting` = true)
    -- How many "countable" units are in the stock at the end of the period? This is the primary business metric.
    countable_count integer,
    -- Net change in the number of "countable" units from the previous period.
    countable_change integer,
    -- How many units became "countable" this period (churn). This includes brand new units and existing units that changed status.
    countable_added_count integer,
    -- How many units stopped being "countable" this period (churn). This includes units that died and units that changed status.
    countable_removed_count integer,

    -- Category 3: Vital Statistics (Events for "Countable" units during the period)
    -- These are event-based counts, not stock-based churn.
    -- How many "countable" units were officially born (birth_date) during this period?
    births integer,
    -- How many "countable" units officially died (death_date) during this period?
    deaths integer,

    -- Category 4: Change Statistics (Attribute changes for "Countable" units that existed in both periods)
    -- For units that were "countable" at the end of the previous period AND at the end of the current period,
    -- how many of them changed specific attributes?
    name_change_count integer,
    primary_activity_category_change_count integer,
    secondary_activity_category_change_count integer,
    sector_change_count integer,
    legal_form_change_count integer,
    physical_region_change_count integer,
    physical_country_change_count integer,
    physical_address_change_count integer,
    stats_summary jsonb
);

-- This function is the single source of truth for calculating history metrics for a single period.
CREATE FUNCTION public.statistical_history_def(
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
        SELECT *
        FROM public.statistical_unit su
        WHERE from_to_overlaps(su.valid_from, su.valid_to, v_prev_start, v_curr_stop)
    ),
    latest_versions_curr AS (
        -- Find the single, most recent version of each unit that was active at any point
        -- during the *current* period. This represents all entities with economic activity.
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
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
        -- A unit is in the stock if its `valid_until` is *after* the period's stop date (`> v_curr_stop`).
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
            c AS curr, -- The full record from the current period's stock
            p AS prev, -- The full record from the previous period's stock
            lvc AS last_version_in_curr -- The latest version active *during* the current period (for event dates)
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month, unit_type,
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
        ss.stats_summary
    FROM demographics d
    LEFT JOIN LATERAL (
        -- FINESSE: The `stats_summary` is calculated here, separately from the demographic counts.
        -- It aggregates summaries from `latest_versions_curr`, which represents all units active
        -- *during* the period, correctly including economic activity from units that died before
        -- the period ended. This is semantically different from the `demographics` CTE, which
        -- is concerned only with the final "stock" of units.
        SELECT COALESCE(public.jsonb_stats_summary_merge_agg(lvc.stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr lvc
        WHERE lvc.unit_type = d.unit_type AND lvc.used_for_counting
    ) ss ON true;
END;
$statistical_history_def$;

-- Reset the search path such that all things must have an explicit namespace.
SELECT pg_catalog.set_config('search_path', '', false);

END;
