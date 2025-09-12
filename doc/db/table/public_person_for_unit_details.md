```sql
                                                            Table "public.person_for_unit"
      Column      |  Type   | Collation | Nullable |                   Default                   | Storage | Compression | Stats target | Description 
------------------+---------+-----------+----------+---------------------------------------------+---------+-------------+--------------+-------------
 id               | integer |           | not null | nextval('person_for_unit_id_seq'::regclass) | plain   |             |              | 
 valid_from       | date    |           | not null |                                             | plain   |             |              | 
 valid_to         | date    |           | not null |                                             | plain   |             |              | 
 valid_until      | date    |           | not null |                                             | plain   |             |              | 
 person_id        | integer |           | not null |                                             | plain   |             |              | 
 person_role_id   | integer |           |          |                                             | plain   |             |              | 
 data_source_id   | integer |           |          |                                             | plain   |             |              | 
 establishment_id | integer |           |          |                                             | plain   |             |              | 
 legal_unit_id    | integer |           |          |                                             | plain   |             |              | 
Indexes:
    "person_for_unit_pkey" PRIMARY KEY, btree (id, valid_from, valid_until) DEFERRABLE
    "ix_person_for_unit_data_source_id" btree (data_source_id)
    "ix_person_for_unit_establishment_id" btree (establishment_id)
    "ix_person_for_unit_legal_unit_id" btree (legal_unit_id)
    "ix_person_for_unit_person_id" btree (person_id)
    "ix_person_for_unit_person_role_id" btree (person_role_id)
    "person_for_unit_id_idx" btree (id)
    "person_for_unit_id_valid_excl" EXCLUDE USING gist (id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "person_for_unit_person_id_person_role_id_establishment_id_idx" btree (person_id, person_role_id, establishment_id)
    "person_for_unit_person_id_person_role_id_legal_unit_id_idx" btree (person_id, person_role_id, legal_unit_id)
    "person_for_unit_person_role_establishment_valid_excl" EXCLUDE USING gist (person_id WITH =, person_role_id WITH =, establishment_id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "person_for_unit_person_role_establishment_valid_uniq" UNIQUE CONSTRAINT, btree (person_id, person_role_id, establishment_id, valid_from, valid_until) DEFERRABLE
    "person_for_unit_person_role_legal_unit_valid_excl" EXCLUDE USING gist (person_id WITH =, person_role_id WITH =, legal_unit_id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "person_for_unit_person_role_legal_unit_valid_uniq" UNIQUE CONSTRAINT, btree (person_id, person_role_id, legal_unit_id, valid_from, valid_until) DEFERRABLE
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "person_for_unit_valid_check" CHECK (valid_from < valid_until AND valid_from > '-infinity'::date)
Foreign-key constraints:
    "person_for_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    "person_for_unit_person_id_fkey" FOREIGN KEY (person_id) REFERENCES person(id) ON DELETE RESTRICT
    "person_for_unit_person_role_id_fkey" FOREIGN KEY (person_role_id) REFERENCES person_role(id)
Policies:
    POLICY "person_for_unit_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "person_for_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "person_for_unit_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    person_for_unit_establishment_id_valid_fk_insert AFTER INSERT ON person_for_unit FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('person_for_unit_establishment_id_valid', 'public', 'person_for_unit', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    person_for_unit_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_from, valid_until, valid_to ON person_for_unit FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('person_for_unit_establishment_id_valid', 'public', 'person_for_unit', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    person_for_unit_legal_unit_id_valid_fk_insert AFTER INSERT ON person_for_unit FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('person_for_unit_legal_unit_id_valid', 'public', 'person_for_unit', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    person_for_unit_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_from, valid_until, valid_to ON person_for_unit FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('person_for_unit_legal_unit_id_valid', 'public', 'person_for_unit', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    person_for_unit_synchronize_temporal_columns_trigger BEFORE INSERT OR UPDATE OF valid_from, valid_until, valid_to ON person_for_unit FOR EACH ROW EXECUTE FUNCTION sql_saga.synchronize_temporal_columns('valid_from', 'valid_until', 'valid_to', 'null', 'date', 't')
    trigger_prevent_person_for_unit_id_update BEFORE UPDATE OF id ON person_for_unit FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
