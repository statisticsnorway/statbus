```sql
                                 View "public.unit_size_ordered"
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
 SELECT unit_size.id,
    unit_size.code,
    unit_size.name,
    unit_size.active,
    unit_size.custom,
    unit_size.created_at,
    unit_size.updated_at
   FROM unit_size
  ORDER BY unit_size.code;
Options: security_invoker=on

```
