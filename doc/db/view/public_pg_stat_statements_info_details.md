```sql
                              View "public.pg_stat_statements_info"
   Column    |           Type           | Collation | Nullable | Default | Storage | Description 
-------------+--------------------------+-----------+----------+---------+---------+-------------
 dealloc     | bigint                   |           |          |         | plain   | 
 stats_reset | timestamp with time zone |           |          |         | plain   | 
View definition:
 SELECT dealloc,
    stats_reset
   FROM pg_stat_statements_info() pg_stat_statements_info(dealloc, stats_reset);

```
