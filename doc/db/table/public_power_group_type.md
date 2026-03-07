```sql
                               Table "public.power_group_type"
   Column   |           Type           | Collation | Nullable |           Default            
------------+--------------------------+-----------+----------+------------------------------
 id         | integer                  |           | not null | generated always as identity
 code       | text                     |           | not null | 
 name       | text                     |           | not null | 
 enabled    | boolean                  |           | not null | 
 custom     | boolean                  |           | not null | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()
 updated_at | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "power_group_type_pkey" PRIMARY KEY, btree (id)
    "ix_power_group_type_code" UNIQUE, btree (code) WHERE enabled
    "ix_power_group_type_enabled" btree (enabled)
    "ix_power_group_type_enabled_code" UNIQUE, btree (enabled, code)
    "power_group_type_code_key" UNIQUE CONSTRAINT, btree (code)
    "power_group_type_name_key" UNIQUE CONSTRAINT, btree (name)
Referenced by:
    TABLE "power_group" CONSTRAINT "power_group_type_id_fkey" FOREIGN KEY (type_id) REFERENCES power_group_type(id)
Policies:
    POLICY "power_group_type_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "power_group_type_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "power_group_type_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_power_group_type_id_update BEFORE UPDATE OF id ON power_group_type FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
