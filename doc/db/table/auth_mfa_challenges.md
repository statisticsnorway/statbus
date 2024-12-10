```sql
                       Table "auth.mfa_challenges"
   Column    |           Type           | Collation | Nullable | Default 
-------------+--------------------------+-----------+----------+---------
 id          | uuid                     |           | not null | 
 factor_id   | uuid                     |           | not null | 
 created_at  | timestamp with time zone |           | not null | 
 verified_at | timestamp with time zone |           |          | 
 ip_address  | inet                     |           | not null | 
 otp_code    | text                     |           |          | 
Indexes:
    "mfa_challenges_pkey" PRIMARY KEY, btree (id)
    "mfa_challenge_created_at_idx" btree (created_at DESC)
Foreign-key constraints:
    "mfa_challenges_auth_factor_id_fkey" FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE
Policies (row security enabled): (none)

```
