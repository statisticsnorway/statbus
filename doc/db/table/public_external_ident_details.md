```sql
                                                                      Table "public.external_ident"
       Column        |           Type           | Collation | Nullable |                  Default                   | Storage  | Compression | Stats target | Description 
---------------------+--------------------------+-----------+----------+--------------------------------------------+----------+-------------+--------------+-------------
 id                  | integer                  |           | not null | nextval('external_ident_id_seq'::regclass) | plain    |             |              | 
 ident               | character varying(50)    |           | not null |                                            | extended |             |              | 
 type_id             | integer                  |           | not null |                                            | plain    |             |              | 
 establishment_id    | integer                  |           |          |                                            | plain    |             |              | 
 legal_unit_id       | integer                  |           |          |                                            | plain    |             |              | 
 enterprise_id       | integer                  |           |          |                                            | plain    |             |              | 
 enterprise_group_id | integer                  |           |          |                                            | plain    |             |              | 
 edit_comment        | character varying(512)   |           |          |                                            | extended |             |              | 
 edit_by_user_id     | integer                  |           | not null |                                            | plain    |             |              | 
 edit_at             | timestamp with time zone |           | not null | statement_timestamp()                      | plain    |             |              | 
Indexes:
    "external_ident_enterprise_group_id_idx" btree (enterprise_group_id)
    "external_ident_enterprise_id_idx" btree (enterprise_id)
    "external_ident_establishment_id_idx" btree (establishment_id)
    "external_ident_legal_unit_id_idx" btree (legal_unit_id)
    "external_ident_type_for_enterprise" UNIQUE, btree (type_id, enterprise_id) WHERE enterprise_id IS NOT NULL
    "external_ident_type_for_enterprise_group" UNIQUE, btree (type_id, enterprise_group_id) WHERE enterprise_group_id IS NOT NULL
    "external_ident_type_for_establishment" UNIQUE, btree (type_id, establishment_id) WHERE establishment_id IS NOT NULL
    "external_ident_type_for_ident" UNIQUE, btree (type_id, ident)
    "external_ident_type_for_legal_unit" UNIQUE, btree (type_id, legal_unit_id) WHERE legal_unit_id IS NOT NULL
    "ix_external_ident_edit_by_user_id" btree (edit_by_user_id)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NOT NULL)
    "external_ident_enterprise_group_id_check" CHECK (admin.enterprise_group_id_exists(enterprise_group_id))
    "external_ident_establishment_id_check" CHECK (admin.establishment_id_exists(establishment_id))
    "external_ident_legal_unit_id_check" CHECK (admin.legal_unit_id_exists(legal_unit_id))
Foreign-key constraints:
    "external_ident_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "external_ident_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    "external_ident_type_id_fkey" FOREIGN KEY (type_id) REFERENCES external_ident_type(id) ON DELETE RESTRICT
Policies:
    POLICY "external_ident_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "external_ident_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "external_ident_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    external_ident_changes_trigger AFTER INSERT OR UPDATE ON external_ident FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    external_ident_deletes_trigger BEFORE DELETE ON external_ident FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    trigger_prevent_external_ident_id_update BEFORE UPDATE OF id ON external_ident FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
