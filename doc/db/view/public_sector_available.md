```sql
                     View "public.sector_available"
   Column    |           Type           | Collation | Nullable | Default 
-------------+--------------------------+-----------+----------+---------
 id          | integer                  |           |          | 
 path        | ltree                    |           |          | 
 parent_id   | integer                  |           |          | 
 label       | character varying        |           |          | 
 code        | character varying        |           |          | 
 name        | text                     |           |          | 
 description | text                     |           |          | 
 active      | boolean                  |           |          | 
 custom      | boolean                  |           |          | 
 created_at  | timestamp with time zone |           |          | 
 updated_at  | timestamp with time zone |           |          | 

```
