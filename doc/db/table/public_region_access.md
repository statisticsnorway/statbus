```sql
                       Table "public.region_access"
  Column   |  Type   | Collation | Nullable |           Default            
-----------+---------+-----------+----------+------------------------------
 id        | integer |           | not null | generated always as identity
 user_id   | integer |           | not null | 
 region_id | integer |           | not null | 
Indexes:
    "region_access_pkey" PRIMARY KEY, btree (id)
    "ix_region_access_region_id" btree (region_id)
    "ix_region_access_user_id" btree (user_id)
    "region_access_user_id_region_id_key" UNIQUE CONSTRAINT, btree (user_id, region_id)
Foreign-key constraints:
    "region_access_region_id_fkey" FOREIGN KEY (region_id) REFERENCES region(id) ON DELETE CASCADE
    "region_access_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
Policies:
    POLICY "region_access_admin_policy"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "region_access_read_policy" FOR SELECT
      TO authenticated
      USING (true)
Triggers:
    trigger_prevent_region_access_id_update BEFORE UPDATE OF id ON region_access FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
