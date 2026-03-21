```sql
                                                   Table "worker.tasks"
         Column         |           Type           | Collation | Nullable |                    Default                    
------------------------+--------------------------+-----------+----------+-----------------------------------------------
 id                     | bigint                   |           | not null | nextval('worker.tasks_id_seq'::regclass)
 command                | text                     |           | not null | 
 priority               | bigint                   |           |          | nextval('worker_task_priority_seq'::regclass)
 created_at             | timestamp with time zone |           |          | now()
 state                  | worker.task_state        |           |          | 'pending'::worker.task_state
 process_start_at       | timestamp with time zone |           |          | 
 completed_at           | timestamp with time zone |           |          | 
 process_duration_ms    | numeric                  |           |          | 
 error                  | text                     |           |          | 
 scheduled_at           | timestamp with time zone |           |          | 
 worker_pid             | integer                  |           |          | 
 payload                | jsonb                    |           |          | 
 parent_id              | bigint                   |           |          | 
 child_mode             | worker.child_mode        |           |          | 
 depth                  | integer                  |           | not null | 0
 process_stop_at        | timestamp with time zone |           |          | 
 completion_duration_ms | numeric                  |           |          | 
 info                   | jsonb                    |           |          | 
Indexes:
    "tasks_pkey" PRIMARY KEY, btree (id)
    "idx_tasks_collect_changes_dedup" UNIQUE, btree (command) WHERE command = 'collect_changes'::text AND state = 'pending'::worker.task_state
    "idx_tasks_depth" btree (depth) WHERE state = 'waiting'::worker.task_state
    "idx_tasks_import_job_cleanup_dedup" UNIQUE, btree (command) WHERE command = 'import_job_cleanup'::text AND state = 'pending'::worker.task_state
    "idx_tasks_parent_id" btree (parent_id) WHERE parent_id IS NOT NULL
    "idx_tasks_scheduled_at" btree (scheduled_at) WHERE state = 'pending'::worker.task_state AND scheduled_at IS NOT NULL
    "idx_tasks_task_cleanup_dedup" UNIQUE, btree (command) WHERE command = 'task_cleanup'::text AND state = 'pending'::worker.task_state
    "idx_tasks_waiting" btree (state) WHERE state = 'waiting'::worker.task_state
    "idx_worker_tasks_pending_priority" btree (state, priority) WHERE state = 'pending'::worker.task_state
Check constraints:
    "check_payload_type" CHECK (payload IS NULL OR jsonb_typeof(payload) = 'object'::text OR jsonb_typeof(payload) = 'null'::text)
    "consistent_command_in_payload" CHECK (command = (payload ->> 'command'::text))
    "error_required_when_failed" CHECK (
CASE state
    WHEN 'failed'::worker.task_state THEN error IS NOT NULL
    ELSE error IS NULL
END)
Foreign-key constraints:
    "fk_tasks_command" FOREIGN KEY (command) REFERENCES worker.command_registry(command)
    "tasks_command_fkey" FOREIGN KEY (command) REFERENCES worker.command_registry(command)
    "tasks_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES worker.tasks(id)
Referenced by:
    TABLE "worker.tasks" CONSTRAINT "tasks_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES worker.tasks(id)
Triggers:
    trg_notify_task_changed AFTER UPDATE ON worker.tasks FOR EACH ROW EXECUTE FUNCTION worker.notify_task_changed()

```
