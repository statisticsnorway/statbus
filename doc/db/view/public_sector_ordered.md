```sql
                      View "public.sector_ordered"
   Column    |           Type           | Collation | Nullable | Default 
-------------+--------------------------+-----------+----------+---------
 id          | integer                  |           |          | 
 path        | ltree                    |           |          | 
 parent_id   | integer                  |           |          | 
 label       | character varying        |           |          | 
 code        | character varying        |           |          | 
 name        | text                     |           |          | 
 description | text                     |           |          | 
 enabled     | boolean                  |           |          | 
 custom      | boolean                  |           |          | 
 created_at  | timestamp with time zone |           |          | 
 updated_at  | timestamp with time zone |           |          | 

```
