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
 SELECT reorg_type_ordered.id,
    reorg_type_ordered.code,
    reorg_type_ordered.name,
    reorg_type_ordered.description,
    reorg_type_ordered.active,
    reorg_type_ordered.custom,
    reorg_type_ordered.created_at,
    reorg_type_ordered.updated_at
   FROM reorg_type_ordered
  WHERE reorg_type_ordered.active;
Options: security_invoker=on

```
