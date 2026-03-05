```sql
                       Unlogged table "worker.base_change_log"
        Column         |      Type      | Collation | Nullable |       Default        
-----------------------+----------------+-----------+----------+----------------------
 establishment_ids     | int4multirange |           | not null | '{}'::int4multirange
 legal_unit_ids        | int4multirange |           | not null | '{}'::int4multirange
 enterprise_ids        | int4multirange |           | not null | '{}'::int4multirange
 edited_by_valid_range | datemultirange |           | not null | '{}'::datemultirange
 power_group_ids       | int4multirange |           | not null | '{}'::int4multirange

```
