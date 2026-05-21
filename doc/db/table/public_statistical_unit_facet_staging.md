```sql
                                            Unlogged table "public.statistical_unit_facet_staging"
             Column             |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 hash_slot                      | integer               |           | not null |         | plain    |             |              | 
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
 count                          | integer               |           | not null |         | plain    |             |              | 
 stats_summary                  | jsonb                 |           |          |         | extended |             |              | 
Indexes:
    "idx_statistical_unit_facet_staging_hash_slot" btree (hash_slot)
    "statistical_unit_facet_stagin_hash_slot_valid_from_vali_key" UNIQUE CONSTRAINT, btree (hash_slot, valid_from, valid_to, valid_until, unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id) NULLS NOT DISTINCT
Not-null constraints:
    "statistical_unit_facet_staging_hash_slot_not_null" NOT NULL "hash_slot"
    "statistical_unit_facet_staging_count_not_null" NOT NULL "count"
Access method: heap

```
