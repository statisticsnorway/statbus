```sql
                                       View "public.status_ordered"
       Column        |           Type           | Collation | Nullable | Default | Storage  | Description 
---------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                  | integer                  |           |          |         | plain    | 
 code                | character varying        |           |          |         | extended | 
 name                | text                     |           |          |         | extended | 
 assigned_by_default | boolean                  |           |          |         | plain    | 
 used_for_counting   | boolean                  |           |          |         | plain    | 
 priority            | integer                  |           |          |         | plain    | 
 enabled             | boolean                  |           |          |         | plain    | 
 custom              | boolean                  |           |          |         | plain    | 
 created_at          | timestamp with time zone |           |          |         | plain    | 
 updated_at          | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    name,
    assigned_by_default,
    used_for_counting,
    priority,
    enabled,
    custom,
    created_at,
    updated_at
   FROM status
  ORDER BY priority, code;
Options: security_invoker=on

```
