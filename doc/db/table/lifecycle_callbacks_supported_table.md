```sql
              Table "lifecycle_callbacks.supported_table"
          Column           |   Type   | Collation | Nullable | Default 
---------------------------+----------+-----------+----------+---------
 table_name                | regclass |           | not null | 
 after_insert_trigger_name | text     |           |          | 
 after_update_trigger_name | text     |           |          | 
 after_delete_trigger_name | text     |           |          | 
Indexes:
    "supported_table_pkey" PRIMARY KEY, btree (table_name)

```
