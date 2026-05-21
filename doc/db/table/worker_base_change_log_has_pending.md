```sql
                                 Table "worker.base_change_log_has_pending"
   Column    |  Type   | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
-------------+---------+-----------+----------+---------+---------+-------------+--------------+-------------
 has_pending | boolean |           | not null | false   | plain   |             |              | 
Indexes:
    "base_change_log_has_pending_single_row" UNIQUE, btree ((true))
Not-null constraints:
    "base_change_log_has_pending_has_pending_not_null" NOT NULL "has_pending"
Access method: heap

```
