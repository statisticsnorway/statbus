```sql
                                                                                                                             Table "worker.tasks"
         Column         |           Type           | Collation | Nullable |                    Default                    | Storage  | Compression | Stats target |                                                Description                                                 
------------------------+--------------------------+-----------+----------+-----------------------------------------------+----------+-------------+--------------+------------------------------------------------------------------------------------------------------------
 id                     | bigint                   |           | not null | nextval('worker.tasks_id_seq'::regclass)      | plain    |             |              | 
 command                | text                     |           | not null |                                               | extended |             |              | 
 priority               | bigint                   |           |          | nextval('worker_task_priority_seq'::regclass) | plain    |             |              | 
 created_at             | timestamp with time zone |           |          | now()                                         | plain    |             |              | 
 state                  | worker.task_state        |           |          | 'pending'::worker.task_state                  | plain    |             |              | 
 process_start_at       | timestamp with time zone |           |          |                                               | plain    |             |              | 
 completed_at           | timestamp with time zone |           |          |                                               | plain    |             |              | 
 process_duration_ms    | numeric                  |           |          |                                               | main     |             |              | Handler execution time only: process_stop_at - process_start_at.                                          +
                        |                          |           |          |                                               |          |             |              | Excludes child execution. For leaf tasks equals completion_duration_ms.
 error                  | text                     |           |          |                                               | extended |             |              | 
 scheduled_at           | timestamp with time zone |           |          |                                               | plain    |             |              | 
 worker_pid             | integer                  |           |          |                                               | plain    |             |              | 
 payload                | jsonb                    |           |          |                                               | extended |             |              | 
 parent_id              | bigint                   |           |          |                                               | plain    |             |              | 
 child_mode             | worker.child_mode        |           |          |                                               | plain    |             |              | How this task's children are processed. concurrent = parallel, serial = one at a time.                    +
                        |                          |           |          |                                               |          |             |              | NULL = leaf task (no children). Set automatically by spawn() on first child.
 depth                  | integer                  |           | not null | 0                                             | plain    |             |              | Task tree depth: 0 = top-level, parent.depth + 1 for children.                                            +
                        |                          |           |          |                                               |          |             |              | Used by process_tasks for depth-first ordering (ORDER BY depth DESC)                                      +
                        |                          |           |          |                                               |          |             |              | so deeper work completes before shallower work resumes.
 process_stop_at        | timestamp with time zone |           |          |                                               | plain    |             |              | When the handler procedure returned (before waiting for children).                                        +
                        |                          |           |          |                                               |          |             |              | For leaf tasks: approximately equals completed_at.                                                        +
                        |                          |           |          |                                               |          |             |              | For parent tasks: completed_at > process_stop_at (gap = child execution time).
 completion_duration_ms | numeric                  |           |          |                                               | main     |             |              | Total wall-clock time: completed_at - process_start_at.                                                   +
                        |                          |           |          |                                               |          |             |              | For parent tasks includes all child execution (completion_duration_ms - process_duration_ms = child time).
 info                   | jsonb                    |           |          |                                               | extended |             |              | Handler output via INOUT p_info jsonb. Each handler reports only what it did (Info Principle).            +
                        |                          |           |          |                                               |          |             |              | On parent completion, children's info is aggregated: numeric values are SUMmed,                           +
                        |                          |           |          |                                               |          |             |              | non-numeric values take the last child's value. Parent's own info overwrites via ||.
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
Not-null constraints:
    "tasks_id_not_null" NOT NULL "id"
    "tasks_command_not_null" NOT NULL "command"
    "tasks_depth_not_null" NOT NULL "depth"
Triggers:
    trg_notify_task_changed AFTER UPDATE ON worker.tasks FOR EACH ROW EXECUTE FUNCTION worker.notify_task_changed()
Access method: heap

```
