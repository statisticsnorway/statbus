```sql
                           View "public.enterprise_group_type_ordered"
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
 SELECT enterprise_group_type.id,
    enterprise_group_type.code,
    enterprise_group_type.name,
    enterprise_group_type.active,
    enterprise_group_type.custom,
    enterprise_group_type.created_at,
    enterprise_group_type.updated_at
   FROM enterprise_group_type
  ORDER BY enterprise_group_type.code;
Options: security_invoker=on

```
