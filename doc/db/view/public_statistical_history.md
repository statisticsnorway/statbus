```sql
                                                                                                                     View "public.statistical_history"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  |                                                                         Description                                                                         
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------------------------------------------------------------------------------------------------------------------------------------------------------
 resolution                               | history_resolution    |           |          |         | plain    | 
 year                                     | integer               |           |          |         | plain    | 
 month                                    | integer               |           |          |         | plain    | 
 unit_type                                | statistical_unit_type |           |          |         | plain    | 
 exists_count                             | integer               |           |          |         | plain    | 
 exists_change                            | integer               |           |          |         | plain    | 
 exists_added_count                       | integer               |           |          |         | plain    | 
 exists_removed_count                     | integer               |           |          |         | plain    | 
 countable_count                          | integer               |           |          |         | plain    | 
 countable_change                         | integer               |           |          |         | plain    | 
 countable_added_count                    | integer               |           |          |         | plain    | 
 countable_removed_count                  | integer               |           |          |         | plain    | 
 births                                   | integer               |           |          |         | plain    | 
 deaths                                   | integer               |           |          |         | plain    | 
 name_change_count                        | integer               |           |          |         | plain    | 
 primary_activity_category_change_count   | integer               |           |          |         | plain    | 
 secondary_activity_category_change_count | integer               |           |          |         | plain    | 
 sector_change_count                      | integer               |           |          |         | plain    | 
 legal_form_change_count                  | integer               |           |          |         | plain    | 
 physical_region_change_count             | integer               |           |          |         | plain    | 
 physical_country_change_count            | integer               |           |          |         | plain    | 
 physical_address_change_count            | integer               |           |          |         | plain    | 
 stats_summary                            | jsonb                 |           |          |         | extended | 
 hash_partition                           | int4range             |           |          |         | extended | Always NULL: every row is a period total. Kept so readers of the former table, which filtered hash_partition IS NULL to get the totals, read the same rows.
View definition:
 WITH per_month AS (
         SELECT d.unit_type,
            d.on_month,
            sum(d.exists_delta) AS exists_delta,
            sum(d.countable_delta) AS countable_delta,
            jsonb_stats_delta_agg(d.stats_delta) AS stats_delta
           FROM history_stock_delta d
          GROUP BY d.unit_type, d.on_month
        ), stock AS (
         SELECT p.resolution,
            p.year,
            p.month,
            m.unit_type,
            sum(m.exists_delta) AS exists_count,
            sum(m.countable_delta) AS countable_count,
            jsonb_stats_delta_agg(m.stats_delta) AS stats_stock
           FROM history_period p
             JOIN per_month m ON m.on_month <= p.curr_stop
          GROUP BY p.resolution, p.year, p.month, m.unit_type
        ), flow AS (
         SELECT f_1.resolution,
            f_1.year,
            f_1.month,
            f_1.unit_type,
            ARRAY[sum(f_1.flows[1])::integer, sum(f_1.flows[2])::integer, sum(f_1.flows[3])::integer, sum(f_1.flows[4])::integer, sum(f_1.flows[5])::integer, sum(f_1.flows[6])::integer, sum(f_1.flows[7])::integer, sum(f_1.flows[8])::integer, sum(f_1.flows[9])::integer, sum(f_1.flows[10])::integer, sum(f_1.flows[11])::integer, sum(f_1.flows[12])::integer, sum(f_1.flows[13])::integer, sum(f_1.flows[14])::integer, sum(f_1.flows[15])::integer, sum(f_1.flows[16])::integer, sum(f_1.flows[17])::integer, sum(f_1.flows[18])::integer] AS flows,
            jsonb_stats_delta_agg(f_1.stats_ended) AS stats_ended
           FROM history_flow_delta f_1
          GROUP BY f_1.resolution, f_1.year, f_1.month, f_1.unit_type
        )
 SELECT COALESCE(s.resolution, f.resolution) AS resolution,
    COALESCE(s.year, f.year) AS year,
    COALESCE(s.month, f.month) AS month,
    COALESCE(s.unit_type, f.unit_type) AS unit_type,
    COALESCE(s.exists_count, 0::numeric)::integer AS exists_count,
    COALESCE(f.flows[1], 0) AS exists_change,
    COALESCE(f.flows[2], 0) AS exists_added_count,
    COALESCE(f.flows[3], 0) AS exists_removed_count,
    COALESCE(s.countable_count, 0::numeric)::integer AS countable_count,
    COALESCE(f.flows[4], 0) AS countable_change,
    COALESCE(f.flows[5], 0) AS countable_added_count,
    COALESCE(f.flows[6], 0) AS countable_removed_count,
    COALESCE(f.flows[7], 0) AS births,
    COALESCE(f.flows[8], 0) AS deaths,
    COALESCE(f.flows[9], 0) AS name_change_count,
    COALESCE(f.flows[10], 0) AS primary_activity_category_change_count,
    COALESCE(f.flows[11], 0) AS secondary_activity_category_change_count,
    COALESCE(f.flows[12], 0) AS sector_change_count,
    COALESCE(f.flows[13], 0) AS legal_form_change_count,
    COALESCE(f.flows[14], 0) AS physical_region_change_count,
    COALESCE(f.flows[15], 0) AS physical_country_change_count,
    COALESCE(f.flows[16], 0) AS physical_address_change_count,
    COALESCE(jsonb_stats_delta_to_agg(jsonb_stats_delta_merge(COALESCE(s.stats_stock, '{"type": "stats_delta"}'::jsonb), COALESCE(f.stats_ended, '{"type": "stats_delta"}'::jsonb))), '{}'::jsonb) AS stats_summary,
    NULL::int4range AS hash_partition
   FROM stock s
     FULL JOIN ( SELECT f_1.resolution,
            f_1.year,
            f_1.month,
            f_1.unit_type,
            f_1.flows,
            f_1.stats_ended
           FROM flow f_1
          WHERE (EXISTS ( SELECT 1
                   FROM history_period p
                  WHERE p.resolution = f_1.resolution AND p.year = f_1.year AND COALESCE(p.month, 0) = COALESCE(f_1.month, 0)))) f ON f.unit_type = s.unit_type AND f.resolution = s.resolution AND f.year = s.year AND COALESCE(f.month, 0) = COALESCE(s.month, 0)
  WHERE COALESCE(s.exists_count, 0::numeric) <> 0::numeric OR COALESCE(s.countable_count, 0::numeric) <> 0::numeric OR f.unit_type IS NOT NULL;
Options: security_invoker=on

```

**Comment:** Totals per period and unit type, from history_stock_delta and history_flow_delta. stats_summary is the stock read from deltas (jsonb_stats_delta_to_agg): exact count, sum and sum_sq; no min/max, since those cannot be undone when a unit leaves.
