```sql
                                                                                                                                                 Table "worker.queue_registry"
       Column        |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                                                                     Description                                                                                                      
---------------------+---------+-----------+----------+---------+----------+-------------+--------------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 queue               | text    |           | not null |         | extended |             |              | 
 description         | text    |           |          |         | extended |             |              | 
 default_concurrency | integer |           | not null | 1       | plain    |             |              | Default number of concurrent child executors for this queue, in addition to its serial coordinator. Existing per-queue worker overrides take precedence. A value of one processes concurrent children one at a time.
Indexes:
    "queue_registry_pkey" PRIMARY KEY, btree (queue)
Referenced by:
    TABLE "worker.command_registry" CONSTRAINT "command_registry_queue_fkey" FOREIGN KEY (queue) REFERENCES worker.queue_registry(queue)
Not-null constraints:
    "queue_registry_queue_not_null" NOT NULL "queue"
    "queue_registry_default_concurrency_not_null" NOT NULL "default_concurrency"
Access method: heap

```

**Comment:** Defines task queues discovered by the worker. Each queue has one serial coordinator and its configured concurrent child executors. Queues run independently, while child_mode and the structured-concurrency barrier determine task ordering.
