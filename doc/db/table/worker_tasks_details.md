```sql
                                                                         Table "worker.tasks"
    Column    |           Type           | Collation | Nullable |                    Default                    | Storage  | Compression | Stats target | Description 
--------------+--------------------------+-----------+----------+-----------------------------------------------+----------+-------------+--------------+-------------
 id           | bigint                   |           | not null | nextval('worker.tasks_id_seq'::regclass)      | plain    |             |              | 
 command      | text                     |           | not null |                                               | extended |             |              | 
 priority     | bigint                   |           |          | nextval('worker_task_priority_seq'::regclass) | plain    |             |              | 
 created_at   | timestamp with time zone |           |          | now()                                         | plain    |             |              | 
 state        | worker.task_state        |           |          | 'pending'::worker.task_state                  | plain    |             |              | 
 processed_at | timestamp with time zone |           |          |                                               | plain    |             |              | 
 completed_at | timestamp with time zone |           |          |                                               | plain    |             |              | 
 duration_ms  | numeric                  |           |          |                                               | main     |             |              | 
 error        | text                     |           |          |                                               | extended |             |              | 
 scheduled_at | timestamp with time zone |           |          |                                               | plain    |             |              | 
 worker_pid   | integer                  |           |          |                                               | plain    |             |              | 
 payload      | jsonb                    |           |          |                                               | extended |             |              | 
 parent_id    | bigint                   |           |          |                                               | plain    |             |              | 
 child_mode   | worker.child_mode        |           |          |                                               | plain    |             |              | 
 depth        | integer                  |           | not null | 0                                             | plain    |             |              | 
Indexes:
    "tasks_pkey" PRIMARY KEY, btree (id)
    "idx_tasks_collect_changes_dedup" UNIQUE, btree (command) WHERE command = 'collect_changes'::text AND state = 'pending'::worker.task_state
    "idx_tasks_depth" btree (depth) WHERE state = 'waiting'::worker.task_state
    "idx_tasks_derive_dedup" UNIQUE, btree (command) WHERE command = 'derive_statistical_unit'::text AND state = 'pending'::worker.task_state
    "idx_tasks_derive_history_facet_period_dedup" UNIQUE, btree (command, (payload ->> 'resolution'::text), (payload ->> 'year'::text), (payload ->> 'month'::text), ((payload ->> 'partition_seq'::text)::integer)) WHERE command = 'derive_statistical_history_facet_period'::text AND state = 'pending'::worker.task_state
    "idx_tasks_derive_reports_dedup" UNIQUE, btree (command) WHERE command = 'derive_reports'::text AND state = 'pending'::worker.task_state
    "idx_tasks_derive_statistical_history_dedup" UNIQUE, btree (command) WHERE command = 'derive_statistical_history'::text AND state = 'pending'::worker.task_state
    "idx_tasks_derive_statistical_history_facet_dedup" UNIQUE, btree (command) WHERE command = 'derive_statistical_history_facet'::text AND state = 'pending'::worker.task_state
    "idx_tasks_derive_statistical_unit_facet_dedup" UNIQUE, btree (command) WHERE command = 'derive_statistical_unit_facet'::text AND state = 'pending'::worker.task_state
    "idx_tasks_derive_statistical_unit_facet_partition_dedup" UNIQUE, btree (command, ((payload ->> 'partition_seq'::text)::integer)) WHERE command = 'derive_statistical_unit_facet_partition'::text AND state = 'pending'::worker.task_state
    "idx_tasks_flush_staging_dedup" UNIQUE, btree (command) WHERE command = 'statistical_unit_flush_staging'::text AND state = 'pending'::worker.task_state
    "idx_tasks_import_job_cleanup_dedup" UNIQUE, btree (command) WHERE command = 'import_job_cleanup'::text AND state = 'pending'::worker.task_state
    "idx_tasks_parent_id" btree (parent_id) WHERE parent_id IS NOT NULL
    "idx_tasks_scheduled_at" btree (scheduled_at) WHERE state = 'pending'::worker.task_state AND scheduled_at IS NOT NULL
    "idx_tasks_statistical_history_facet_reduce_dedup" UNIQUE, btree (command) WHERE command = 'statistical_history_facet_reduce'::text AND state = 'pending'::worker.task_state
    "idx_tasks_statistical_history_reduce_dedup" UNIQUE, btree (command) WHERE command = 'statistical_history_reduce'::text AND state = 'pending'::worker.task_state
    "idx_tasks_statistical_unit_facet_reduce_dedup" UNIQUE, btree (command) WHERE command = 'statistical_unit_facet_reduce'::text AND state = 'pending'::worker.task_state
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
Access method: heap

```
