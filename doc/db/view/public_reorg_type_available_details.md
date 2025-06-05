```sql
                                View "public.reorg_type_available"
   Column    |           Type           | Collation | Nullable | Default | Storage  | Description 
-------------+--------------------------+-----------+----------+---------+----------+-------------
 id          | integer                  |           |          |         | plain    | 
 code        | text                     |           |          |         | extended | 
 name        | text                     |           |          |         | extended | 
 description | text                     |           |          |         | extended | 
 active      | boolean                  |           |          |         | plain    | 
 custom      | boolean                  |           |          |         | plain    | 
 created_at  | timestamp with time zone |           |          |         | plain    | 
 updated_at  | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    name,
    description,
    active,
    custom,
    created_at,
    updated_at
   FROM reorg_type_ordered
  WHERE active;
Options: security_invoker=on

```
