```sql
                                          View "public.statistical_history_facet"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Description 
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------
 resolution                               | history_resolution    |           |          |         | plain    | 
 year                                     | integer               |           |          |         | plain    | 
 month                                    | integer               |           |          |         | plain    | 
 unit_type                                | statistical_unit_type |           |          |         | plain    | 
 primary_activity_category_path           | ltree                 |           |          |         | extended | 
 secondary_activity_category_path         | ltree                 |           |          |         | extended | 
 sector_path                              | ltree                 |           |          |         | extended | 
 legal_form_id                            | integer               |           |          |         | plain    | 
 physical_region_path                     | ltree                 |           |          |         | extended | 
 physical_country_id                      | integer               |           |          |         | plain    | 
 unit_size_id                             | integer               |           |          |         | plain    | 
 status_id                                | integer               |           |          |         | plain    | 
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
 unit_size_change_count                   | integer               |           |          |         | plain    | 
 status_change_count                      | integer               |           |          |         | plain    | 
 stats_summary                            | jsonb                 |           |          |         | extended | 
View definition:
 WITH stock AS (
         SELECT d.unit_type,
            d.primary_activity_category_path,
            d.secondary_activity_category_path,
            d.sector_path,
            d.legal_form_id,
            d.physical_region_path,
            d.physical_country_id,
            d.unit_size_id,
            d.status_id,
            d.on_month,
            sum(d.exists_delta) OVER w AS exists_count,
            sum(d.countable_delta) OVER w AS countable_count,
            jsonb_stats_delta_agg(d.stats_delta) OVER w AS stats_stock,
            lead(d.on_month) OVER w AS next_date
           FROM history_stock_delta d
          WINDOW w AS (PARTITION BY d.unit_type, d.primary_activity_category_path, d.secondary_activity_category_path, d.sector_path, d.legal_form_id, d.physical_region_path, d.physical_country_id, d.unit_size_id, d.status_id ORDER BY d.on_month)
        ), parts AS (
         SELECT p.resolution,
            p.year,
            p.month,
            s.unit_type,
            s.primary_activity_category_path,
            s.secondary_activity_category_path,
            s.sector_path,
            s.legal_form_id,
            s.physical_region_path,
            s.physical_country_id,
            s.unit_size_id,
            s.status_id,
            s.exists_count <> 0 OR s.countable_count <> 0 AS has_row,
            s.exists_count,
            s.countable_count,
            NULL::integer[] AS flows,
            s.stats_stock AS stats
           FROM history_period p
             JOIN stock s ON s.on_month <= p.curr_stop AND (s.next_date IS NULL OR p.curr_stop < s.next_date)
        UNION ALL
         SELECT f.resolution,
            f.year,
            f.month,
            f.unit_type,
            f.primary_activity_category_path,
            f.secondary_activity_category_path,
            f.sector_path,
            f.legal_form_id,
            f.physical_region_path,
            f.physical_country_id,
            f.unit_size_id,
            f.status_id,
            (EXISTS ( SELECT 1
                   FROM unnest(f.flows) x(x)
                  WHERE x.x <> 0)) AS "exists",
            0,
            0,
            f.flows,
            f.stats_ended
           FROM history_flow_delta f
             JOIN history_period p ON p.resolution = f.resolution AND p.year = f.year AND NOT p.month IS DISTINCT FROM f.month
        )
 SELECT resolution,
    year,
    month,
    unit_type,
    primary_activity_category_path,
    secondary_activity_category_path,
    sector_path,
    legal_form_id,
    physical_region_path,
    physical_country_id,
    unit_size_id,
    status_id,
    sum(exists_count)::integer AS exists_count,
    COALESCE(sum(flows[1]), 0::bigint)::integer AS exists_change,
    COALESCE(sum(flows[2]), 0::bigint)::integer AS exists_added_count,
    COALESCE(sum(flows[3]), 0::bigint)::integer AS exists_removed_count,
    sum(countable_count)::integer AS countable_count,
    COALESCE(sum(flows[4]), 0::bigint)::integer AS countable_change,
    COALESCE(sum(flows[5]), 0::bigint)::integer AS countable_added_count,
    COALESCE(sum(flows[6]), 0::bigint)::integer AS countable_removed_count,
    COALESCE(sum(flows[7]), 0::bigint)::integer AS births,
    COALESCE(sum(flows[8]), 0::bigint)::integer AS deaths,
    COALESCE(sum(flows[9]), 0::bigint)::integer AS name_change_count,
    COALESCE(sum(flows[10]), 0::bigint)::integer AS primary_activity_category_change_count,
    COALESCE(sum(flows[11]), 0::bigint)::integer AS secondary_activity_category_change_count,
    COALESCE(sum(flows[12]), 0::bigint)::integer AS sector_change_count,
    COALESCE(sum(flows[13]), 0::bigint)::integer AS legal_form_change_count,
    COALESCE(sum(flows[14]), 0::bigint)::integer AS physical_region_change_count,
    COALESCE(sum(flows[15]), 0::bigint)::integer AS physical_country_change_count,
    COALESCE(sum(flows[16]), 0::bigint)::integer AS physical_address_change_count,
    COALESCE(sum(flows[17]), 0::bigint)::integer AS unit_size_change_count,
    COALESCE(sum(flows[18]), 0::bigint)::integer AS status_change_count,
    COALESCE(jsonb_stats_delta_to_agg(jsonb_stats_delta_agg(stats)), '{}'::jsonb) AS stats_summary
   FROM parts
  GROUP BY resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id
 HAVING bool_or(has_row);
Options: security_invoker=on

```

**Comment:** Counts and stats per period and cell, from history_stock_delta and history_flow_delta. stats_summary as in statistical_history: exact count, sum and sum_sq, no min/max.
