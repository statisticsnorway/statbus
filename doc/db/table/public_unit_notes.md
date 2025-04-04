```sql
                                      Table "public.unit_notes"
       Column        |           Type           | Collation | Nullable |           Default            
---------------------+--------------------------+-----------+----------+------------------------------
 id                  | integer                  |           | not null | generated always as identity
 notes               | text                     |           | not null | 
 establishment_id    | integer                  |           |          | 
 legal_unit_id       | integer                  |           |          | 
 enterprise_id       | integer                  |           |          | 
 enterprise_group_id | integer                  |           |          | 
 created_at          | timestamp with time zone |           | not null | statement_timestamp()
 edit_comment        | character varying(512)   |           |          | 
 edit_by_user_id     | integer                  |           | not null | 
 edit_at             | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "unit_notes_pkey" PRIMARY KEY, btree (id)
    "ix_unit_notes_edit_by_user_id" btree (edit_by_user_id)
    "ix_unit_notes_enterprise_group_id" UNIQUE, btree (enterprise_group_id)
    "ix_unit_notes_enterprise_id" UNIQUE, btree (enterprise_id)
    "ix_unit_notes_establishment_id" UNIQUE, btree (establishment_id)
    "ix_unit_notes_legal_unit_id" UNIQUE, btree (legal_unit_id)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NOT NULL)
    "unit_notes_enterprise_group_id_check" CHECK (admin.enterprise_group_id_exists(enterprise_group_id))
    "unit_notes_establishment_id_check" CHECK (admin.establishment_id_exists(establishment_id))
    "unit_notes_legal_unit_id_check" CHECK (admin.legal_unit_id_exists(legal_unit_id))
Foreign-key constraints:
    "unit_notes_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "unit_notes_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
Policies:
    POLICY "unit_notes_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "unit_notes_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "unit_notes_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    trigger_prevent_unit_notes_id_update BEFORE UPDATE OF id ON unit_notes FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
