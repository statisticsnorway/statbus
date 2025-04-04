```sql
                        Table "public.region_role"
  Column   |  Type   | Collation | Nullable |           Default            
-----------+---------+-----------+----------+------------------------------
 id        | integer |           | not null | generated always as identity
 role_id   | integer |           | not null | 
 region_id | integer |           | not null | 
Indexes:
    "region_role_pkey" PRIMARY KEY, btree (id)
    "ix_region_role" btree (region_id)
    "region_role_role_id_region_id_key" UNIQUE CONSTRAINT, btree (role_id, region_id)
Foreign-key constraints:
    "region_role_region_id_fkey" FOREIGN KEY (region_id) REFERENCES region(id) ON DELETE CASCADE
    "region_role_role_id_fkey" FOREIGN KEY (role_id) REFERENCES statbus_role(id) ON DELETE CASCADE
Policies:
    POLICY "region_role_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "region_role_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "region_role_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_region_role_id_update BEFORE UPDATE OF id ON region_role FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
