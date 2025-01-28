```sql
                                View "public.unit_size_available"
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
 SELECT unit_size_ordered.id,
    unit_size_ordered.code,
    unit_size_ordered.name,
    unit_size_ordered.active,
    unit_size_ordered.custom,
    unit_size_ordered.created_at,
    unit_size_ordered.updated_at
   FROM unit_size_ordered
  WHERE unit_size_ordered.active;
Options: security_invoker=on

```
