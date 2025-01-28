```sql
                               View "public.person_role_available"
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
 SELECT person_role_ordered.id,
    person_role_ordered.code,
    person_role_ordered.name,
    person_role_ordered.active,
    person_role_ordered.custom,
    person_role_ordered.created_at,
    person_role_ordered.updated_at
   FROM person_role_ordered
  WHERE person_role_ordered.active;
Options: security_invoker=on

```
