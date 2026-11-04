```sql
CREATE OR REPLACE FUNCTION public.statistical_history_drilldown(unit_type statistical_unit_type DEFAULT 'enterprise'::statistical_unit_type, resolution history_resolution DEFAULT 'year'::history_resolution, year integer DEFAULT NULL::integer, region_path ltree DEFAULT NULL::ltree, activity_category_path ltree DEFAULT NULL::ltree, sector_path ltree DEFAULT NULL::ltree, status_id integer DEFAULT NULL::integer, legal_form_id integer DEFAULT NULL::integer, country_id integer DEFAULT NULL::integer, year_min integer DEFAULT NULL::integer, year_max integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH params AS MATERIALIZED (
        SELECT unit_type AS param_unit_type, resolution AS param_resolution, year AS param_year,
               region_path AS param_region_path, activity_category_path AS param_activity_category_path,
               sector_path AS param_sector_path, legal_form_id AS param_legal_form_id, status_id AS param_status_id,
               country_id AS param_country_id,
               statistical_history_drilldown.year_min AS param_year_min,
               statistical_history_drilldown.year_max AS param_year_max,
               -- The unit types to read, as an array the indexes on unit_type can use (NULL: all).
               CASE WHEN unit_type IS NULL THEN enum_range(NULL::public.statistical_unit_type)
                    ELSE ARRAY[unit_type] END AS param_unit_types
    ), settings_activity_category_standard AS (
        SELECT activity_category_standard_id AS id FROM public.settings
    ),
    -- The asked periods.
    period AS MATERIALIZED (
        SELECT p.resolution, p.year, p.month, p.curr_stop
          FROM public.statistical_history_period AS p, params
         WHERE (param_resolution IS NULL OR p.resolution = param_resolution)
           AND (param_year IS NULL OR p.year = param_year)
           AND (param_year_min IS NULL OR p.year >= param_year_min)
           AND (param_year_max IS NULL OR p.year <= param_year_max)
    ),
    -- Stock deltas of the asked unit type that pass every filter. Rows dated after the last asked period end
    -- cannot reach any period.
    stock AS MATERIALIZED (
        SELECT d.primary_activity_category_path, d.sector_path, d.legal_form_id, d.physical_region_path,
               d.physical_country_id, d.status_id, d.on_month, d.exists_delta, d.countable_delta
          FROM public.statistical_history_facet_stock_delta AS d, params
         WHERE d.unit_type = ANY (ARRAY(SELECT unnest(param_unit_types) FROM params))
           AND d.on_month <= (SELECT max(curr_stop) FROM period)
           AND (param_region_path IS NULL OR d.physical_region_path IS NOT NULL AND d.physical_region_path OPERATOR(public.<@) param_region_path)
           AND (param_activity_category_path IS NULL OR d.primary_activity_category_path IS NOT NULL AND d.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path)
           AND (param_sector_path IS NULL OR d.sector_path IS NOT NULL AND d.sector_path OPERATOR(public.<@) param_sector_path)
           AND (param_legal_form_id IS NULL OR d.legal_form_id IS NOT NULL AND d.legal_form_id = param_legal_form_id)
           AND (param_status_id IS NULL OR d.status_id IS NOT NULL AND d.status_id = param_status_id)
           AND (param_country_id IS NULL OR d.physical_country_id IS NOT NULL AND d.physical_country_id = param_country_id)
    ),
    -- How many asked period ends each month's deltas reach.
    month_periods AS MATERIALIZED (
        SELECT m.on_month, (SELECT count(*) FROM period AS p WHERE m.on_month <= p.curr_stop) AS periods
          FROM (SELECT DISTINCT on_month FROM stock) AS m
    ),
    -- A breakdown count is the countable stock at each asked period end, summed over the periods. The stock
    -- at an end is the sum of the deltas up to it, so the total is each delta times the periods it reaches.
    weight AS MATERIALIZED (
        SELECT s.primary_activity_category_path, s.sector_path, s.legal_form_id, s.physical_region_path,
               s.physical_country_id, s.status_id, s.countable_delta * mp.periods AS count
          FROM stock AS s JOIN month_periods AS mp USING (on_month)
         WHERE s.countable_delta <> 0
    ),
    flow AS MATERIALIZED (
        SELECT f.year, f.month,
               sum(f.flows[1])::bigint AS exists_change, sum(f.flows[2])::bigint AS exists_added_count,
               sum(f.flows[3])::bigint AS exists_removed_count, sum(f.flows[4])::bigint AS countable_change,
               sum(f.flows[5])::bigint AS countable_added_count, sum(f.flows[6])::bigint AS countable_removed_count,
               sum(f.flows[7])::bigint AS births, sum(f.flows[8])::bigint AS deaths,
               sum(f.flows[9])::bigint AS name_change_count, sum(f.flows[10])::bigint AS primary_activity_category_change_count,
               sum(f.flows[11])::bigint AS secondary_activity_category_change_count, sum(f.flows[12])::bigint AS sector_change_count,
               sum(f.flows[13])::bigint AS legal_form_change_count, sum(f.flows[14])::bigint AS physical_region_change_count,
               sum(f.flows[15])::bigint AS physical_country_change_count, sum(f.flows[16])::bigint AS physical_address_change_count,
               sum(f.flows[17])::bigint AS unit_size_change_count, sum(f.flows[18])::bigint AS status_change_count,
               public.jsonb_stats_delta_agg(f.stats_ended) FILTER (WHERE f.stats_ended IS NOT NULL) AS stats_ended
          FROM public.statistical_history_facet_flow_delta AS f
          JOIN period AS p ON p.resolution = f.resolution AND p.year = f.year AND COALESCE(p.month, 0) = COALESCE(f.month, 0)
             , params
         -- One index range per asked resolution and year; the month is matched in the join.
         WHERE f.resolution = ANY (ARRAY(SELECT DISTINCT resolution FROM period))
           AND f.year = ANY (ARRAY(SELECT DISTINCT year FROM period))
           AND f.unit_type = ANY (ARRAY(SELECT unnest(param_unit_types) FROM params))
           AND (param_region_path IS NULL OR f.physical_region_path IS NOT NULL AND f.physical_region_path OPERATOR(public.<@) param_region_path)
           AND (param_activity_category_path IS NULL OR f.primary_activity_category_path IS NOT NULL AND f.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path)
           AND (param_sector_path IS NULL OR f.sector_path IS NOT NULL AND f.sector_path OPERATOR(public.<@) param_sector_path)
           AND (param_legal_form_id IS NULL OR f.legal_form_id IS NOT NULL AND f.legal_form_id = param_legal_form_id)
           AND (param_status_id IS NULL OR f.status_id IS NOT NULL AND f.status_id = param_status_id)
           AND (param_country_id IS NULL OR f.physical_country_id IS NOT NULL AND f.physical_country_id = param_country_id)
         GROUP BY 1, 2
    ),
    -- Stats of the stock: per month first, then per period end.
    stats_month AS MATERIALIZED (
        SELECT d.on_month, public.jsonb_stats_delta_agg(d.stats_delta) AS stats_delta
          FROM public.statistical_history_facet_stock_delta AS d, params
         WHERE d.stats_delta IS NOT NULL
           AND d.unit_type = ANY (ARRAY(SELECT unnest(param_unit_types) FROM params))
           AND d.on_month <= (SELECT max(curr_stop) FROM period)
           AND (param_region_path IS NULL OR d.physical_region_path IS NOT NULL AND d.physical_region_path OPERATOR(public.<@) param_region_path)
           AND (param_activity_category_path IS NULL OR d.primary_activity_category_path IS NOT NULL AND d.primary_activity_category_path OPERATOR(public.<@) param_activity_category_path)
           AND (param_sector_path IS NULL OR d.sector_path IS NOT NULL AND d.sector_path OPERATOR(public.<@) param_sector_path)
           AND (param_legal_form_id IS NULL OR d.legal_form_id IS NOT NULL AND d.legal_form_id = param_legal_form_id)
           AND (param_status_id IS NULL OR d.status_id IS NOT NULL AND d.status_id = param_status_id)
           AND (param_country_id IS NULL OR d.physical_country_id IS NOT NULL AND d.physical_country_id = param_country_id)
         GROUP BY 1
    ),
    count_month AS MATERIALIZED (
        SELECT s.on_month, sum(s.exists_delta) AS exists_delta, sum(s.countable_delta) AS countable_delta
          FROM stock AS s GROUP BY 1
    ),
    stock_period AS MATERIALIZED (
        SELECT p.year, p.month,
               COALESCE((SELECT sum(c.exists_delta) FROM count_month AS c WHERE c.on_month <= p.curr_stop), 0) AS exists_count,
               COALESCE((SELECT sum(c.countable_delta) FROM count_month AS c WHERE c.on_month <= p.curr_stop), 0) AS countable_count,
               (SELECT public.jsonb_stats_delta_agg(m.stats_delta) FROM stats_month AS m WHERE m.on_month <= p.curr_stop) AS stats_stock
          FROM period AS p
    ),
    available_history_stats AS (
        SELECT sp.year, sp.month
             , sp.exists_count::integer AS exists_count
             , COALESCE(f.exists_change, 0)::integer AS exists_change
             , COALESCE(f.exists_added_count, 0)::integer AS exists_added_count
             , COALESCE(f.exists_removed_count, 0)::integer AS exists_removed_count
             , sp.countable_count::integer AS countable_count
             , COALESCE(f.countable_change, 0)::integer AS countable_change
             , COALESCE(f.countable_added_count, 0)::integer AS countable_added_count
             , COALESCE(f.countable_removed_count, 0)::integer AS countable_removed_count
             , COALESCE(f.births, 0)::integer AS births
             , COALESCE(f.deaths, 0)::integer AS deaths
             , COALESCE(f.name_change_count, 0)::integer AS name_change_count
             , COALESCE(f.primary_activity_category_change_count, 0)::integer AS primary_activity_category_change_count
             , COALESCE(f.secondary_activity_category_change_count, 0)::integer AS secondary_activity_category_change_count
             , COALESCE(f.sector_change_count, 0)::integer AS sector_change_count
             , COALESCE(f.legal_form_change_count, 0)::integer AS legal_form_change_count
             , COALESCE(f.physical_region_change_count, 0)::integer AS physical_region_change_count
             , COALESCE(f.physical_country_change_count, 0)::integer AS physical_country_change_count
             , COALESCE(f.physical_address_change_count, 0)::integer AS physical_address_change_count
             , COALESCE(f.unit_size_change_count, 0)::integer AS unit_size_change_count
             , COALESCE(f.status_change_count, 0)::integer AS status_change_count
             , COALESCE(public.jsonb_stats_delta_to_agg(
                   CASE WHEN sp.stats_stock IS NULL THEN f.stats_ended
                        WHEN f.stats_ended IS NULL THEN sp.stats_stock
                        ELSE public.jsonb_stats_delta_merge(sp.stats_stock, f.stats_ended) END), '{"type": "stats_agg"}'::jsonb) AS stats_summary
          FROM stock_period AS sp
          LEFT JOIN flow AS f ON f.year = sp.year AND f.month IS NOT DISTINCT FROM sp.month
         WHERE sp.exists_count <> 0 OR sp.countable_count <> 0 OR f.year IS NOT NULL
         ORDER BY sp.year ASC, sp.month ASC NULLS FIRST
    ),
    breadcrumb_region AS (
        SELECT r.path, r.label, r.code, r.name FROM public.region AS r
         WHERE region_path IS NOT NULL AND r.path OPERATOR(public.@>) (region_path)
         ORDER BY path
    ),
    available_region AS (
        SELECT r.path, r.label, r.code, r.name FROM public.region AS r
         WHERE (region_path IS NULL AND r.path OPERATOR(public.~) '*{1}'::public.lquery)
            OR (region_path IS NOT NULL AND r.path OPERATOR(public.~) (region_path::text || '.*{1}')::public.lquery)
         ORDER BY r.path
    ), region_weight AS (
        SELECT w.physical_region_path AS path, sum(w.count) AS count
          FROM weight AS w WHERE w.physical_region_path IS NOT NULL GROUP BY 1
    ), aggregated_region_counts AS (
        SELECT ar.path, ar.label, ar.code, ar.name
             , COALESCE(SUM(rw.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE rw.path OPERATOR(public.<>) ar.path AND rw.count <> 0), false) AS has_children
          FROM available_region AS ar
          LEFT JOIN region_weight AS rw ON rw.path OPERATOR(public.<@) ar.path
         GROUP BY ar.path, ar.label, ar.code, ar.name
    ),
    breadcrumb_activity_category AS (
        SELECT ac.path, ac.label, ac.code, ac.name FROM public.activity_category AS ac
         WHERE ac.enabled AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND activity_category_path IS NOT NULL AND ac.path OPERATOR(public.@>) activity_category_path
         ORDER BY path
    ),
    available_activity_category AS (
        SELECT ac.path, ac.label, ac.code, ac.name FROM public.activity_category AS ac
         WHERE ac.enabled AND ac.standard_id = (SELECT id FROM settings_activity_category_standard)
           AND ((activity_category_path IS NULL AND ac.path OPERATOR(public.~) '*{1}'::public.lquery)
             OR (activity_category_path IS NOT NULL AND ac.path OPERATOR(public.~) (activity_category_path::text || '.*{1}')::public.lquery))
         ORDER BY ac.path
    ), activity_weight AS (
        SELECT w.primary_activity_category_path AS path, sum(w.count) AS count
          FROM weight AS w WHERE w.primary_activity_category_path IS NOT NULL GROUP BY 1
    ), aggregated_activity_counts AS (
        SELECT aac.path, aac.label, aac.code, aac.name
             , COALESCE(SUM(aw.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE aw.path OPERATOR(public.<>) aac.path AND aw.count <> 0), false) AS has_children
          FROM available_activity_category AS aac
          LEFT JOIN activity_weight AS aw ON aw.path OPERATOR(public.<@) aac.path
         GROUP BY aac.path, aac.label, aac.code, aac.name
         ORDER BY aac.path
    ),
    breadcrumb_sector AS (
        SELECT s.path, s.label, s.code, s.name FROM public.sector AS s
         WHERE sector_path IS NOT NULL AND s.path OPERATOR(public.@>) (sector_path)
         ORDER BY s.path
    ),
    available_sector AS (
        SELECT "as".path, "as".label, "as".code, "as".name FROM public.sector AS "as"
         WHERE (sector_path IS NULL AND "as".path OPERATOR(public.~) '*{1}'::public.lquery)
            OR (sector_path IS NOT NULL AND "as".path OPERATOR(public.~) (sector_path::text || '.*{1}')::public.lquery)
         ORDER BY "as".path
    ), sector_weight AS (
        SELECT w.sector_path AS path, sum(w.count) AS count
          FROM weight AS w WHERE w.sector_path IS NOT NULL GROUP BY 1
    ), aggregated_sector_counts AS (
        SELECT "as".path, "as".label, "as".code, "as".name
             , COALESCE(SUM(sw.count), 0) AS count
             , COALESCE(bool_or(true) FILTER (WHERE sw.path OPERATOR(public.<>) "as".path AND sw.count <> 0), false) AS has_children
          FROM available_sector AS "as"
          LEFT JOIN sector_weight AS sw ON sw.path OPERATOR(public.<@) "as".path
         GROUP BY "as".path, "as".label, "as".code, "as".name
         ORDER BY "as".path
    ),
    breadcrumb_legal_form AS (
        SELECT lf.id, lf.code, lf.name FROM public.legal_form AS lf
         WHERE legal_form_id IS NOT NULL AND lf.id = legal_form_id
         ORDER BY lf.code
    ),
    available_legal_form AS (
        SELECT lf.id, lf.code, lf.name FROM public.legal_form AS lf
         -- Every legal form is available, unless one is selected.
         WHERE legal_form_id IS NULL
         ORDER BY lf.code
    ), legal_form_weight AS (
        SELECT w.legal_form_id AS id, sum(w.count) AS count FROM weight AS w WHERE w.legal_form_id IS NOT NULL GROUP BY 1
    ), aggregated_legal_form_counts AS (
        SELECT lf.id, lf.code, lf.name
             , COALESCE(lw.count, 0) AS count
             , false AS has_children
          FROM available_legal_form AS lf
          LEFT JOIN legal_form_weight AS lw ON lw.id = lf.id
         ORDER BY lf.code
    ),
    breadcrumb_status AS (
        SELECT s.id, s.code, s.name FROM public.status AS s
         WHERE status_id IS NOT NULL AND s.id = status_id
         ORDER BY s.code
    ),
    available_status AS (
        SELECT s.id, s.code, s.name FROM public.status AS s
         -- Every status is available, unless one is selected.
         WHERE status_id IS NULL
         ORDER BY s.code
    ), status_weight AS (
        SELECT w.status_id AS id, sum(w.count) AS count FROM weight AS w WHERE w.status_id IS NOT NULL GROUP BY 1
    ), aggregated_status_counts AS (
        SELECT s.id, s.code, s.name
             , COALESCE(sw.count, 0) AS count
             , false AS has_children
          FROM available_status AS s
          LEFT JOIN status_weight AS sw ON sw.id = s.id
         ORDER BY s.code
    ),
    breadcrumb_physical_country AS (
        SELECT pc.id, pc.iso_2, pc.name FROM public.country AS pc
         WHERE country_id IS NOT NULL AND pc.id = country_id
         ORDER BY pc.iso_2
    ),
    available_physical_country AS (
        SELECT pc.id, pc.iso_2, pc.name FROM public.country AS pc
         -- Every country is available, unless one is selected.
         WHERE country_id IS NULL
         ORDER BY pc.iso_2
    ), country_weight AS (
        SELECT w.physical_country_id AS id, sum(w.count) AS count
          FROM weight AS w WHERE w.physical_country_id IS NOT NULL GROUP BY 1
    ), aggregated_physical_country_counts AS (
        SELECT pc.id, pc.iso_2, pc.name
             , COALESCE(cw.count, 0) AS count
             , false AS has_children
          FROM available_physical_country AS pc
          LEFT JOIN country_weight AS cw ON cw.id = pc.id
         ORDER BY pc.iso_2
    )
    SELECT
        jsonb_build_object(
          'unit_type', unit_type,
          'stats', (SELECT jsonb_agg(to_jsonb(source.*)) FROM available_history_stats AS source),
          'breadcrumb', jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_region AS source),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_activity_category AS source),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_sector AS source),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_legal_form AS source),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_status AS source),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM breadcrumb_physical_country AS source)
          ),
          'available', jsonb_build_object(
            'region', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_region_counts AS source WHERE count > 0),
            'activity_category', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_activity_counts AS source WHERE count > 0),
            'sector', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_sector_counts AS source WHERE count > 0),
            'legal_form', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_legal_form_counts AS source WHERE count > 0),
            'status', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_status_counts AS source WHERE count > 0),
            'country', (SELECT jsonb_agg(to_jsonb(source.*)) FROM aggregated_physical_country_counts AS source WHERE count > 0)
          ),
          'filter', jsonb_build_object(
            'type', param_resolution,
            'year', param_year,
            'unit_type', param_unit_type,
            'region_path', param_region_path,
            'activity_category_path', param_activity_category_path,
            'sector_path', param_sector_path,
            'legal_form_id', param_legal_form_id,
            'status_id', param_status_id,
            'country_id', param_country_id
          )
        )
    FROM params;
$function$
```
