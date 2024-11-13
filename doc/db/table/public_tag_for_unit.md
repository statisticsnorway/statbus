```sql
                             Table "public.tag_for_unit"
       Column        |  Type   | Collation | Nullable |           Default            
---------------------+---------+-----------+----------+------------------------------
 id                  | integer |           | not null | generated always as identity
 tag_id              | integer |           | not null | 
 establishment_id    | integer |           |          | 
 legal_unit_id       | integer |           |          | 
 enterprise_id       | integer |           |          | 
 enterprise_group_id | integer |           |          | 
 updated_by_user_id  | integer |           | not null | 
Indexes:
    "tag_for_unit_pkey" PRIMARY KEY, btree (id)
    "ix_tag_for_unit_enterprise_group_id_id" btree (enterprise_group_id)
    "ix_tag_for_unit_enterprise_id_id" btree (enterprise_id)
    "ix_tag_for_unit_establishment_id_id" btree (establishment_id)
    "ix_tag_for_unit_legal_unit_id_id" btree (legal_unit_id)
    "ix_tag_for_unit_tag_id" btree (tag_id)
    "ix_tag_for_unit_updated_by_user_id" btree (updated_by_user_id)
    "tag_for_unit_tag_id_enterprise_group_id_key" UNIQUE CONSTRAINT, btree (tag_id, enterprise_group_id)
    "tag_for_unit_tag_id_enterprise_id_key" UNIQUE CONSTRAINT, btree (tag_id, enterprise_id)
    "tag_for_unit_tag_id_establishment_id_key" UNIQUE CONSTRAINT, btree (tag_id, establishment_id)
    "tag_for_unit_tag_id_legal_unit_id_key" UNIQUE CONSTRAINT, btree (tag_id, legal_unit_id)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NOT NULL)
    "tag_for_unit_enterprise_group_id_check" CHECK (admin.enterprise_group_id_exists(enterprise_group_id))
    "tag_for_unit_establishment_id_check" CHECK (admin.establishment_id_exists(establishment_id))
    "tag_for_unit_legal_unit_id_check" CHECK (admin.legal_unit_id_exists(legal_unit_id))
Foreign-key constraints:
    "tag_for_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    "tag_for_unit_tag_id_fkey" FOREIGN KEY (tag_id) REFERENCES tag(id) ON DELETE CASCADE
    "tag_for_unit_updated_by_user_id_fkey" FOREIGN KEY (updated_by_user_id) REFERENCES statbus_user(id) ON DELETE CASCADE
Policies:
    POLICY "tag_for_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "tag_for_unit_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "tag_for_unit_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_tag_for_unit_id_update BEFORE UPDATE OF id ON tag_for_unit FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
