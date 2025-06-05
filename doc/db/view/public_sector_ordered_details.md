```sql
                                   View "public.sector_ordered"
   Column    |           Type           | Collation | Nullable | Default | Storage  | Description 
-------------+--------------------------+-----------+----------+---------+----------+-------------
 id          | integer                  |           |          |         | plain    | 
 path        | ltree                    |           |          |         | extended | 
 parent_id   | integer                  |           |          |         | plain    | 
 label       | character varying        |           |          |         | extended | 
 code        | character varying        |           |          |         | extended | 
 name        | text                     |           |          |         | extended | 
 description | text                     |           |          |         | extended | 
 active      | boolean                  |           |          |         | plain    | 
 custom      | boolean                  |           |          |         | plain    | 
 created_at  | timestamp with time zone |           |          |         | plain    | 
 updated_at  | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    path,
    parent_id,
    label,
    code,
    name,
    description,
    active,
    custom,
    created_at,
    updated_at
   FROM sector
  ORDER BY path;
Options: security_invoker=on

```
