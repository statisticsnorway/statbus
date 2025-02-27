```sql
                     Unlogged table "public.statistical_unit_facet"
             Column             |         Type          | Collation | Nullable | Default 
--------------------------------+-----------------------+-----------+----------+---------
 valid_from                     | date                  |           |          | 
 valid_to                       | date                  |           |          | 
 unit_type                      | statistical_unit_type |           |          | 
 physical_region_path           | ltree                 |           |          | 
 primary_activity_category_path | ltree                 |           |          | 
 sector_path                    | ltree                 |           |          | 
 legal_form_id                  | integer               |           |          | 
 physical_country_id            | integer               |           |          | 
 status_id                      | integer               |           |          | 
 count                          | bigint                |           |          | 
 stats_summary                  | jsonb                 |           |          | 
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
    "statistical_unit_facet_valid_to" btree (valid_to)
Policies:
    POLICY "statistical_unit_facet_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statistical_unit_facet_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "statistical_unit_facet_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))

```
