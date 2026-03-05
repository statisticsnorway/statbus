```sql
CREATE OR REPLACE FUNCTION public.statistical_history_facet_def(p_resolution history_resolution, p_year integer, p_month integer, p_partition_seq integer DEFAULT NULL::integer)
 RETURNS SETOF statistical_history_facet_type
 LANGUAGE plpgsql
AS $function$
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
    -- PERF: Pre-aggregate stats with composite key for fast hash join.
    -- The composite key concatenates all facet dimensions with '|' separator,
    -- using COALESCE to convert NULLs to empty strings (hashable).
    -- This enables a single-column equality join instead of IS NOT DISTINCT FROM
    -- on 9 nullable columns, which prevents hash joins.
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
            COALESCE(public.jsonb_stats_merge_agg(stats_summary), '{}'::jsonb) AS stats_summary
        FROM latest_versions_curr
        WHERE used_for_counting
        GROUP BY 1
    ),
    -- PERF: Flatten columns instead of storing entire ROW types.
    -- Accessing fields from composite ROW types (e.g., (curr).name) is expensive
    -- when done repeatedly in aggregate FILTER clauses. Flattening to plain columns
    -- avoids repeated detoasting and field extraction.
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
        FROM stock_at_end_of_curr c
        FULL JOIN stock_at_end_of_prev p ON c.unit_id = p.unit_id AND c.unit_type = p.unit_type
        LEFT JOIN latest_versions_curr lvc ON lvc.unit_id = COALESCE(p.unit_id, c.unit_id)
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
            -- PERF: Composite key matches stats_by_facet for hash join
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
$function$
```
