```sql
                          View "public.enterprise_group_role_available"
   Column   |           Type           | Collation | Nullable | Default | Storage  | Description 
------------+--------------------------+-----------+----------+---------+----------+-------------
 id         | integer                  |           |          |         | plain    | 
 code       | text                     |           |          |         | extended | 
 name       | text                     |           |          |         | extended | 
 active     | boolean                  |           |          |         | plain    | 
 custom     | boolean                  |           |          |         | plain    | 
 created_at | timestamp with time zone |           |          |         | plain    | 
 updated_at | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    name,
    active,
    custom,
    created_at,
    updated_at
   FROM enterprise_group_role_ordered
  WHERE active;
Options: security_invoker=on

```
