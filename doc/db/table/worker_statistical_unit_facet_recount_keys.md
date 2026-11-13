```sql
                                          Unlogged table "worker.statistical_unit_facet_recount_keys"
             Column             |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 valid_from                     | date                  |           | not null |         | plain    |             |              | 
 valid_to                       | date                  |           | not null |         | plain    |             |              | 
 valid_until                    | date                  |           | not null |         | plain    |             |              | 
 unit_type                      | statistical_unit_type |           | not null |         | plain    |             |              | 
 physical_region_path           | ltree                 |           |          |         | extended |             |              | 
 primary_activity_category_path | ltree                 |           |          |         | extended |             |              | 
 sector_path                    | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                  | integer               |           |          |         | plain    |             |              | 
 physical_country_id            | integer               |           |          |         | plain    |             |              | 
 status_id                      | integer               |           |          |         | plain    |             |              | 
Not-null constraints:
    "statistical_unit_facet_recount_keys_valid_from_not_null" NOT NULL "valid_from"
    "statistical_unit_facet_recount_keys_valid_to_not_null" NOT NULL "valid_to"
    "statistical_unit_facet_recount_keys_valid_until_not_null" NOT NULL "valid_until"
    "statistical_unit_facet_recount_keys_unit_type_not_null" NOT NULL "unit_type"
Access method: heap

```

**Comment:** Facet keys staged in the dirty hash slots of a partial derive, recorded by worker.derive_statistical_unit_facet before its children rewrite them: the facets the changed units may leave. worker.statistical_unit_facet_reduce recounts them and empties the table in its transaction. UNLOGGED like the staging it describes: after a crash staging is empty too, and the next derive rewrites all of it (worker.statistical_unit_facet_state.recount_all).
