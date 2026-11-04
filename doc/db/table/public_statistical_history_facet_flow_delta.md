```sql
                                                                                                                                                                                                       Table "public.statistical_history_facet_flow_delta"
              Column              |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                                                                                                                         Description                                                                                                                                                          
----------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 resolution                       | history_resolution    |           | not null |         | plain    |             |              | 
 year                             | integer               |           | not null |         | plain    |             |              | 
 month                            | integer               |           |          |         | plain    |             |              | 
 unit_type                        | statistical_unit_type |           | not null |         | plain    |             |              | 
 primary_activity_category_path   | ltree                 |           |          |         | extended |             |              | 
 secondary_activity_category_path | ltree                 |           |          |         | extended |             |              | 
 sector_path                      | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                    | integer               |           |          |         | plain    |             |              | 
 physical_region_path             | ltree                 |           |          |         | extended |             |              | 
 physical_country_id              | integer               |           |          |         | plain    |             |              | 
 unit_size_id                     | integer               |           |          |         | plain    |             |              | 
 status_id                        | integer               |           |          |         | plain    |             |              | 
 flows                            | integer[]             |           | not null |         | extended |             |              | In order: exists_change, exists_added_count, exists_removed_count, countable_change, countable_added_count, countable_removed_count, births, deaths, name, primary_activity_category, secondary_activity_category, sector, legal_form, physical_region, physical_country, physical_address, unit_size, status change counts.
 stats_ended                      | jsonb                 |           |          |         | extended |             |              | 
 unit_ids                         | integer[]             |           | not null |         | extended |             |              | 
Indexes:
    "statistical_history_facet_flow_delta_key" UNIQUE, btree (resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id) NULLS NOT DISTINCT
Policies:
    POLICY "statistical_history_facet_flow_delta_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "statistical_history_facet_flow_delta_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statistical_history_facet_flow_delta_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "statistical_history_facet_flow_delta_resolution_not_null" NOT NULL "resolution"
    "statistical_history_facet_flow_delta_year_not_null" NOT NULL "year"
    "statistical_history_facet_flow_delta_unit_type_not_null" NOT NULL "unit_type"
    "statistical_history_facet_flow_delta_flows_not_null" NOT NULL "flows"
    "statistical_history_facet_flow_delta_unit_ids_not_null" NOT NULL "unit_ids"
Access method: heap

```

**Comment:** Change counts per cell and period, comparing each unit at the previous and current period end (flows, in the order of the statistical_history_facet columns exists_change .. status_change_count), and the stats of units whose latest overlapping version ended inside the period (stats_ended). unit_ids lists the contributing units.
