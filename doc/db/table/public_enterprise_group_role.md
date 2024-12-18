```sql
                            Table "public.enterprise_group_role"
   Column   |           Type           | Collation | Nullable |           Default            
------------+--------------------------+-----------+----------+------------------------------
 id         | integer                  |           | not null | generated always as identity
 code       | text                     |           | not null | 
 name       | text                     |           | not null | 
 active     | boolean                  |           | not null | 
 custom     | boolean                  |           | not null | 
 updated_at | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "enterprise_group_role_pkey" PRIMARY KEY, btree (id)
    "ix_enterprise_group_role_active_code" UNIQUE, btree (active, code)
    "ix_enterprise_group_role_code" UNIQUE, btree (code) WHERE active
Policies:
    POLICY "enterprise_group_role_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_group_role_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "enterprise_group_role_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_enterprise_group_role_id_update BEFORE UPDATE OF id ON enterprise_group_role FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
