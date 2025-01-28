```sql
                                Table "public.statbus_role"
   Column    |          Type          | Collation | Nullable |           Default            
-------------+------------------------+-----------+----------+------------------------------
 id          | integer                |           | not null | generated always as identity
 type        | statbus_role_type      |           | not null | 
 name        | character varying(256) |           | not null | 
 description | text                   |           |          | 
Indexes:
    "statbus_role_pkey" PRIMARY KEY, btree (id)
    "statbus_role_name_key" UNIQUE CONSTRAINT, btree (name)
    "statbus_role_role_type" UNIQUE, btree (type) WHERE type = 'super_user'::statbus_role_type OR type = 'regular_user'::statbus_role_type OR type = 'external_user'::statbus_role_type
Referenced by:
    TABLE "activity_category_role" CONSTRAINT "activity_category_role_role_id_fkey" FOREIGN KEY (role_id) REFERENCES statbus_role(id) ON DELETE CASCADE
    TABLE "region_role" CONSTRAINT "region_role_role_id_fkey" FOREIGN KEY (role_id) REFERENCES statbus_role(id) ON DELETE CASCADE
    TABLE "statbus_user" CONSTRAINT "statbus_user_role_id_fkey" FOREIGN KEY (role_id) REFERENCES statbus_role(id) ON DELETE CASCADE
Policies:
    POLICY "statbus_role_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statbus_role_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "statbus_role_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_statbus_role_id_update BEFORE UPDATE OF id ON statbus_role FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
