```sql
                             Table "public.statbus_user"
 Column  |  Type   | Collation | Nullable |                 Default                  
---------+---------+-----------+----------+------------------------------------------
 id      | integer |           | not null | nextval('statbus_user_id_seq'::regclass)
 uuid    | uuid    |           | not null | 
 role_id | integer |           | not null | 
Indexes:
    "statbus_user_pkey" PRIMARY KEY, btree (id)
    "statbus_user_uuid_key" UNIQUE CONSTRAINT, btree (uuid)
Foreign-key constraints:
    "statbus_user_role_id_fkey" FOREIGN KEY (role_id) REFERENCES statbus_role(id) ON DELETE CASCADE
    "statbus_user_uuid_fkey" FOREIGN KEY (uuid) REFERENCES auth.users(id) ON DELETE CASCADE
Referenced by:
    TABLE "activity" CONSTRAINT "activity_updated_by_user_id_fkey" FOREIGN KEY (updated_by_user_id) REFERENCES statbus_user(id) ON DELETE CASCADE
    TABLE "external_ident" CONSTRAINT "external_ident_updated_by_user_id_fkey" FOREIGN KEY (updated_by_user_id) REFERENCES statbus_user(id) ON DELETE CASCADE
    TABLE "location" CONSTRAINT "location_updated_by_user_id_fkey" FOREIGN KEY (updated_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "tag_for_unit" CONSTRAINT "tag_for_unit_updated_by_user_id_fkey" FOREIGN KEY (updated_by_user_id) REFERENCES statbus_user(id) ON DELETE CASCADE
Policies:
    POLICY "statbus_user_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statbus_user_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "statbus_user_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_statbus_user_id_update BEFORE UPDATE OF id ON statbus_user FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
