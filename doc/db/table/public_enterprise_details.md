```sql
                                                               Table "public.enterprise"
     Column      |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-----------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id              | integer                  |           | not null | generated always as identity | plain    |             |              | 
 active          | boolean                  |           | not null | true                         | plain    |             |              | 
 short_name      | character varying(16)    |           |          |                              | extended |             |              | 
 edit_comment    | character varying(512)   |           |          |                              | extended |             |              | 
 edit_by_user_id | integer                  |           | not null |                              | plain    |             |              | 
 edit_at         | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "enterprise_pkey" PRIMARY KEY, btree (id)
    "ix_enterprise_active" btree (active)
    "ix_enterprise_edit_by_user_id" btree (edit_by_user_id)
Foreign-key constraints:
    "enterprise_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
Referenced by:
    TABLE "establishment" CONSTRAINT "establishment_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    TABLE "external_ident" CONSTRAINT "external_ident_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    TABLE "legal_unit" CONSTRAINT "legal_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    TABLE "tag_for_unit" CONSTRAINT "tag_for_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    TABLE "unit_notes" CONSTRAINT "unit_notes_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
Policies:
    POLICY "enterprise_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "enterprise_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    enterprise_changes_trigger AFTER INSERT OR UPDATE ON enterprise FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    enterprise_deletes_trigger BEFORE DELETE ON enterprise FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    trigger_prevent_enterprise_id_update BEFORE UPDATE OF id ON enterprise FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
