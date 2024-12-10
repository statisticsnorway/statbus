```sql
                            Table "auth.mfa_amr_claims"
        Column         |           Type           | Collation | Nullable | Default 
-----------------------+--------------------------+-----------+----------+---------
 session_id            | uuid                     |           | not null | 
 created_at            | timestamp with time zone |           | not null | 
 updated_at            | timestamp with time zone |           | not null | 
 authentication_method | text                     |           | not null | 
 id                    | uuid                     |           | not null | 
Indexes:
    "amr_id_pk" PRIMARY KEY, btree (id)
    "mfa_amr_claims_session_id_authentication_method_pkey" UNIQUE CONSTRAINT, btree (session_id, authentication_method)
Foreign-key constraints:
    "mfa_amr_claims_session_id_fkey" FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE
Policies (row security enabled): (none)

```
