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

**Comment:** The single row (unique index on (true)) saying whether worker.base_change_log holds changes no collector has drained yet. Producers lock this row and set the flag through worker.publish_base_change_wakeup; worker.command_collect_changes locks it before its drain snapshot and clears it after. Statements name the row they change by the flag value (WHERE NOT has_pending / WHERE has_pending), as every session runs under pg_safeupdate.
