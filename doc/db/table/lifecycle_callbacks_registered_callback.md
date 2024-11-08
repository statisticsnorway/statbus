```sql
                                          Table "lifecycle_callbacks.registered_callback"
       Column       |    Type    | Collation | Nullable |                                  Default                                  
--------------------+------------+-----------+----------+---------------------------------------------------------------------------
 label              | text       |           | not null | 
 priority           | integer    |           | not null | nextval('lifecycle_callbacks.registered_callback_priority_seq'::regclass)
 table_names        | regclass[] |           |          | 
 generate_procedure | regproc    |           | not null | 
 cleanup_procedure  | regproc    |           | not null | 
Indexes:
    "registered_callback_pkey" PRIMARY KEY, btree (label)

```
