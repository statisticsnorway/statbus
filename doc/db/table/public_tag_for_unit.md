```sql
                                     Table "public.tag_for_unit"
       Column        |           Type           | Collation | Nullable |           Default            
---------------------+--------------------------+-----------+----------+------------------------------
 id                  | integer                  |           | not null | generated always as identity
 tag_id              | integer                  |           | not null | 
 establishment_id    | integer                  |           |          | 
 legal_unit_id       | integer                  |           |          | 
 enterprise_id       | integer                  |           |          | 
 enterprise_group_id | integer                  |           |          | 
 created_at          | timestamp with time zone |           | not null | statement_timestamp()
 edit_comment        | character varying(512)   |           |          | 
 edit_by_user_id     | integer                  |           | not null | 
 edit_at             | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "tag_for_unit_pkey" PRIMARY KEY, btree (id)
    "ix_tag_for_unit_edit_by_user_id" btree (edit_by_user_id)
    "ix_tag_for_unit_enterprise_group_id_id" btree (enterprise_group_id)
    "ix_tag_for_unit_enterprise_id_id" btree (enterprise_id)
    "ix_tag_for_unit_establishment_id_id" btree (establishment_id)
    "ix_tag_for_unit_legal_unit_id_id" btree (legal_unit_id)
    "ix_tag_for_unit_tag_id" btree (tag_id)
    "tag_for_unit_tag_unit_consolidated_key" UNIQUE, btree (tag_id, establishment_id, legal_unit_id, enterprise_id, enterprise_group_id) NULLS NOT DISTINCT
Check constraints:
    "One and only one statistical unit id must be set" CHECK (num_nonnulls(establishment_id, legal_unit_id, enterprise_id, enterprise_group_id) = 1)
    "tag_for_unit_enterprise_group_id_check" CHECK (admin.enterprise_group_id_exists(enterprise_group_id))
    "tag_for_unit_establishment_id_check" CHECK (admin.establishment_id_exists(establishment_id))
    "tag_for_unit_legal_unit_id_check" CHECK (admin.legal_unit_id_exists(legal_unit_id))
Foreign-key constraints:
    "tag_for_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "tag_for_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    "tag_for_unit_tag_id_fkey" FOREIGN KEY (tag_id) REFERENCES tag(id) ON DELETE CASCADE
Policies:
    POLICY "tag_for_unit_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "tag_for_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "tag_for_unit_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    trigger_prevent_tag_for_unit_id_update BEFORE UPDATE OF id ON tag_for_unit FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
