```sql
                                        Unlogged table "public.statistical_history_facet_pre_dirty_dims"
              Column              |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
----------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 resolution                       | history_resolution    |           |          |         | plain    |             |              | 
 year                             | integer               |           |          |         | plain    |             |              | 
 month                            | integer               |           |          |         | plain    |             |              | 
 unit_type                        | statistical_unit_type |           |          |         | plain    |             |              | 
 primary_activity_category_path   | ltree                 |           |          |         | extended |             |              | 
 secondary_activity_category_path | ltree                 |           |          |         | extended |             |              | 
 sector_path                      | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                    | integer               |           |          |         | plain    |             |              | 
 physical_region_path             | ltree                 |           |          |         | extended |             |              | 
 physical_country_id              | integer               |           |          |         | plain    |             |              | 
 unit_size_id                     | integer               |           |          |         | plain    |             |              | 
 status_id                        | integer               |           |          |         | plain    |             |              | 
Access method: heap

```
