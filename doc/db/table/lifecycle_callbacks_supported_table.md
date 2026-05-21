```sql
                                         Table "lifecycle_callbacks.supported_table"
          Column           |   Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
---------------------------+----------+-----------+----------+---------+----------+-------------+--------------+-------------
 table_name                | regclass |           | not null |         | plain    |             |              | 
 after_insert_trigger_name | text     |           |          |         | extended |             |              | 
 after_update_trigger_name | text     |           |          |         | extended |             |              | 
 after_delete_trigger_name | text     |           |          |         | extended |             |              | 
Indexes:
    "supported_table_pkey" PRIMARY KEY, btree (table_name)
Not-null constraints:
    "supported_table_table_name_not_null" NOT NULL "table_name"
Access method: heap

```
