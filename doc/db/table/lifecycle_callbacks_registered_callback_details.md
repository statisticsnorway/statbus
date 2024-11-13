```sql
                                                                     Table "lifecycle_callbacks.registered_callback"
       Column       |    Type    | Collation | Nullable |                                  Default                                  | Storage  | Compression | Stats target | Description 
--------------------+------------+-----------+----------+---------------------------------------------------------------------------+----------+-------------+--------------+-------------
 label              | text       |           | not null |                                                                           | extended |             |              | 
 priority           | integer    |           | not null | nextval('lifecycle_callbacks.registered_callback_priority_seq'::regclass) | plain    |             |              | 
 table_names        | regclass[] |           |          |                                                                           | extended |             |              | 
 generate_procedure | regproc    |           | not null |                                                                           | plain    |             |              | 
 cleanup_procedure  | regproc    |           | not null |                                                                           | plain    |             |              | 
Indexes:
    "registered_callback_pkey" PRIMARY KEY, btree (label)
Access method: heap

```
