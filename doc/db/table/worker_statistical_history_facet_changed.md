```sql
                                            Unlogged table "worker.statistical_history_facet_changed"
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
Indexes:
    "statistical_history_facet_cha_resolution_year_month_unit_ty_key" UNIQUE CONSTRAINT, btree (resolution, year, month, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id) NULLS NOT DISTINCT
Access method: heap

```

**Comment:** The public.statistical_history_facet combinations whose rows in public.statistical_history_facet_partitions changed since the last worker.statistical_history_facet_reduce: added, altered or removed. worker.derive_statistical_history_facet_period records them when it rewrites a period and slot range in dirty mode, comparing the slice before and after. The reduce recomputes exactly these combinations, deletes the ones without support left, and empties the table. A combination recorded twice, or left over from an interrupted cycle, is only recomputed again, so the table may over-state but never miss a change.
