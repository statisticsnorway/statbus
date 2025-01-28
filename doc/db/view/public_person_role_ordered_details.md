```sql
                                View "public.person_role_ordered"
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
 SELECT person_role.id,
    person_role.code,
    person_role.name,
    person_role.active,
    person_role.custom,
    person_role.created_at,
    person_role.updated_at
   FROM person_role
  ORDER BY person_role.code;
Options: security_invoker=on

```
