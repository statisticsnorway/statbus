```sql
                                                                                                   Table "worker.command_registry"
       Column        |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                Description                                                
---------------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-----------------------------------------------------------------------------------------------------------
 command             | text                     |           | not null |         | extended |             |              | 
 handler_procedure   | text                     |           | not null |         | extended |             |              | 
 before_procedure    | text                     |           |          |         | extended |             |              | 
 after_procedure     | text                     |           |          |         | extended |             |              | 
 description         | text                     |           |          |         | extended |             |              | 
 queue               | text                     |           | not null |         | extended |             |              | 
 created_at          | timestamp with time zone |           | not null | now()   | plain    |             |              | 
 batches_per_wave    | integer                  |           |          |         | plain    |             |              | Number of child batch tasks to spawn per wave before an ANALYZE sync point. NULL means spawn all at once.
 phase               | worker.pipeline_phase    |           |          |         | plain    |             |              | 
 on_children_created | text                     |           |          |         | extended |             |              | 
 on_child_completed  | text                     |           |          |         | extended |             |              | 
Indexes:
    "command_registry_pkey" PRIMARY KEY, btree (command)
    "idx_command_registry_queue" btree (queue)
Foreign-key constraints:
    "command_registry_queue_fkey" FOREIGN KEY (queue) REFERENCES worker.queue_registry(queue)
Referenced by:
    TABLE "worker.tasks" CONSTRAINT "fk_tasks_command" FOREIGN KEY (command) REFERENCES worker.command_registry(command)
    TABLE "worker.pipeline_step_weight" CONSTRAINT "pipeline_step_weight_step_fkey" FOREIGN KEY (step) REFERENCES worker.command_registry(command)
    TABLE "worker.tasks" CONSTRAINT "tasks_command_fkey" FOREIGN KEY (command) REFERENCES worker.command_registry(command)
Not-null constraints:
    "command_registry_command_not_null" NOT NULL "command"
    "command_registry_handler_procedure_not_null" NOT NULL "handler_procedure"
    "command_registry_queue_not_null" NOT NULL "queue"
    "command_registry_created_at_not_null" NOT NULL "created_at"
Triggers:
    command_registry_queue_change_trigger AFTER INSERT OR UPDATE OF queue ON worker.command_registry FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_queue_change()
Access method: heap

```
