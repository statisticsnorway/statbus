```sql
                             View "public.worker_task"
         Column         |           Type           | Collation | Nullable | Default 
------------------------+--------------------------+-----------+----------+---------
 id                     | bigint                   |           |          | 
 command                | text                     |           |          | 
 priority               | bigint                   |           |          | 
 state                  | worker.task_state        |           |          | 
 parent_id              | bigint                   |           |          | 
 depth                  | integer                  |           |          | 
 child_mode             | worker.child_mode        |           |          | 
 created_at             | timestamp with time zone |           |          | 
 process_start_at       | timestamp with time zone |           |          | 
 process_stop_at        | timestamp with time zone |           |          | 
 completed_at           | timestamp with time zone |           |          | 
 process_duration_ms    | numeric                  |           |          | 
 completion_duration_ms | numeric                  |           |          | 
 error                  | text                     |           |          | 
 scheduled_at           | timestamp with time zone |           |          | 
 worker_pid             | integer                  |           |          | 
 payload                | jsonb                    |           |          | 
 info                   | jsonb                    |           |          | 
 queue                  | text                     |           |          | 
 command_description    | text                     |           |          | 

```
