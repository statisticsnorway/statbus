```sql
                                                       Table "auth.audit_log_entries"
   Column    |           Type           | Collation | Nullable |        Default        | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+-----------------------+----------+-------------+--------------+-------------
 instance_id | uuid                     |           |          |                       | plain    |             |              | 
 id          | uuid                     |           | not null |                       | plain    |             |              | 
 payload     | json                     |           |          |                       | extended |             |              | 
 created_at  | timestamp with time zone |           |          |                       | plain    |             |              | 
 ip_address  | character varying(64)    |           | not null | ''::character varying | extended |             |              | 
Indexes:
    "audit_log_entries_pkey" PRIMARY KEY, btree (id)
    "audit_logs_instance_id_idx" btree (instance_id)
Policies (row security enabled): (none)
Access method: heap

```
