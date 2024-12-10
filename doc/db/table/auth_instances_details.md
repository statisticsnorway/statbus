```sql
                                                      Table "auth.instances"
     Column      |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
-----------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id              | uuid                     |           | not null |         | plain    |             |              | 
 uuid            | uuid                     |           |          |         | plain    |             |              | 
 raw_base_config | text                     |           |          |         | extended |             |              | 
 created_at      | timestamp with time zone |           |          |         | plain    |             |              | 
 updated_at      | timestamp with time zone |           |          |         | plain    |             |              | 
Indexes:
    "instances_pkey" PRIMARY KEY, btree (id)
Policies (row security enabled): (none)
Access method: heap

```
