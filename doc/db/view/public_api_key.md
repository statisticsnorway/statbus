```sql
                          View "public.api_key"
   Column    |           Type           | Collation | Nullable | Default 
-------------+--------------------------+-----------+----------+---------
 id          | integer                  |           |          | 
 jti         | uuid                     |           |          | 
 user_id     | integer                  |           |          | 
 description | text                     |           |          | 
 created_at  | timestamp with time zone |           |          | 
 expires_at  | timestamp with time zone |           |          | 
 revoked_at  | timestamp with time zone |           |          | 
 token       | text                     |           |          | 

```
