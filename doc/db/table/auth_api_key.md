```sql
                                     Table "auth.api_key"
   Column    |           Type           | Collation | Nullable |           Default            
-------------+--------------------------+-----------+----------+------------------------------
 id          | integer                  |           | not null | generated always as identity
 jti         | uuid                     |           | not null | public.gen_random_uuid()
 user_id     | integer                  |           | not null | 
 description | text                     |           |          | 
 created_at  | timestamp with time zone |           | not null | now()
 expires_at  | timestamp with time zone |           | not null | 
 revoked_at  | timestamp with time zone |           |          | 
 token       | text                     |           |          | 
Indexes:
    "api_key_pkey" PRIMARY KEY, btree (id)
    "api_key_jti_key" UNIQUE CONSTRAINT, btree (jti)
    "api_key_user_id_idx" btree (user_id)
Foreign-key constraints:
    "api_key_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
Policies:
    POLICY "delete_own_api_keys" FOR DELETE
      USING ((user_id = auth.uid()))
    POLICY "insert_own_api_keys" FOR INSERT
      WITH CHECK ((user_id = auth.uid()))
    POLICY "revoke_own_api_keys" FOR UPDATE
      USING ((user_id = auth.uid()))
      WITH CHECK ((user_id = auth.uid()))
    POLICY "select_own_api_keys" FOR SELECT
      USING ((user_id = auth.uid()))
Triggers:
    generate_api_key_token_trigger BEFORE INSERT ON auth.api_key FOR EACH ROW EXECUTE FUNCTION auth.generate_api_key_token()

```
