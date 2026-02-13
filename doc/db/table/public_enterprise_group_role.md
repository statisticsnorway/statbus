```sql
                            Table "public.enterprise_group_role"
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
    "enterprise_group_role_pkey" PRIMARY KEY, btree (id)
    "ix_enterprise_group_role_code" UNIQUE, btree (code) WHERE enabled
    "ix_enterprise_group_role_enabled" btree (enabled)
    "ix_enterprise_group_role_enabled_code" UNIQUE, btree (enabled, code)
Policies:
    POLICY "enterprise_group_role_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "enterprise_group_role_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_group_role_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_enterprise_group_role_id_update BEFORE UPDATE OF id ON enterprise_group_role FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
