```sql
                                                                                                            Table "worker.queue_registry"
       Column        |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                                 Description                                                                 
---------------------+---------+-----------+----------+---------+----------+-------------+--------------+---------------------------------------------------------------------------------------------------------------------------------------------
 queue               | text    |           | not null |         | extended |             |              | 
 description         | text    |           |          |         | extended |             |              | 
 default_concurrency | integer |           | not null | 1       | plain    |             |              | Number of parallel workers for this queue. 1=serial (default). Higher values used for child task processing in structured concurrency mode.
Indexes:
    "queue_registry_pkey" PRIMARY KEY, btree (queue)
Referenced by:
    TABLE "worker.command_registry" CONSTRAINT "command_registry_queue_fkey" FOREIGN KEY (queue) REFERENCES worker.queue_registry(queue)
Not-null constraints:
    "queue_registry_queue_not_null" NOT NULL "queue"
    "queue_registry_default_concurrency_not_null" NOT NULL "default_concurrency"
Access method: heap

```
