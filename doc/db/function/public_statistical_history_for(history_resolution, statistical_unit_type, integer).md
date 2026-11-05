```sql
CREATE OR REPLACE FUNCTION public.statistical_history_for(p_resolution history_resolution, p_unit_type statistical_unit_type, p_year integer DEFAULT NULL::integer)
 RETURNS TABLE(resolution history_resolution, year integer, month integer, unit_type statistical_unit_type, exists_count integer, exists_change integer, exists_added_count integer, exists_removed_count integer, countable_count integer, countable_change integer, countable_added_count integer, countable_removed_count integer, births integer, deaths integer, name_change_count integer, primary_activity_category_change_count integer, secondary_activity_category_change_count integer, sector_change_count integer, legal_form_change_count integer, physical_region_change_count integer, physical_country_change_count integer, physical_address_change_count integer, stats_summary jsonb, exists_moved_in_count integer, exists_moved_out_count integer, countable_moved_in_count integer, countable_moved_out_count integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH period AS MATERIALIZED (
        SELECT p.year, p.month, p.curr_start, p.curr_stop FROM public.statistical_history_period AS p
         WHERE p.resolution = p_resolution AND (p_year IS NULL OR p.year = p_year)
    ), per_month AS MATERIALIZED (
        SELECT d.on_month,
               sum(d.exists_added_count - d.exists_removed_count + d.exists_moved_in_count - d.exists_moved_out_count) AS exists_net,
               sum(d.countable_added_count - d.countable_removed_count + d.countable_moved_in_count - d.countable_moved_out_count) AS countable_net,
               sum(d.exists_added_count) AS exists_added_count, sum(d.exists_removed_count) AS exists_removed_count,
               sum(d.countable_added_count) AS countable_added_count, sum(d.countable_removed_count) AS countable_removed_count,
               sum(d.exists_moved_in_count) AS exists_moved_in_count, sum(d.exists_moved_out_count) AS exists_moved_out_count,
               sum(d.countable_moved_in_count) AS countable_moved_in_count, sum(d.countable_moved_out_count) AS countable_moved_out_count,
               sum(d.births) AS births, sum(d.deaths) AS deaths, sum(d.name_change_count) AS name_change_count,
               sum(d.primary_activity_category_change_count) AS primary_activity_category_change_count,
               sum(d.secondary_activity_category_change_count) AS secondary_activity_category_change_count,
               sum(d.sector_change_count) AS sector_change_count, sum(d.legal_form_change_count) AS legal_form_change_count,
               sum(d.physical_region_change_count) AS physical_region_change_count,
               sum(d.physical_country_change_count) AS physical_country_change_count,
               sum(d.physical_address_change_count) AS physical_address_change_count,
               public.jsonb_stats_delta_agg(d.stats_delta) FILTER (WHERE d.stats_delta IS NOT NULL) AS stats_delta,
               public.jsonb_stats_delta_agg(CASE p_resolution WHEN 'year' THEN d.stats_ended_year ELSE d.stats_ended_month END)
                   FILTER (WHERE CASE p_resolution WHEN 'year' THEN d.stats_ended_year ELSE d.stats_ended_month END IS NOT NULL) AS stats_ended
          FROM public.statistical_history_facet_delta AS d
         WHERE d.unit_type = p_unit_type AND d.on_month <= (SELECT max(curr_stop) FROM period)
         GROUP BY 1
    ), summed AS MATERIALIZED (
        SELECT p.year, p.month,
               sum(m.exists_net) AS exists_count, sum(m.countable_net) AS countable_count,
               public.jsonb_stats_delta_agg(m.stats_delta) FILTER (WHERE m.stats_delta IS NOT NULL) AS stats_stock,
               sum(m.exists_net) FILTER (WHERE m.on_month >= p.curr_start) AS exists_change,
               sum(m.exists_added_count) FILTER (WHERE m.on_month >= p.curr_start) AS exists_added_count,
               sum(m.exists_removed_count) FILTER (WHERE m.on_month >= p.curr_start) AS exists_removed_count,
               sum(m.countable_net) FILTER (WHERE m.on_month >= p.curr_start) AS countable_change,
               sum(m.countable_added_count) FILTER (WHERE m.on_month >= p.curr_start) AS countable_added_count,
               sum(m.countable_removed_count) FILTER (WHERE m.on_month >= p.curr_start) AS countable_removed_count,
               sum(m.exists_moved_in_count) FILTER (WHERE m.on_month >= p.curr_start) AS exists_moved_in_count,
               sum(m.exists_moved_out_count) FILTER (WHERE m.on_month >= p.curr_start) AS exists_moved_out_count,
               sum(m.countable_moved_in_count) FILTER (WHERE m.on_month >= p.curr_start) AS countable_moved_in_count,
               sum(m.countable_moved_out_count) FILTER (WHERE m.on_month >= p.curr_start) AS countable_moved_out_count,
               sum(m.births) FILTER (WHERE m.on_month >= p.curr_start) AS births,
               sum(m.deaths) FILTER (WHERE m.on_month >= p.curr_start) AS deaths,
               sum(m.name_change_count) FILTER (WHERE m.on_month >= p.curr_start) AS name_change_count,
               sum(m.primary_activity_category_change_count) FILTER (WHERE m.on_month >= p.curr_start) AS primary_activity_category_change_count,
               sum(m.secondary_activity_category_change_count) FILTER (WHERE m.on_month >= p.curr_start) AS secondary_activity_category_change_count,
               sum(m.sector_change_count) FILTER (WHERE m.on_month >= p.curr_start) AS sector_change_count,
               sum(m.legal_form_change_count) FILTER (WHERE m.on_month >= p.curr_start) AS legal_form_change_count,
               sum(m.physical_region_change_count) FILTER (WHERE m.on_month >= p.curr_start) AS physical_region_change_count,
               sum(m.physical_country_change_count) FILTER (WHERE m.on_month >= p.curr_start) AS physical_country_change_count,
               sum(m.physical_address_change_count) FILTER (WHERE m.on_month >= p.curr_start) AS physical_address_change_count,
               public.jsonb_stats_delta_agg(m.stats_ended) FILTER (WHERE m.on_month >= p.curr_start AND m.stats_ended IS NOT NULL) AS stats_ended
          FROM period AS p JOIN per_month AS m ON m.on_month <= p.curr_stop
         GROUP BY 1, 2
    )
    SELECT p_resolution, s.year, s.month, p_unit_type,
           s.exists_count::integer, COALESCE(s.exists_change, 0)::integer, COALESCE(s.exists_added_count, 0)::integer,
           COALESCE(s.exists_removed_count, 0)::integer, s.countable_count::integer,
           COALESCE(s.countable_change, 0)::integer, COALESCE(s.countable_added_count, 0)::integer,
           COALESCE(s.countable_removed_count, 0)::integer, COALESCE(s.births, 0)::integer, COALESCE(s.deaths, 0)::integer,
           COALESCE(s.name_change_count, 0)::integer, COALESCE(s.primary_activity_category_change_count, 0)::integer,
           COALESCE(s.secondary_activity_category_change_count, 0)::integer, COALESCE(s.sector_change_count, 0)::integer,
           COALESCE(s.legal_form_change_count, 0)::integer, COALESCE(s.physical_region_change_count, 0)::integer,
           COALESCE(s.physical_country_change_count, 0)::integer, COALESCE(s.physical_address_change_count, 0)::integer,
           COALESCE(public.jsonb_stats_delta_to_agg(public.jsonb_stats_delta_nullif_zero(
               CASE WHEN s.stats_stock IS NULL THEN s.stats_ended
                    WHEN s.stats_ended IS NULL THEN s.stats_stock
                    ELSE public.jsonb_stats_delta_merge(s.stats_stock, s.stats_ended) END)), '{}'::jsonb),
           COALESCE(s.exists_moved_in_count, 0)::integer, COALESCE(s.exists_moved_out_count, 0)::integer,
           COALESCE(s.countable_moved_in_count, 0)::integer, COALESCE(s.countable_moved_out_count, 0)::integer
      FROM summed AS s
     WHERE s.exists_count <> 0 OR s.countable_count <> 0
        OR s.exists_added_count <> 0 OR s.exists_removed_count <> 0 OR s.countable_added_count <> 0
        OR s.countable_removed_count <> 0 OR s.births <> 0 OR s.deaths <> 0 OR s.name_change_count <> 0
        OR s.primary_activity_category_change_count <> 0 OR s.secondary_activity_category_change_count <> 0
        OR s.sector_change_count <> 0 OR s.legal_form_change_count <> 0 OR s.physical_region_change_count <> 0
        OR s.physical_country_change_count <> 0 OR s.physical_address_change_count <> 0
        OR s.exists_moved_in_count <> 0 OR s.stats_ended IS NOT NULL
     ORDER BY s.year, s.month NULLS FIRST
$function$
```
