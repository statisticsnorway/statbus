```sql
                 Unlogged table "public.statistical_unit_facet_staging"
             Column             |         Type          | Collation | Nullable | Default 
--------------------------------+-----------------------+-----------+----------+---------
 partition_seq                  | integer               |           | not null | 
 valid_from                     | date                  |           |          | 
 valid_to                       | date                  |           |          | 
 valid_until                    | date                  |           |          | 
 unit_type                      | statistical_unit_type |           |          | 
 physical_region_path           | ltree                 |           |          | 
 primary_activity_category_path | ltree                 |           |          | 
 sector_path                    | ltree                 |           |          | 
 legal_form_id                  | integer               |           |          | 
 physical_country_id            | integer               |           |          | 
 status_id                      | integer               |           |          | 
 count                          | integer               |           | not null | 
 stats_summary                  | jsonb                 |           |          | 
Indexes:
    "idx_statistical_unit_facet_staging_partition_seq" btree (partition_seq)
    "statistical_unit_facet_stagin_partition_seq_valid_from_vali_key" UNIQUE CONSTRAINT, btree (partition_seq, valid_from, valid_to, valid_until, unit_type, physical_region_path, primary_activity_category_path, sector_path, legal_form_id, physical_country_id, status_id) NULLS NOT DISTINCT

```
