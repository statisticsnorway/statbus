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
 exists_moved_in_count                    | integer               |           |          |         | plain    | 
 exists_moved_out_count                   | integer               |           |          |         | plain    | 
 countable_moved_in_count                 | integer               |           |          |         | plain    | 
 countable_moved_out_count                | integer               |           |          |         | plain    | 
View definition:
 WITH run AS (
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
            sum(d.exists_added_count - d.exists_removed_count + d.exists_moved_in_count - d.exists_moved_out_count) OVER w AS exists_count,
            sum(d.countable_added_count - d.countable_removed_count + d.countable_moved_in_count - d.countable_moved_out_count) OVER w AS countable_count,
            jsonb_stats_delta_agg(d.stats_delta) OVER w AS stats_stock,
            lead(d.on_month) OVER w AS next_month
           FROM statistical_history_facet_delta d
          WINDOW w AS (PARTITION BY d.unit_type, d.primary_activity_category_path, d.secondary_activity_category_path, d.sector_path, d.legal_form_id, d.physical_region_path, d.physical_country_id, d.unit_size_id, d.status_id ORDER BY d.on_month)
        ), parts AS (
         SELECT p.resolution,
            p.year,
            p.month,
            r.unit_type,
            r.primary_activity_category_path,
            r.secondary_activity_category_path,
            r.sector_path,
            r.legal_form_id,
            r.physical_region_path,
            r.physical_country_id,
            r.unit_size_id,
            r.status_id,
            r.exists_count <> 0 OR r.countable_count <> 0 AS has_row,
            r.exists_count,
            r.countable_count,
            0 AS exists_added_count,
            0 AS exists_removed_count,
            0 AS countable_added_count,
            0 AS countable_removed_count,
            0 AS exists_moved_in_count,
            0 AS exists_moved_out_count,
            0 AS countable_moved_in_count,
            0 AS countable_moved_out_count,
            0 AS births,
            0 AS deaths,
            0 AS name_change_count,
            0 AS primary_activity_category_change_count,
            0 AS secondary_activity_category_change_count,
            0 AS sector_change_count,
            0 AS legal_form_change_count,
            0 AS physical_region_change_count,
            0 AS physical_country_change_count,
            0 AS physical_address_change_count,
            0 AS unit_size_change_count,
            0 AS status_change_count,
            r.stats_stock AS stats
           FROM statistical_history_period p
             JOIN run r ON r.on_month <= p.curr_stop AND (r.next_month IS NULL OR p.curr_stop < r.next_month)
        UNION ALL
         SELECT p.resolution,
            p.year,
            p.month,
            d.unit_type,
            d.primary_activity_category_path,
            d.secondary_activity_category_path,
            d.sector_path,
            d.legal_form_id,
            d.physical_region_path,
            d.physical_country_id,
            d.unit_size_id,
            d.status_id,
            d.exists_added_count <> 0 OR d.exists_removed_count <> 0 OR d.countable_added_count <> 0 OR d.countable_removed_count <> 0 OR d.exists_moved_in_count <> 0 OR d.exists_moved_out_count <> 0 OR d.births <> 0 OR d.deaths <> 0 OR d.name_change_count <> 0 OR d.primary_activity_category_change_count <> 0 OR d.secondary_activity_category_change_count <> 0 OR d.sector_change_count <> 0 OR d.legal_form_change_count <> 0 OR d.physical_region_change_count <> 0 OR d.physical_country_change_count <> 0 OR d.physical_address_change_count <> 0 OR d.unit_size_change_count <> 0 OR d.status_change_count <> 0,
            0,
            0,
            d.exists_added_count,
            d.exists_removed_count,
            d.countable_added_count,
            d.countable_removed_count,
            d.exists_moved_in_count,
            d.exists_moved_out_count,
            d.countable_moved_in_count,
            d.countable_moved_out_count,
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
                CASE p.resolution
                    WHEN 'year'::history_resolution THEN d.stats_ended_year
                    ELSE d.stats_ended_month
                END AS stats_ended_month
           FROM statistical_history_period p
             JOIN statistical_history_facet_delta d ON d.on_month >= p.curr_start AND d.on_month <= p.curr_stop
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
    (sum(exists_added_count) - sum(exists_removed_count) + sum(exists_moved_in_count) - sum(exists_moved_out_count))::integer AS exists_change,
    sum(exists_added_count)::integer AS exists_added_count,
    sum(exists_removed_count)::integer AS exists_removed_count,
    sum(countable_count)::integer AS countable_count,
    (sum(countable_added_count) - sum(countable_removed_count) + sum(countable_moved_in_count) - sum(countable_moved_out_count))::integer AS countable_change,
    sum(countable_added_count)::integer AS countable_added_count,
    sum(countable_removed_count)::integer AS countable_removed_count,
    sum(births)::integer AS births,
    sum(deaths)::integer AS deaths,
    sum(name_change_count)::integer AS name_change_count,
    sum(primary_activity_category_change_count)::integer AS primary_activity_category_change_count,
    sum(secondary_activity_category_change_count)::integer AS secondary_activity_category_change_count,
    sum(sector_change_count)::integer AS sector_change_count,
    sum(legal_form_change_count)::integer AS legal_form_change_count,
    sum(physical_region_change_count)::integer AS physical_region_change_count,
    sum(physical_country_change_count)::integer AS physical_country_change_count,
    sum(physical_address_change_count)::integer AS physical_address_change_count,
    sum(unit_size_change_count)::integer AS unit_size_change_count,
    sum(status_change_count)::integer AS status_change_count,
    COALESCE(jsonb_stats_delta_to_agg(jsonb_stats_delta_nullif_zero(jsonb_stats_delta_agg(stats))), '{}'::jsonb) AS stats_summary,
    sum(exists_moved_in_count)::integer AS exists_moved_in_count,
    sum(exists_moved_out_count)::integer AS exists_moved_out_count,
    sum(countable_moved_in_count)::integer AS countable_moved_in_count,
    sum(countable_moved_out_count)::integer AS countable_moved_out_count
   FROM parts
  GROUP BY resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id
 HAVING bool_or(has_row);
Options: security_invoker=on

```

**Comment:** Counts, changes and stats per period and cell, from public.statistical_history_facet_delta. Per cell, a move is moved_out of the old cell and moved_in to the new one; stats_summary as in statistical_history.
