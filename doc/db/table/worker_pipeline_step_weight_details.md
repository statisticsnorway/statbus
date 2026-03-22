```sql
                                   Table "worker.pipeline_step_weight"
 Column |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+----------+-------------+--------------+-------------
 step   | text    |           | not null |         | extended |             |              | 
 weight | integer |           | not null |         | plain    |             |              | 
 seq    | integer |           | not null | 0       | plain    |             |              | 
 phase  | text    |           | not null |         | extended |             |              | 
Indexes:
    "pipeline_step_weight_pkey" PRIMARY KEY, btree (step)
Check constraints:
    "pipeline_step_weight_weight_check" CHECK (weight > 0)
Foreign-key constraints:
    "pipeline_step_weight_step_fkey" FOREIGN KEY (step) REFERENCES worker.command_registry(command)
Not-null constraints:
    "pipeline_step_weight_step_not_null" NOT NULL "step"
    "pipeline_step_weight_weight_not_null" NOT NULL "weight"
    "pipeline_step_weight_seq_not_null" NOT NULL "seq"
    "pipeline_step_weight_phase_not_null" NOT NULL "phase"
Access method: heap

```
