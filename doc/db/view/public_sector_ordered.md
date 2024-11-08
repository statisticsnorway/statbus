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
 active      | boolean                  |           |          | 
 custom      | boolean                  |           |          | 
 updated_at  | timestamp with time zone |           |          | 

```
