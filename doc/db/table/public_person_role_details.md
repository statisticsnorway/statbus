```sql
                                                            Table "public.person_role"
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
    "person_role_pkey" PRIMARY KEY, btree (id)
    "ix_person_role_active" btree (active)
    "ix_person_role_active_code" UNIQUE, btree (active, code)
    "person_role_code_key" UNIQUE CONSTRAINT, btree (code)
    "person_role_name_key" UNIQUE CONSTRAINT, btree (name)
Referenced by:
    TABLE "person_for_unit" CONSTRAINT "person_for_unit_person_role_id_fkey" FOREIGN KEY (person_role_id) REFERENCES person_role(id)
Policies:
    POLICY "person_role_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "person_role_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "person_role_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_person_role_id_update BEFORE UPDATE OF id ON person_role FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
