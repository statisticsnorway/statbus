```sql
                          Table "public.person_for_unit"
      Column      |  Type   | Collation | Nullable |           Default            
------------------+---------+-----------+----------+------------------------------
 id               | integer |           | not null | generated always as identity
 person_id        | integer |           | not null | 
 person_type_id   | integer |           |          | 
 establishment_id | integer |           |          | 
 legal_unit_id    | integer |           |          | 
Indexes:
    "person_for_unit_pkey" PRIMARY KEY, btree (id)
    "ix_person_for_unit_establishment_id" btree (establishment_id)
    "ix_person_for_unit_legal_unit_id" btree (legal_unit_id)
    "ix_person_for_unit_person_id" btree (person_id)
    "ix_person_for_unit_person_type_id_establishment_id_legal_unit_i" UNIQUE, btree (person_type_id, establishment_id, legal_unit_id, person_id)
Check constraints:
    "One and only one of establishment_id legal_unit_id  must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "person_for_unit_establishment_id_check" CHECK (admin.establishment_id_exists(establishment_id))
    "person_for_unit_legal_unit_id_check" CHECK (admin.legal_unit_id_exists(legal_unit_id))
Foreign-key constraints:
    "person_for_unit_person_id_fkey" FOREIGN KEY (person_id) REFERENCES person(id) ON DELETE CASCADE
    "person_for_unit_person_type_id_fkey" FOREIGN KEY (person_type_id) REFERENCES person_role(id)
Policies:
    POLICY "person_for_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "person_for_unit_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "person_for_unit_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_person_for_unit_id_update BEFORE UPDATE OF id ON person_for_unit FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
