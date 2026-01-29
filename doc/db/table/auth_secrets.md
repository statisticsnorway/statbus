```sql
                               Table "auth.secrets"
   Column    |           Type           | Collation | Nullable |      Default      
-------------+--------------------------+-----------+----------+-------------------
 key         | text                     |           | not null | 
 value       | text                     |           | not null | 
 description | text                     |           |          | 
 created_at  | timestamp with time zone |           | not null | clock_timestamp()
 updated_at  | timestamp with time zone |           | not null | clock_timestamp()
Indexes:
    "secrets_pkey" PRIMARY KEY, btree (key)
Policies (forced row security enabled): (none)

```
