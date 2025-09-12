```sql
                                                     Table "public.statistical_unit_facet"
             Column             |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 valid_from                     | date                  |           |          |         | plain    |             |              | 
 valid_to                       | date                  |           |          |         | plain    |             |              | 
 valid_until                    | date                  |           |          |         | plain    |             |              | 
 unit_type                      | statistical_unit_type |           |          |         | plain    |             |              | 
 physical_region_path           | ltree                 |           |          |         | extended |             |              | 
 primary_activity_category_path | ltree                 |           |          |         | extended |             |              | 
 sector_path                    | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                  | integer               |           |          |         | plain    |             |              | 
 physical_country_id            | integer               |           |          |         | plain    |             |              | 
 status_id                      | integer               |           |          |         | plain    |             |              | 
 count                          | bigint                |           |          |         | plain    |             |              | 
 stats_summary                  | jsonb                 |           |          |         | extended |             |              | 
Indexes:
    "statistical_unit_facet_legal_form_id_btree" btree (legal_form_id)
    "statistical_unit_facet_physical_country_id_btree" btree (physical_country_id)
    "statistical_unit_facet_physical_region_path_btree" btree (physical_region_path)
    "statistical_unit_facet_physical_region_path_gist" gist (physical_region_path)
    "statistical_unit_facet_primary_activity_category_path_btree" btree (primary_activity_category_path)
    "statistical_unit_facet_primary_activity_category_path_gist" gist (primary_activity_category_path)
    "statistical_unit_facet_sector_path_btree" btree (sector_path)
    "statistical_unit_facet_sector_path_gist" gist (sector_path)
    "statistical_unit_facet_unit_type" btree (unit_type)
    "statistical_unit_facet_valid_from" btree (valid_from)
    "statistical_unit_facet_valid_until" btree (valid_until)
Policies:
    POLICY "statistical_unit_facet_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "statistical_unit_facet_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statistical_unit_facet_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```
