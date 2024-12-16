```sql
                                                                                                                                              Table "auth.users"
           Column            |           Type           | Collation | Nullable |                                  Default                                   | Storage  | Compression | Stats target |                                               Description                                                
-----------------------------+--------------------------+-----------+----------+----------------------------------------------------------------------------+----------+-------------+--------------+----------------------------------------------------------------------------------------------------------
 instance_id                 | uuid                     |           |          |                                                                            | plain    |             |              | 
 id                          | uuid                     |           | not null |                                                                            | plain    |             |              | 
 aud                         | character varying(255)   |           |          |                                                                            | extended |             |              | 
 role                        | character varying(255)   |           |          |                                                                            | extended |             |              | 
 email                       | character varying(255)   |           |          |                                                                            | extended |             |              | 
 encrypted_password          | character varying(255)   |           |          |                                                                            | extended |             |              | 
 email_confirmed_at          | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 invited_at                  | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 confirmation_token          | character varying(255)   |           |          |                                                                            | extended |             |              | 
 confirmation_sent_at        | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 recovery_token              | character varying(255)   |           |          |                                                                            | extended |             |              | 
 recovery_sent_at            | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 email_change_token_new      | character varying(255)   |           |          |                                                                            | extended |             |              | 
 email_change                | character varying(255)   |           |          |                                                                            | extended |             |              | 
 email_change_sent_at        | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 last_sign_in_at             | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 raw_app_meta_data           | jsonb                    |           |          |                                                                            | extended |             |              | 
 raw_user_meta_data          | jsonb                    |           |          |                                                                            | extended |             |              | 
 is_super_admin              | boolean                  |           |          |                                                                            | plain    |             |              | 
 created_at                  | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 updated_at                  | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 phone                       | text                     |           |          | NULL::character varying                                                    | extended |             |              | 
 phone_confirmed_at          | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 phone_change                | text                     |           |          | ''::character varying                                                      | extended |             |              | 
 phone_change_token          | character varying(255)   |           |          | ''::character varying                                                      | extended |             |              | 
 phone_change_sent_at        | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 confirmed_at                | timestamp with time zone |           |          | generated always as (LEAST(email_confirmed_at, phone_confirmed_at)) stored | plain    |             |              | 
 email_change_token_current  | character varying(255)   |           |          | ''::character varying                                                      | extended |             |              | 
 email_change_confirm_status | smallint                 |           |          | 0                                                                          | plain    |             |              | 
 banned_until                | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 reauthentication_token      | character varying(255)   |           |          | ''::character varying                                                      | extended |             |              | 
 reauthentication_sent_at    | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 is_sso_user                 | boolean                  |           | not null | false                                                                      | plain    |             |              | Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.
 deleted_at                  | timestamp with time zone |           |          |                                                                            | plain    |             |              | 
 is_anonymous                | boolean                  |           | not null | false                                                                      | plain    |             |              | 
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
    "confirmation_token_idx" UNIQUE, btree (confirmation_token) WHERE confirmation_token::text !~ '^[0-9 ]*$'::text
    "email_change_token_current_idx" UNIQUE, btree (email_change_token_current) WHERE email_change_token_current::text !~ '^[0-9 ]*$'::text
    "email_change_token_new_idx" UNIQUE, btree (email_change_token_new) WHERE email_change_token_new::text !~ '^[0-9 ]*$'::text
    "reauthentication_token_idx" UNIQUE, btree (reauthentication_token) WHERE reauthentication_token::text !~ '^[0-9 ]*$'::text
    "recovery_token_idx" UNIQUE, btree (recovery_token) WHERE recovery_token::text !~ '^[0-9 ]*$'::text
    "users_email_key" UNIQUE CONSTRAINT, btree (email)
    "users_email_partial_key" UNIQUE, btree (email) WHERE is_sso_user = false
    "users_instance_id_email_idx" btree (instance_id, lower(email::text))
    "users_instance_id_idx" btree (instance_id)
    "users_is_anonymous_idx" btree (is_anonymous)
    "users_phone_key" UNIQUE CONSTRAINT, btree (phone)
Check constraints:
    "users_email_change_confirm_status_check" CHECK (email_change_confirm_status >= 0 AND email_change_confirm_status <= 2)
Referenced by:
    TABLE "auth.identities" CONSTRAINT "identities_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
    TABLE "auth.mfa_factors" CONSTRAINT "mfa_factors_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
    TABLE "auth.one_time_tokens" CONSTRAINT "one_time_tokens_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
    TABLE "auth.sessions" CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
    TABLE "statbus_user" CONSTRAINT "statbus_user_uuid_fkey" FOREIGN KEY (uuid) REFERENCES auth.users(id) ON DELETE CASCADE
Policies (row security enabled): (none)
Triggers:
    on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION admin.create_new_statbus_user()
Access method: heap

```
