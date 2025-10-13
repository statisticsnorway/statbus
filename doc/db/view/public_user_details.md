```sql
                                           View "public.user"
       Column       |           Type           | Collation | Nullable | Default | Storage  | Description 
--------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                 | integer                  |           |          |         | plain    | 
 sub                | uuid                     |           |          |         | plain    | 
 display_name       | text                     |           |          |         | extended | 
 email              | text                     |           |          |         | extended | 
 password           | text                     |           |          |         | extended | 
 statbus_role       | statbus_role             |           |          |         | plain    | 
 created_at         | timestamp with time zone |           |          |         | plain    | 
 updated_at         | timestamp with time zone |           |          |         | plain    | 
 last_sign_in_at    | timestamp with time zone |           |          |         | plain    | 
 email_confirmed_at | timestamp with time zone |           |          |         | plain    | 
 deleted_at         | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    sub,
    display_name,
    email,
    password,
    statbus_role,
    created_at,
    updated_at,
    last_sign_in_at,
    email_confirmed_at,
    deleted_at
   FROM auth."user" u;
Options: security_barrier=true

```
