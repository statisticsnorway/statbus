```sql
                                    Table "public.enterprise"
     Column      |           Type           | Collation | Nullable |           Default            
-----------------+--------------------------+-----------+----------+------------------------------
 id              | integer                  |           | not null | generated always as identity
 active          | boolean                  |           | not null | true
 short_name      | character varying(16)    |           |          | 
 edit_comment    | character varying(512)   |           |          | 
 edit_by_user_id | integer                  |           | not null | 
 edit_at         | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "enterprise_pkey" PRIMARY KEY, btree (id)
    "ix_enterprise_edit_by_user_id" btree (edit_by_user_id)
Foreign-key constraints:
    "enterprise_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
Referenced by:
    TABLE "establishment" CONSTRAINT "establishment_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    TABLE "external_ident" CONSTRAINT "external_ident_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    TABLE "legal_unit" CONSTRAINT "legal_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    TABLE "tag_for_unit" CONSTRAINT "tag_for_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    TABLE "unit_notes" CONSTRAINT "unit_notes_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
Policies:
    POLICY "enterprise_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "enterprise_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    enterprise_changes_trigger AFTER INSERT OR UPDATE ON enterprise FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    enterprise_deletes_trigger BEFORE DELETE ON enterprise FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    trigger_prevent_enterprise_id_update BEFORE UPDATE OF id ON enterprise FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
