```sql
                                      View "public.pg_stat_statements"
         Column         |           Type           | Collation | Nullable | Default | Storage  | Description 
------------------------+--------------------------+-----------+----------+---------+----------+-------------
 userid                 | oid                      |           |          |         | plain    | 
 dbid                   | oid                      |           |          |         | plain    | 
 toplevel               | boolean                  |           |          |         | plain    | 
 queryid                | bigint                   |           |          |         | plain    | 
 query                  | text                     |           |          |         | extended | 
 plans                  | bigint                   |           |          |         | plain    | 
 total_plan_time        | double precision         |           |          |         | plain    | 
 min_plan_time          | double precision         |           |          |         | plain    | 
 max_plan_time          | double precision         |           |          |         | plain    | 
 mean_plan_time         | double precision         |           |          |         | plain    | 
 stddev_plan_time       | double precision         |           |          |         | plain    | 
 calls                  | bigint                   |           |          |         | plain    | 
 total_exec_time        | double precision         |           |          |         | plain    | 
 min_exec_time          | double precision         |           |          |         | plain    | 
 max_exec_time          | double precision         |           |          |         | plain    | 
 mean_exec_time         | double precision         |           |          |         | plain    | 
 stddev_exec_time       | double precision         |           |          |         | plain    | 
 rows                   | bigint                   |           |          |         | plain    | 
 shared_blks_hit        | bigint                   |           |          |         | plain    | 
 shared_blks_read       | bigint                   |           |          |         | plain    | 
 shared_blks_dirtied    | bigint                   |           |          |         | plain    | 
 shared_blks_written    | bigint                   |           |          |         | plain    | 
 local_blks_hit         | bigint                   |           |          |         | plain    | 
 local_blks_read        | bigint                   |           |          |         | plain    | 
 local_blks_dirtied     | bigint                   |           |          |         | plain    | 
 local_blks_written     | bigint                   |           |          |         | plain    | 
 temp_blks_read         | bigint                   |           |          |         | plain    | 
 temp_blks_written      | bigint                   |           |          |         | plain    | 
 shared_blk_read_time   | double precision         |           |          |         | plain    | 
 shared_blk_write_time  | double precision         |           |          |         | plain    | 
 local_blk_read_time    | double precision         |           |          |         | plain    | 
 local_blk_write_time   | double precision         |           |          |         | plain    | 
 temp_blk_read_time     | double precision         |           |          |         | plain    | 
 temp_blk_write_time    | double precision         |           |          |         | plain    | 
 wal_records            | bigint                   |           |          |         | plain    | 
 wal_fpi                | bigint                   |           |          |         | plain    | 
 wal_bytes              | numeric                  |           |          |         | main     | 
 jit_functions          | bigint                   |           |          |         | plain    | 
 jit_generation_time    | double precision         |           |          |         | plain    | 
 jit_inlining_count     | bigint                   |           |          |         | plain    | 
 jit_inlining_time      | double precision         |           |          |         | plain    | 
 jit_optimization_count | bigint                   |           |          |         | plain    | 
 jit_optimization_time  | double precision         |           |          |         | plain    | 
 jit_emission_count     | bigint                   |           |          |         | plain    | 
 jit_emission_time      | double precision         |           |          |         | plain    | 
 jit_deform_count       | bigint                   |           |          |         | plain    | 
 jit_deform_time        | double precision         |           |          |         | plain    | 
 stats_since            | timestamp with time zone |           |          |         | plain    | 
 minmax_stats_since     | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT userid,
    dbid,
    toplevel,
    queryid,
    query,
    plans,
    total_plan_time,
    min_plan_time,
    max_plan_time,
    mean_plan_time,
    stddev_plan_time,
    calls,
    total_exec_time,
    min_exec_time,
    max_exec_time,
    mean_exec_time,
    stddev_exec_time,
    rows,
    shared_blks_hit,
    shared_blks_read,
    shared_blks_dirtied,
    shared_blks_written,
    local_blks_hit,
    local_blks_read,
    local_blks_dirtied,
    local_blks_written,
    temp_blks_read,
    temp_blks_written,
    shared_blk_read_time,
    shared_blk_write_time,
    local_blk_read_time,
    local_blk_write_time,
    temp_blk_read_time,
    temp_blk_write_time,
    wal_records,
    wal_fpi,
    wal_bytes,
    jit_functions,
    jit_generation_time,
    jit_inlining_count,
    jit_inlining_time,
    jit_optimization_count,
    jit_optimization_time,
    jit_emission_count,
    jit_emission_time,
    jit_deform_count,
    jit_deform_time,
    stats_since,
    minmax_stats_since
   FROM pg_stat_statements(true) pg_stat_statements(userid, dbid, toplevel, queryid, query, plans, total_plan_time, min_plan_time, max_plan_time, mean_plan_time, stddev_plan_time, calls, total_exec_time, min_exec_time, max_exec_time, mean_exec_time, stddev_exec_time, rows, shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied, local_blks_written, temp_blks_read, temp_blks_written, shared_blk_read_time, shared_blk_write_time, local_blk_read_time, local_blk_write_time, temp_blk_read_time, temp_blk_write_time, wal_records, wal_fpi, wal_bytes, jit_functions, jit_generation_time, jit_inlining_count, jit_inlining_time, jit_optimization_count, jit_optimization_time, jit_emission_count, jit_emission_time, jit_deform_count, jit_deform_time, stats_since, minmax_stats_since);

```
