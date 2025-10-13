```sql
CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(p_resolution history_resolution, p_year integer, p_month integer)
 RETURNS SETOF statistical_history_facet_type
 LANGUAGE plpgsql
AS $function$
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
        -- FINESSE: This CTE is the heart of the statistical summary logic. It finds the
        -- single, most recent version of each unit that was active at any point during
        -- the *current* period. This set of units represents all entities that had
        -- economic activity and must be included in the `stats_summary`.
        --
        -- CRITICAL: An explicit inclusive-range overlap check (`valid_to >= period_start
        -- AND valid_from <= period_end`) is used. The custom `from_to_overlaps`
        -- function has different semantics that incorrectly included units that had
        -- already died before the current period began, which was a primary source of
        -- the regression. This explicit check is the beacon of correctness.
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_curr_stop AND uip.valid_to >= v_curr_start
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    units_at_end_of_curr AS (
        -- FINESSE: This CTE defines the "stock" of units for demographic counts (births, deaths, changes).
        -- It filters `latest_versions_curr` to only those units that survived past the end of the current period.
        --
        -- CRITICAL: The temporal logic here uses an "end of day" semantic. A unit is counted
        -- in the stock if its `valid_until` is *after* the period's stop date (`> v_curr_stop`).
        -- A unit dying *on* the last day of the period is therefore correctly excluded from the final stock count.
        SELECT * FROM latest_versions_curr lvc
        WHERE lvc.valid_until > v_curr_stop
          AND lvc.used_for_counting
          AND COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop
          AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop)
    ),
    latest_versions_prev AS (
        SELECT DISTINCT ON (uip.unit_id, uip.unit_type) uip.*
        FROM units_in_period AS uip
        WHERE uip.valid_from <= v_prev_stop
        ORDER BY uip.unit_id, uip.unit_type, uip.valid_from DESC, uip.valid_until DESC
    ),
    units_at_end_of_prev AS (
        SELECT * FROM latest_versions_prev lvp
        WHERE lvp.valid_until > v_prev_stop
          AND lvp.used_for_counting
          AND COALESCE(lvp.birth_date, lvp.valid_from) <= v_prev_stop
          AND (lvp.death_date IS NULL OR lvp.death_date > v_prev_stop)
    ),
    -- The Statbus Demographic Model ("End of Day" Stock)
    -- A unit's `death_date` is the last full day it was alive. Its first day of being dead is the next day.
    -- The "stock" at a period's end (e.g., at `v_curr_stop`) is measured based on the state at the *end* of that day.
    -- Therefore, a unit dying on the last day of the period is EXCLUDED from that period's final stock.
    --
    -- BIRTHS: Any unit that enters the reportable stock.
    -- DEATHS: Any unit that exits the reportable stock.
    --
    changed_units AS (
        SELECT
            COALESCE(c.unit_id, p.unit_id) AS unit_id,
            COALESCE(c.unit_type, p.unit_type) AS unit_type,
            c AS curr,
            p AS prev,
            lvc AS last_version_in_curr,
            -- A true "death" event is defined by the death_date falling within the period.
            -- The death_date MUST be sourced from the latest version of the unit in the
            -- current period (lvc), because the previous period's version (p) will not
            -- have the death_date if the unit died during the current period.
            (lvc.death_date IS NOT NULL AND lvc.death_date BETWEEN v_curr_start AND v_curr_stop) AS is_demographic_death
        FROM units_at_end_of_curr c
        FULL JOIN units_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id) AND lvc.unit_type = COALESCE(p.unit_type, c.unit_type)
    ),
    demographics AS (
        SELECT
            p_resolution, p_year, p_month,
            unit_type,
            COALESCE((curr).primary_activity_category_path, (prev).primary_activity_category_path) AS primary_activity_category_path,
            COALESCE((curr).secondary_activity_category_path, (prev).secondary_activity_category_path) AS secondary_activity_category_path,
            COALESCE((curr).sector_path, (prev).sector_path) AS sector_path,
            COALESCE((curr).legal_form_id, (prev).legal_form_id) AS legal_form_id,
            COALESCE((curr).physical_region_path, (prev).physical_region_path) AS physical_region_path,
            COALESCE((curr).physical_country_id, (prev).physical_country_id) AS physical_country_id,
            COALESCE((curr).unit_size_id, (prev).unit_size_id) AS unit_size_id,
            COALESCE((curr).status_id, (prev).status_id) AS status_id,
            count((curr).unit_id) AS count,
            count((curr).unit_id) FILTER (WHERE (prev).unit_id IS NULL)::integer AS births,
            count((prev).unit_id) FILTER (WHERE (curr).unit_id IS NULL AND is_demographic_death)::integer AS deaths,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).name IS DISTINCT FROM (prev).name)::integer AS name_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).primary_activity_category_path IS DISTINCT FROM (prev).primary_activity_category_path)::integer AS primary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).secondary_activity_category_path IS DISTINCT FROM (prev).secondary_activity_category_path)::integer AS secondary_activity_category_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).sector_path IS DISTINCT FROM (prev).sector_path)::integer AS sector_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).legal_form_id IS DISTINCT FROM (prev).legal_form_id)::integer AS legal_form_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).physical_region_path IS DISTINCT FROM (prev).physical_region_path)::integer AS physical_region_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).physical_country_id IS DISTINCT FROM (prev).physical_country_id)::integer AS physical_country_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND ((curr).physical_address_part1, (curr).physical_address_part2, (curr).physical_address_part3, (curr).physical_postcode, (curr).physical_postplace) IS DISTINCT FROM ((prev).physical_address_part1, (prev).physical_address_part2, (prev).physical_address_part3, (prev).physical_postcode, (prev).physical_postplace))::integer AS physical_address_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).unit_size_id IS DISTINCT FROM (prev).unit_size_id)::integer AS unit_size_change_count,
            count(*) FILTER (WHERE (prev).unit_id IS NOT NULL AND (curr).unit_id IS NOT NULL AND (curr).status_id IS DISTINCT FROM (prev).status_id)::integer AS status_change_count
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
        d.count,
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
        ss.stats_summary
    FROM demographics d
    LEFT JOIN LATERAL (
        -- FINESSE: The `stats_summary` is calculated here, separately from the demographic counts.
        --
        -- CRITICAL: This subquery aggregates summaries from `latest_versions_curr`, which represents
        -- all units active *during* the period. This correctly includes the economic activity of units
        -- that died before the period ended. This is semantically different from the `demographics`
        -- CTE, which is concerned only with the final "stock" of units. This separation is the
        -- key to fixing the statistical regression. The JOIN conditions ensure the summary is
        -- calculated for the correct facet group.
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
$function$
```
