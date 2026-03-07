```sql
       Table "worker.base_change_log_has_pending"
   Column    |  Type   | Collation | Nullable | Default 
-------------+---------+-----------+----------+---------
 has_pending | boolean |           | not null | false
Indexes:
    "base_change_log_has_pending_single_row" UNIQUE, btree ((true))

```
