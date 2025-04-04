```sql
                          View "public.pg_stat_statements"
         Column         |           Type           | Collation | Nullable | Default 
------------------------+--------------------------+-----------+----------+---------
 userid                 | oid                      |           |          | 
 dbid                   | oid                      |           |          | 
 toplevel               | boolean                  |           |          | 
 queryid                | bigint                   |           |          | 
 query                  | text                     |           |          | 
 plans                  | bigint                   |           |          | 
 total_plan_time        | double precision         |           |          | 
 min_plan_time          | double precision         |           |          | 
 max_plan_time          | double precision         |           |          | 
 mean_plan_time         | double precision         |           |          | 
 stddev_plan_time       | double precision         |           |          | 
 calls                  | bigint                   |           |          | 
 total_exec_time        | double precision         |           |          | 
 min_exec_time          | double precision         |           |          | 
 max_exec_time          | double precision         |           |          | 
 mean_exec_time         | double precision         |           |          | 
 stddev_exec_time       | double precision         |           |          | 
 rows                   | bigint                   |           |          | 
 shared_blks_hit        | bigint                   |           |          | 
 shared_blks_read       | bigint                   |           |          | 
 shared_blks_dirtied    | bigint                   |           |          | 
 shared_blks_written    | bigint                   |           |          | 
 local_blks_hit         | bigint                   |           |          | 
 local_blks_read        | bigint                   |           |          | 
 local_blks_dirtied     | bigint                   |           |          | 
 local_blks_written     | bigint                   |           |          | 
 temp_blks_read         | bigint                   |           |          | 
 temp_blks_written      | bigint                   |           |          | 
 shared_blk_read_time   | double precision         |           |          | 
 shared_blk_write_time  | double precision         |           |          | 
 local_blk_read_time    | double precision         |           |          | 
 local_blk_write_time   | double precision         |           |          | 
 temp_blk_read_time     | double precision         |           |          | 
 temp_blk_write_time    | double precision         |           |          | 
 wal_records            | bigint                   |           |          | 
 wal_fpi                | bigint                   |           |          | 
 wal_bytes              | numeric                  |           |          | 
 jit_functions          | bigint                   |           |          | 
 jit_generation_time    | double precision         |           |          | 
 jit_inlining_count     | bigint                   |           |          | 
 jit_inlining_time      | double precision         |           |          | 
 jit_optimization_count | bigint                   |           |          | 
 jit_optimization_time  | double precision         |           |          | 
 jit_emission_count     | bigint                   |           |          | 
 jit_emission_time      | double precision         |           |          | 
 jit_deform_count       | bigint                   |           |          | 
 jit_deform_time        | double precision         |           |          | 
 stats_since            | timestamp with time zone |           |          | 
 minmax_stats_since     | timestamp with time zone |           |          | 

```
