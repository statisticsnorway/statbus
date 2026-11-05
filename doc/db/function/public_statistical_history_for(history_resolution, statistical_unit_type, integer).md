```sql
CREATE OR REPLACE FUNCTION public.statistical_history_for(p_resolution history_resolution, p_unit_type statistical_unit_type, p_year integer DEFAULT NULL::integer)
 RETURNS SETOF statistical_history
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH period AS MATERIALIZED (
        SELECT p.resolution, p.year, p.month, p.curr_stop FROM public.statistical_history_period AS p
         WHERE p.resolution = p_resolution AND (p_year IS NULL OR p.year = p_year)
    ), per_month AS MATERIALIZED (
        SELECT d.on_month, sum(d.exists_delta) AS exists_delta, sum(d.countable_delta) AS countable_delta,
               public.jsonb_stats_delta_agg(d.stats_delta) FILTER (WHERE d.stats_delta IS NOT NULL) AS stats_delta
          FROM public.statistical_history_facet_stock_delta AS d
         WHERE d.unit_type = p_unit_type AND d.on_month <= (SELECT max(curr_stop) FROM period)
         GROUP BY 1
    ), stock AS MATERIALIZED (
        SELECT p.year, p.month, sum(m.exists_delta) AS exists_count, sum(m.countable_delta) AS countable_count,
               public.jsonb_stats_delta_agg(m.stats_delta) FILTER (WHERE m.stats_delta IS NOT NULL) AS stats_stock
          FROM period AS p JOIN per_month AS m ON m.on_month <= p.curr_stop
         GROUP BY 1, 2
    ), flow AS MATERIALIZED (
        SELECT f.year, f.month,
               ARRAY[sum(f.flows[1]), sum(f.flows[2]), sum(f.flows[3]), sum(f.flows[4]), sum(f.flows[5]), sum(f.flows[6]),
                     sum(f.flows[7]), sum(f.flows[8]), sum(f.flows[9]), sum(f.flows[10]), sum(f.flows[11]), sum(f.flows[12]),
                     sum(f.flows[13]), sum(f.flows[14]), sum(f.flows[15]), sum(f.flows[16]), sum(f.flows[17]),
                     sum(f.flows[18])]::integer[] AS flows,
               public.jsonb_stats_delta_agg(f.stats_ended) FILTER (WHERE f.stats_ended IS NOT NULL) AS stats_ended
          FROM public.statistical_history_facet_flow_delta AS f
          JOIN period AS p ON p.year = f.year AND COALESCE(p.month, 0) = COALESCE(f.month, 0)
         WHERE f.resolution = p_resolution AND f.unit_type = p_unit_type
           AND (p_year IS NULL OR f.year = p_year)
         GROUP BY 1, 2
    )
    SELECT p_resolution, COALESCE(s.year, f.year), COALESCE(s.month, f.month), p_unit_type,
           COALESCE(s.exists_count, 0)::integer,
           COALESCE(f.flows[1], 0), COALESCE(f.flows[2], 0), COALESCE(f.flows[3], 0),
           COALESCE(s.countable_count, 0)::integer,
           COALESCE(f.flows[4], 0), COALESCE(f.flows[5], 0), COALESCE(f.flows[6], 0),
           COALESCE(f.flows[7], 0), COALESCE(f.flows[8], 0), COALESCE(f.flows[9], 0),
           COALESCE(f.flows[10], 0), COALESCE(f.flows[11], 0), COALESCE(f.flows[12], 0), COALESCE(f.flows[13], 0),
           COALESCE(f.flows[14], 0), COALESCE(f.flows[15], 0), COALESCE(f.flows[16], 0),
           COALESCE(public.jsonb_stats_delta_to_agg(public.jsonb_stats_delta_merge(
               COALESCE(s.stats_stock, '{"type": "stats_delta"}'), COALESCE(f.stats_ended, '{"type": "stats_delta"}'))),
               '{}'::jsonb),
           NULL::int4range
      FROM stock AS s
      FULL JOIN flow AS f ON f.year = s.year AND COALESCE(f.month, 0) = COALESCE(s.month, 0)
     WHERE COALESCE(s.exists_count, 0) <> 0 OR COALESCE(s.countable_count, 0) <> 0 OR f.year IS NOT NULL
$function$
```
