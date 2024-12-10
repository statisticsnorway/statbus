```sql
                           Table "auth.instances"
     Column      |           Type           | Collation | Nullable | Default 
-----------------+--------------------------+-----------+----------+---------
 id              | uuid                     |           | not null | 
 uuid            | uuid                     |           |          | 
 raw_base_config | text                     |           |          | 
 created_at      | timestamp with time zone |           |          | 
 updated_at      | timestamp with time zone |           |          | 
Indexes:
    "instances_pkey" PRIMARY KEY, btree (id)
Policies (row security enabled): (none)

```
