```sql
                                          View "public.worker_task"
         Column         |           Type           | Collation | Nullable | Default | Storage  | Description 
------------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                     | bigint                   |           |          |         | plain    | 
 command                | text                     |           |          |         | extended | 
 priority               | bigint                   |           |          |         | plain    | 
 state                  | worker.task_state        |           |          |         | plain    | 
 parent_id              | bigint                   |           |          |         | plain    | 
 depth                  | integer                  |           |          |         | plain    | 
 child_mode             | worker.child_mode        |           |          |         | plain    | 
 created_at             | timestamp with time zone |           |          |         | plain    | 
 process_start_at       | timestamp with time zone |           |          |         | plain    | 
 process_stop_at        | timestamp with time zone |           |          |         | plain    | 
 completed_at           | timestamp with time zone |           |          |         | plain    | 
 process_duration_ms    | numeric                  |           |          |         | main     | 
 completion_duration_ms | numeric                  |           |          |         | main     | 
 error                  | text                     |           |          |         | extended | 
 scheduled_at           | timestamp with time zone |           |          |         | plain    | 
 worker_pid             | integer                  |           |          |         | plain    | 
 payload                | jsonb                    |           |          |         | extended | 
 info                   | jsonb                    |           |          |         | extended | 
 queue                  | text                     |           |          |         | extended | 
 command_description    | text                     |           |          |         | extended | 
View definition:
 SELECT t.id,
    t.command,
    t.priority,
    t.state,
    t.parent_id,
    t.depth,
    t.child_mode,
    t.created_at,
    t.process_start_at,
    t.process_stop_at,
    t.completed_at,
    t.process_duration_ms,
    t.completion_duration_ms,
    t.error,
    t.scheduled_at,
    t.worker_pid,
    t.payload,
    t.info,
    cr.queue,
    cr.description AS command_description
   FROM worker.tasks t
     JOIN worker.command_registry cr ON cr.command = t.command;
Options: security_invoker=on

```
