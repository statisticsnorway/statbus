```sql
                        View "public.statistical_unit_facet_def"
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

```
