```sql
                         Table "worker.command_registry"
       Column        |           Type           | Collation | Nullable | Default 
---------------------+--------------------------+-----------+----------+---------
 command             | text                     |           | not null | 
 handler_procedure   | text                     |           | not null | 
 before_procedure    | text                     |           |          | 
 after_procedure     | text                     |           |          | 
 description         | text                     |           |          | 
 queue               | text                     |           | not null | 
 created_at          | timestamp with time zone |           | not null | now()
 batches_per_wave    | integer                  |           |          | 
 phase               | worker.pipeline_phase    |           |          | 
 on_children_created | text                     |           |          | 
 on_child_completed  | text                     |           |          | 
Indexes:
    "command_registry_pkey" PRIMARY KEY, btree (command)
    "idx_command_registry_queue" btree (queue)
Foreign-key constraints:
    "command_registry_queue_fkey" FOREIGN KEY (queue) REFERENCES worker.queue_registry(queue)
Referenced by:
    TABLE "worker.tasks" CONSTRAINT "fk_tasks_command" FOREIGN KEY (command) REFERENCES worker.command_registry(command)
    TABLE "worker.pipeline_step_weight" CONSTRAINT "pipeline_step_weight_step_fkey" FOREIGN KEY (step) REFERENCES worker.command_registry(command)
    TABLE "worker.tasks" CONSTRAINT "tasks_command_fkey" FOREIGN KEY (command) REFERENCES worker.command_registry(command)
Triggers:
    command_registry_queue_change_trigger AFTER INSERT OR UPDATE OF queue ON worker.command_registry FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_queue_change()

```
