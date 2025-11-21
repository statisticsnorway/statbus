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
Not-null constraints:
    "registered_callback_label_not_null" NOT NULL "label"
    "registered_callback_priority_not_null" NOT NULL "priority"
    "registered_callback_generate_procedure_not_null" NOT NULL "generate_procedure"
    "registered_callback_cleanup_procedure_not_null" NOT NULL "cleanup_procedure"
Access method: heap

```
