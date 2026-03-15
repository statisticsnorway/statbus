```sql
                            View "public.tag_ordered"
       Column        |           Type           | Collation | Nullable | Default 
---------------------+--------------------------+-----------+----------+---------
 id                  | integer                  |           |          | 
 path                | ltree                    |           |          | 
 parent_id           | integer                  |           |          | 
 level               | integer                  |           |          | 
 label               | character varying        |           |          | 
 code                | character varying        |           |          | 
 name                | character varying(256)   |           |          | 
 description         | text                     |           |          | 
 enabled             | boolean                  |           |          | 
 context_valid_from  | date                     |           |          | 
 context_valid_to    | date                     |           |          | 
 context_valid_until | date                     |           |          | 
 context_valid_on    | date                     |           |          | 
 created_at          | timestamp with time zone |           |          | 
 updated_at          | timestamp with time zone |           |          | 
 custom              | boolean                  |           |          | 

```
