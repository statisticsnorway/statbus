```sql
                                            Unlogged table "worker.statistical_unit_facet_changed"
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
Indexes:
    "statistical_unit_facet_change_valid_from_valid_to_valid_unt_key" UNIQUE CONSTRAINT, btree (valid_from, valid_to, valid_until, unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id) NULLS NOT DISTINCT
Access method: heap

```

**Comment:** The public.statistical_unit_facet combinations whose rows in public.statistical_unit_facet_staging changed since the last worker.statistical_unit_facet_reduce: added, altered or removed. worker.derive_statistical_unit_facet_partition records them when it rewrites a slice in dirty mode, comparing the slice before and after. The reduce recomputes exactly these combinations, deletes the ones without support left, and empties the table. A combination recorded twice, or left over from an interrupted cycle, is only recomputed again, so the table may over-state but never miss a change.
