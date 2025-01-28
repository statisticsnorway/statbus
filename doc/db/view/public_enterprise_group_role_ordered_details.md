```sql
                           View "public.enterprise_group_role_ordered"
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
 SELECT enterprise_group_role.id,
    enterprise_group_role.code,
    enterprise_group_role.name,
    enterprise_group_role.active,
    enterprise_group_role.custom,
    enterprise_group_role.created_at,
    enterprise_group_role.updated_at
   FROM enterprise_group_role
  ORDER BY enterprise_group_role.code;
Options: security_invoker=on

```
