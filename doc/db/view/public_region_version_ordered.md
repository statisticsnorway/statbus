```sql
                               View "public.region_version_ordered"
   Column    |           Type           | Collation | Nullable | Default | Storage  | Description 
-------------+--------------------------+-----------+----------+---------+----------+-------------
 id          | integer                  |           |          |         | plain    | 
 code        | text                     |           |          |         | extended | 
 name        | text                     |           |          |         | extended | 
 description | text                     |           |          |         | extended | 
 lasts_to    | date                     |           |          |         | plain    | 
 enabled     | boolean                  |           |          |         | plain    | 
 custom      | boolean                  |           |          |         | plain    | 
 created_at  | timestamp with time zone |           |          |         | plain    | 
 updated_at  | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    name,
    description,
    lasts_to,
    enabled,
    custom,
    created_at,
    updated_at
   FROM region_version
  ORDER BY code;
Options: security_invoker=on

```
