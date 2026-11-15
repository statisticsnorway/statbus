```sql
                                          Unlogged table "worker.statistical_unit_facet_slot_before"
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
    "statistical_unit_facet_slot_before_hash_slot_idx" btree (hash_slot)
Not-null constraints:
    "statistical_unit_facet_staging_hash_slot_not_null" NOT NULL "hash_slot"
    "statistical_unit_facet_staging_count_not_null" NOT NULL "count"
Access method: heap

```

**Comment:** The staging rows of the dirty hash slots of partial derives as they were before the rewrite, recorded by worker.derive_statistical_unit_facet: what the stored facets hold for those slots. worker.statistical_unit_facet_reduce subtracts them from the facets, adds the slots' rows after the rewrite, and empties the table in its transaction. A slot already recorded is not recorded again, as its first rows are still what the stored facets hold. UNLOGGED like the staging it copies: after a crash staging is empty too, and the next derive rewrites all of it (worker.statistical_unit_facet_state.recount_all).
