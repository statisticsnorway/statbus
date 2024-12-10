```sql
                            Table "auth.audit_log_entries"
   Column    |           Type           | Collation | Nullable |        Default        
-------------+--------------------------+-----------+----------+-----------------------
 instance_id | uuid                     |           |          | 
 id          | uuid                     |           | not null | 
 payload     | json                     |           |          | 
 created_at  | timestamp with time zone |           |          | 
 ip_address  | character varying(64)    |           | not null | ''::character varying
Indexes:
    "audit_log_entries_pkey" PRIMARY KEY, btree (id)
    "audit_logs_instance_id_idx" btree (instance_id)
Policies (row security enabled): (none)

```
