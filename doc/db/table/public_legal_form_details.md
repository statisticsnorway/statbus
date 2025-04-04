```sql
                                                             Table "public.legal_form"
   Column   |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id         | integer                  |           | not null | generated always as identity | plain    |             |              | 
 code       | text                     |           | not null |                              | extended |             |              | 
 name       | text                     |           | not null |                              | extended |             |              | 
 active     | boolean                  |           | not null |                              | plain    |             |              | 
 custom     | boolean                  |           | not null |                              | plain    |             |              | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 updated_at | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "legal_form_pkey" PRIMARY KEY, btree (id)
    "ix_legal_form_active_code" UNIQUE, btree (active, code)
    "ix_legal_form_code" UNIQUE, btree (code) WHERE active
    "legal_form_code_active_custom_key" UNIQUE CONSTRAINT, btree (code, active, custom)
Referenced by:
    TABLE "legal_unit" CONSTRAINT "legal_unit_legal_form_id_fkey" FOREIGN KEY (legal_form_id) REFERENCES legal_form(id)
Policies:
    POLICY "legal_form_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "legal_form_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_form_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_legal_form_id_update BEFORE UPDATE OF id ON legal_form FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
