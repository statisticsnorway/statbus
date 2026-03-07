```sql
                                                  Unlogged table "worker.base_change_log"
        Column         |      Type      | Collation | Nullable |       Default        | Storage  | Compression | Stats target | Description 
-----------------------+----------------+-----------+----------+----------------------+----------+-------------+--------------+-------------
 establishment_ids     | int4multirange |           | not null | '{}'::int4multirange | extended |             |              | 
 legal_unit_ids        | int4multirange |           | not null | '{}'::int4multirange | extended |             |              | 
 enterprise_ids        | int4multirange |           | not null | '{}'::int4multirange | extended |             |              | 
 edited_by_valid_range | datemultirange |           | not null | '{}'::datemultirange | extended |             |              | 
 power_group_ids       | int4multirange |           | not null | '{}'::int4multirange | extended |             |              | 
Not-null constraints:
    "base_change_log_establishment_ids_not_null" NOT NULL "establishment_ids"
    "base_change_log_legal_unit_ids_not_null" NOT NULL "legal_unit_ids"
    "base_change_log_enterprise_ids_not_null" NOT NULL "enterprise_ids"
    "base_change_log_edited_by_valid_range_not_null" NOT NULL "edited_by_valid_range"
    "base_change_log_power_group_ids_not_null" NOT NULL "power_group_ids"
Access method: heap
Options: autovacuum_vacuum_threshold=50, autovacuum_vacuum_scale_factor=0.0

```
