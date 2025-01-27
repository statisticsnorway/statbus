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
    TABLE "activity" CONSTRAINT "activity_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "contact" CONSTRAINT "contact_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "enterprise" CONSTRAINT "enterprise_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "enterprise_group" CONSTRAINT "enterprise_group_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "establishment" CONSTRAINT "establishment_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "external_ident" CONSTRAINT "external_ident_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "legal_unit" CONSTRAINT "legal_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "location" CONSTRAINT "location_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "tag_for_unit" CONSTRAINT "tag_for_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    TABLE "unit_notes" CONSTRAINT "unit_notes_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
Policies:
    POLICY "statbus_user_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statbus_user_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "statbus_user_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_statbus_user_id_update BEFORE UPDATE OF id ON statbus_user FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
