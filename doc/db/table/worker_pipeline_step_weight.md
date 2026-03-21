```sql
        Table "worker.pipeline_step_weight"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 step   | text    |           | not null | 
 weight | integer |           | not null | 
 seq    | integer |           | not null | 0
 phase  | text    |           | not null | 
Indexes:
    "pipeline_step_weight_pkey" PRIMARY KEY, btree (step)
Check constraints:
    "pipeline_step_weight_weight_check" CHECK (weight > 0)
Foreign-key constraints:
    "pipeline_step_weight_step_fkey" FOREIGN KEY (step) REFERENCES worker.command_registry(command)

```
