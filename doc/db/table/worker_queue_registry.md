```sql
                 Table "worker.queue_registry"
       Column        |  Type   | Collation | Nullable | Default 
---------------------+---------+-----------+----------+---------
 queue               | text    |           | not null | 
 description         | text    |           |          | 
 default_concurrency | integer |           | not null | 1
Indexes:
    "queue_registry_pkey" PRIMARY KEY, btree (queue)
Referenced by:
    TABLE "worker.command_registry" CONSTRAINT "command_registry_queue_fkey" FOREIGN KEY (queue) REFERENCES worker.queue_registry(queue)

```
