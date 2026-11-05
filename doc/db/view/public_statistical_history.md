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
 exists_moved_in_count                    | integer               |           |          |         | plain    | 
 exists_moved_out_count                   | integer               |           |          |         | plain    | 
 countable_moved_in_count                 | integer               |           |          |         | plain    | 
 countable_moved_out_count                | integer               |           |          |         | plain    | 
View definition:
 WITH per_month AS (
         SELECT d.unit_type,
            d.on_month,
            sum(d.exists_added_count - d.exists_removed_count + d.exists_moved_in_count - d.exists_moved_out_count) AS exists_net,
            sum(d.countable_added_count - d.countable_removed_count + d.countable_moved_in_count - d.countable_moved_out_count) AS countable_net,
            sum(d.exists_added_count) AS exists_added_count,
            sum(d.exists_removed_count) AS exists_removed_count,
            sum(d.countable_added_count) AS countable_added_count,
            sum(d.countable_removed_count) AS countable_removed_count,
            sum(d.exists_moved_in_count) AS exists_moved_in_count,
            sum(d.exists_moved_out_count) AS exists_moved_out_count,
            sum(d.countable_moved_in_count) AS countable_moved_in_count,
            sum(d.countable_moved_out_count) AS countable_moved_out_count,
            sum(d.births) AS births,
            sum(d.deaths) AS deaths,
            sum(d.name_change_count) AS name_change_count,
            sum(d.primary_activity_category_change_count) AS primary_activity_category_change_count,
            sum(d.secondary_activity_category_change_count) AS secondary_activity_category_change_count,
            sum(d.sector_change_count) AS sector_change_count,
            sum(d.legal_form_change_count) AS legal_form_change_count,
            sum(d.physical_region_change_count) AS physical_region_change_count,
            sum(d.physical_country_change_count) AS physical_country_change_count,
            sum(d.physical_address_change_count) AS physical_address_change_count,
            jsonb_stats_delta_agg(d.stats_delta) FILTER (WHERE d.stats_delta IS NOT NULL) AS stats_delta,
            jsonb_stats_delta_agg(d.stats_ended_month) FILTER (WHERE d.stats_ended_month IS NOT NULL) AS stats_ended_month,
            jsonb_stats_delta_agg(d.stats_ended_year) FILTER (WHERE d.stats_ended_year IS NOT NULL) AS stats_ended_year
           FROM statistical_history_facet_delta d
          GROUP BY d.unit_type, d.on_month
        ), stock AS (
         SELECT p.resolution,
            p.year,
            p.month,
            m.unit_type,
            sum(m.exists_net) AS exists_count,
            sum(m.countable_net) AS countable_count,
            jsonb_stats_delta_agg(m.stats_delta) FILTER (WHERE m.stats_delta IS NOT NULL) AS stats_stock
           FROM statistical_history_period p
             JOIN per_month m ON m.on_month <= p.curr_stop
          GROUP BY p.resolution, p.year, p.month, m.unit_type
        ), change AS (
         SELECT p.resolution,
            p.year,
            p.month,
            m.unit_type,
            sum(m.exists_net) AS exists_change,
            sum(m.exists_added_count) AS exists_added_count,
            sum(m.exists_removed_count) AS exists_removed_count,
            sum(m.countable_net) AS countable_change,
            sum(m.countable_added_count) AS countable_added_count,
            sum(m.countable_removed_count) AS countable_removed_count,
            sum(m.exists_moved_in_count) AS exists_moved_in_count,
            sum(m.exists_moved_out_count) AS exists_moved_out_count,
            sum(m.countable_moved_in_count) AS countable_moved_in_count,
            sum(m.countable_moved_out_count) AS countable_moved_out_count,
            sum(m.births) AS births,
            sum(m.deaths) AS deaths,
            sum(m.name_change_count) AS name_change_count,
            sum(m.primary_activity_category_change_count) AS primary_activity_category_change_count,
            sum(m.secondary_activity_category_change_count) AS secondary_activity_category_change_count,
            sum(m.sector_change_count) AS sector_change_count,
            sum(m.legal_form_change_count) AS legal_form_change_count,
            sum(m.physical_region_change_count) AS physical_region_change_count,
            sum(m.physical_country_change_count) AS physical_country_change_count,
            sum(m.physical_address_change_count) AS physical_address_change_count,
            jsonb_stats_delta_agg(
                CASE p.resolution
                    WHEN 'year'::history_resolution THEN m.stats_ended_year
                    ELSE m.stats_ended_month
                END) FILTER (WHERE
                CASE p.resolution
                    WHEN 'year'::history_resolution THEN m.stats_ended_year
                    ELSE m.stats_ended_month
                END IS NOT NULL) AS stats_ended
           FROM statistical_history_period p
             JOIN per_month m ON m.on_month >= p.curr_start AND m.on_month <= p.curr_stop
          GROUP BY p.resolution, p.year, p.month, m.unit_type
        )
 SELECT s.resolution,
    s.year,
    s.month,
    s.unit_type,
    s.exists_count::integer AS exists_count,
    COALESCE(c.exists_change, 0::numeric)::integer AS exists_change,
    COALESCE(c.exists_added_count, 0::numeric)::integer AS exists_added_count,
    COALESCE(c.exists_removed_count, 0::numeric)::integer AS exists_removed_count,
    s.countable_count::integer AS countable_count,
    COALESCE(c.countable_change, 0::numeric)::integer AS countable_change,
    COALESCE(c.countable_added_count, 0::numeric)::integer AS countable_added_count,
    COALESCE(c.countable_removed_count, 0::numeric)::integer AS countable_removed_count,
    COALESCE(c.births, 0::numeric)::integer AS births,
    COALESCE(c.deaths, 0::numeric)::integer AS deaths,
    COALESCE(c.name_change_count, 0::numeric)::integer AS name_change_count,
    COALESCE(c.primary_activity_category_change_count, 0::numeric)::integer AS primary_activity_category_change_count,
    COALESCE(c.secondary_activity_category_change_count, 0::numeric)::integer AS secondary_activity_category_change_count,
    COALESCE(c.sector_change_count, 0::numeric)::integer AS sector_change_count,
    COALESCE(c.legal_form_change_count, 0::numeric)::integer AS legal_form_change_count,
    COALESCE(c.physical_region_change_count, 0::numeric)::integer AS physical_region_change_count,
    COALESCE(c.physical_country_change_count, 0::numeric)::integer AS physical_country_change_count,
    COALESCE(c.physical_address_change_count, 0::numeric)::integer AS physical_address_change_count,
    COALESCE(jsonb_stats_delta_to_agg(jsonb_stats_delta_nullif_zero(
        CASE
            WHEN s.stats_stock IS NULL THEN c.stats_ended
            WHEN c.stats_ended IS NULL THEN s.stats_stock
            ELSE jsonb_stats_delta_merge(s.stats_stock, c.stats_ended)
        END)), '{}'::jsonb) AS stats_summary,
    NULL::int4range AS hash_partition,
    COALESCE(c.exists_moved_in_count, 0::numeric)::integer AS exists_moved_in_count,
    COALESCE(c.exists_moved_out_count, 0::numeric)::integer AS exists_moved_out_count,
    COALESCE(c.countable_moved_in_count, 0::numeric)::integer AS countable_moved_in_count,
    COALESCE(c.countable_moved_out_count, 0::numeric)::integer AS countable_moved_out_count
   FROM stock s
     LEFT JOIN change c ON c.unit_type = s.unit_type AND c.resolution = s.resolution AND c.year = s.year AND COALESCE(c.month, 0) = COALESCE(s.month, 0)
  WHERE s.exists_count <> 0::numeric OR s.countable_count <> 0::numeric OR c.exists_added_count <> 0::numeric OR c.exists_removed_count <> 0::numeric OR c.countable_added_count <> 0::numeric OR c.countable_removed_count <> 0::numeric OR c.births <> 0::numeric OR c.deaths <> 0::numeric OR c.name_change_count <> 0::numeric OR c.primary_activity_category_change_count <> 0::numeric OR c.secondary_activity_category_change_count <> 0::numeric OR c.sector_change_count <> 0::numeric OR c.legal_form_change_count <> 0::numeric OR c.physical_region_change_count <> 0::numeric OR c.physical_country_change_count <> 0::numeric OR c.physical_address_change_count <> 0::numeric OR c.exists_moved_in_count <> 0::numeric OR c.stats_ended IS NOT NULL;
Options: security_invoker=on

```

**Comment:** Totals per period and unit type, from public.statistical_history_facet_delta. Changes are counted from each unit's versions, so a year equals the sum of its months; exists_change is the net change of the stock (added - removed + moved_in - moved_out). stats_summary is the stock read from deltas (jsonb_stats_delta_to_agg): exact count, sum and sum_sq; no min/max, since those cannot be undone when a unit leaves.
