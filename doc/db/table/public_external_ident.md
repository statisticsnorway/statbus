```sql
                                          Table "public.external_ident"
       Column        |         Type          | Collation | Nullable |                  Default                   
---------------------+-----------------------+-----------+----------+--------------------------------------------
 id                  | integer               |           | not null | nextval('external_ident_id_seq'::regclass)
 ident               | character varying(50) |           | not null | 
 type_id             | integer               |           | not null | 
 establishment_id    | integer               |           |          | 
 legal_unit_id       | integer               |           |          | 
 enterprise_id       | integer               |           |          | 
 enterprise_group_id | integer               |           |          | 
 updated_by_user_id  | integer               |           | not null | 
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
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL AND enterprise_id IS NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NOT NULL AND enterprise_group_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NULL AND enterprise_id IS NULL AND enterprise_group_id IS NOT NULL)
    "external_ident_enterprise_group_id_check" CHECK (admin.enterprise_group_id_exists(enterprise_group_id))
    "external_ident_establishment_id_check" CHECK (admin.establishment_id_exists(establishment_id))
    "external_ident_legal_unit_id_check" CHECK (admin.legal_unit_id_exists(legal_unit_id))
Foreign-key constraints:
    "external_ident_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE CASCADE
    "external_ident_type_id_fkey" FOREIGN KEY (type_id) REFERENCES external_ident_type(id) ON DELETE RESTRICT
    "external_ident_updated_by_user_id_fkey" FOREIGN KEY (updated_by_user_id) REFERENCES statbus_user(id) ON DELETE CASCADE
Policies:
    POLICY "external_ident_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "external_ident_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "external_ident_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_external_ident_id_update BEFORE UPDATE OF id ON external_ident FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
