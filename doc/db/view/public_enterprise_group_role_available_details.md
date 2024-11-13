```sql
                          View "public.enterprise_group_role_available"
   Column   |           Type           | Collation | Nullable | Default | Storage  | Description 
------------+--------------------------+-----------+----------+---------+----------+-------------
 id         | integer                  |           |          |         | plain    | 
 code       | text                     |           |          |         | extended | 
 name       | text                     |           |          |         | extended | 
 active     | boolean                  |           |          |         | plain    | 
 custom     | boolean                  |           |          |         | plain    | 
 updated_at | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT enterprise_group_role_ordered.id,
    enterprise_group_role_ordered.code,
    enterprise_group_role_ordered.name,
    enterprise_group_role_ordered.active,
    enterprise_group_role_ordered.custom,
    enterprise_group_role_ordered.updated_at
   FROM enterprise_group_role_ordered
  WHERE enterprise_group_role_ordered.active;
Options: security_invoker=on

```
