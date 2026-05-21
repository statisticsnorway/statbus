```sql
                                      View "public.api_key"
   Column    |           Type           | Collation | Nullable | Default | Storage  | Description 
-------------+--------------------------+-----------+----------+---------+----------+-------------
 id          | integer                  |           |          |         | plain    | 
 jti         | uuid                     |           |          |         | plain    | 
 user_id     | integer                  |           |          |         | plain    | 
 description | text                     |           |          |         | extended | 
 created_at  | timestamp with time zone |           |          |         | plain    | 
 expires_at  | timestamp with time zone |           |          |         | plain    | 
 revoked_at  | timestamp with time zone |           |          |         | plain    | 
 token       | text                     |           |          |         | extended | 
View definition:
 SELECT id,
    jti,
    user_id,
    description,
    created_at,
    expires_at,
    revoked_at,
    token
   FROM auth.api_key;
Options: security_invoker=true

```
