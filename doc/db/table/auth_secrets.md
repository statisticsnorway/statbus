```sql
                                                          Table "auth.secrets"
   Column    |           Type           | Collation | Nullable |      Default      | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+-------------------+----------+-------------+--------------+-------------
 key         | text                     |           | not null |                   | extended |             |              | 
 value       | text                     |           | not null |                   | extended |             |              | 
 description | text                     |           |          |                   | extended |             |              | 
 created_at  | timestamp with time zone |           | not null | clock_timestamp() | plain    |             |              | 
 updated_at  | timestamp with time zone |           | not null | clock_timestamp() | plain    |             |              | 
Indexes:
    "secrets_pkey" PRIMARY KEY, btree (key)
Policies (forced row security enabled): (none)
Not-null constraints:
    "secrets_key_not_null" NOT NULL "key"
    "secrets_value_not_null" NOT NULL "value"
    "secrets_created_at_not_null" NOT NULL "created_at"
    "secrets_updated_at_not_null" NOT NULL "updated_at"
Access method: heap

```
