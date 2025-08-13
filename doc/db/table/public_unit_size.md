```sql
                                  Table "public.unit_size"
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
    "unit_size_pkey" PRIMARY KEY, btree (id)
    "ix_unit_size_active" btree (active)
    "ix_unit_size_active_code" UNIQUE, btree (active, code)
    "ix_unit_size_code" UNIQUE, btree (code) WHERE active
Referenced by:
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
    TABLE "establishment" CONSTRAINT "establishment_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
    TABLE "legal_unit" CONSTRAINT "legal_unit_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Policies:
    POLICY "unit_size_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "unit_size_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "unit_size_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_unit_size_id_update BEFORE UPDATE OF id ON unit_size FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
