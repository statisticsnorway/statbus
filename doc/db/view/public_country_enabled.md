```sql
                                  View "public.country_enabled"
   Column   |           Type           | Collation | Nullable | Default | Storage  | Description 
------------+--------------------------+-----------+----------+---------+----------+-------------
 id         | integer                  |           |          |         | plain    | 
 iso_2      | text                     |           |          |         | extended | 
 iso_3      | text                     |           |          |         | extended | 
 iso_num    | text                     |           |          |         | extended | 
 name       | text                     |           |          |         | extended | 
 enabled    | boolean                  |           |          |         | plain    | 
 custom     | boolean                  |           |          |         | plain    | 
 created_at | timestamp with time zone |           |          |         | plain    | 
 updated_at | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    iso_2,
    iso_3,
    iso_num,
    name,
    enabled,
    custom,
    created_at,
    updated_at
   FROM country_ordered
  WHERE enabled;
Options: security_invoker=on

```
