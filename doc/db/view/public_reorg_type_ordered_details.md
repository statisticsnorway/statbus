```sql
                                 View "public.reorg_type_ordered"
   Column    |           Type           | Collation | Nullable | Default | Storage  | Description 
-------------+--------------------------+-----------+----------+---------+----------+-------------
 id          | integer                  |           |          |         | plain    | 
 code        | text                     |           |          |         | extended | 
 name        | text                     |           |          |         | extended | 
 description | text                     |           |          |         | extended | 
 active      | boolean                  |           |          |         | plain    | 
 custom      | boolean                  |           |          |         | plain    | 
 updated_at  | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT reorg_type.id,
    reorg_type.code,
    reorg_type.name,
    reorg_type.description,
    reorg_type.active,
    reorg_type.custom,
    reorg_type.updated_at
   FROM reorg_type
  ORDER BY reorg_type.code;
Options: security_invoker=on

```
