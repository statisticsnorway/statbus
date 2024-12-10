```sql
                                                       Table "auth.mfa_factors"
       Column       |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id                 | uuid                     |           | not null |         | plain    |             |              | 
 user_id            | uuid                     |           | not null |         | plain    |             |              | 
 friendly_name      | text                     |           |          |         | extended |             |              | 
 factor_type        | auth.factor_type         |           | not null |         | plain    |             |              | 
 status             | auth.factor_status       |           | not null |         | plain    |             |              | 
 created_at         | timestamp with time zone |           | not null |         | plain    |             |              | 
 updated_at         | timestamp with time zone |           | not null |         | plain    |             |              | 
 secret             | text                     |           |          |         | extended |             |              | 
 phone              | text                     |           |          |         | extended |             |              | 
 last_challenged_at | timestamp with time zone |           |          |         | plain    |             |              | 
Indexes:
    "mfa_factors_pkey" PRIMARY KEY, btree (id)
    "factor_id_created_at_idx" btree (user_id, created_at)
    "mfa_factors_last_challenged_at_key" UNIQUE CONSTRAINT, btree (last_challenged_at)
    "mfa_factors_phone_key" UNIQUE CONSTRAINT, btree (phone)
    "mfa_factors_user_friendly_name_unique" UNIQUE, btree (friendly_name, user_id) WHERE TRIM(BOTH FROM friendly_name) <> ''::text
    "mfa_factors_user_id_idx" btree (user_id)
    "unique_verified_phone_factor" UNIQUE, btree (user_id, phone)
Foreign-key constraints:
    "mfa_factors_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
Referenced by:
    TABLE "auth.mfa_challenges" CONSTRAINT "mfa_challenges_auth_factor_id_fkey" FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE
Policies (row security enabled): (none)
Access method: heap

```
