```sql
                                     View "public.legal_rel_type_ordered"
         Column          |           Type           | Collation | Nullable | Default | Storage  | Description 
-------------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                      | integer                  |           |          |         | plain    | 
 code                    | text                     |           |          |         | extended | 
 name                    | text                     |           |          |         | extended | 
 description             | text                     |           |          |         | extended | 
 primary_influencer_only | boolean                  |           |          |         | plain    | 
 enabled                 | boolean                  |           |          |         | plain    | 
 custom                  | boolean                  |           |          |         | plain    | 
 created_at              | timestamp with time zone |           |          |         | plain    | 
 updated_at              | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    name,
    description,
    primary_influencer_only,
    enabled,
    custom,
    created_at,
    updated_at
   FROM legal_rel_type
  ORDER BY code;
Options: security_invoker=on

```
