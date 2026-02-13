```sql
                                                               Table "public.enterprise"
     Column      |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-----------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id              | integer                  |           | not null | generated always as identity | plain    |             |              | 
 enabled         | boolean                  |           | not null | true                         | plain    |             |              | 
 short_name      | character varying(16)    |           |          |                              | extended |             |              | 
 edit_comment    | character varying(512)   |           |          |                              | extended |             |              | 
 edit_by_user_id | integer                  |           | not null |                              | plain    |             |              | 
 edit_at         | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
Indexes:
    "enterprise_pkey" PRIMARY KEY, btree (id)
    "ix_enterprise_edit_by_user_id" btree (edit_by_user_id)
    "ix_enterprise_enabled" btree (enabled)
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
Not-null constraints:
    "enterprise_id_not_null" NOT NULL "id"
    "enterprise_enabled_not_null" NOT NULL "enabled"
    "enterprise_edit_by_user_id_not_null" NOT NULL "edit_by_user_id"
    "enterprise_edit_at_not_null" NOT NULL "edit_at"
Triggers:
    a_enterprise_log_delete AFTER DELETE ON enterprise REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change()
    a_enterprise_log_insert AFTER INSERT ON enterprise REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change()
    a_enterprise_log_update AFTER UPDATE ON enterprise REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION worker.log_base_change()
    b_enterprise_ensure_collect AFTER INSERT OR DELETE OR UPDATE ON enterprise FOR EACH STATEMENT EXECUTE FUNCTION worker.ensure_collect_changes()
    trigger_prevent_enterprise_id_update BEFORE UPDATE OF id ON enterprise FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
