```sql
                                 Table "public.person_role"
   Column   |           Type           | Collation | Nullable |           Default            
------------+--------------------------+-----------+----------+------------------------------
 id         | integer                  |           | not null | generated always as identity
 code       | text                     |           | not null | 
 name       | text                     |           | not null | 
 active     | boolean                  |           | not null | 
 custom     | boolean                  |           | not null | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()
 updated_at | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "person_role_pkey" PRIMARY KEY, btree (id)
    "ix_person_role_active_code" UNIQUE, btree (active, code)
    "person_role_code_key" UNIQUE CONSTRAINT, btree (code)
    "person_role_name_key" UNIQUE CONSTRAINT, btree (name)
Referenced by:
    TABLE "person_for_unit" CONSTRAINT "person_for_unit_person_role_id_fkey" FOREIGN KEY (person_role_id) REFERENCES person_role(id)
Policies:
    POLICY "person_role_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "person_role_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "person_role_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_person_role_id_update BEFORE UPDATE OF id ON person_role FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
