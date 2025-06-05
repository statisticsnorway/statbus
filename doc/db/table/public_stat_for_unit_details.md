```sql
                                                                      Table "public.stat_for_unit"
       Column       |           Type           | Collation | Nullable |                  Default                  | Storage  | Compression | Stats target | Description 
--------------------+--------------------------+-----------+----------+-------------------------------------------+----------+-------------+--------------+-------------
 id                 | integer                  |           | not null | nextval('stat_for_unit_id_seq'::regclass) | plain    |             |              | 
 stat_definition_id | integer                  |           | not null |                                           | plain    |             |              | 
 valid_from         | date                     |           | not null |                                           | plain    |             |              | 
 valid_after        | date                     |           | not null |                                           | plain    |             |              | 
 valid_to           | date                     |           | not null | 'infinity'::date                          | plain    |             |              | 
 data_source_id     | integer                  |           |          |                                           | plain    |             |              | 
 establishment_id   | integer                  |           |          |                                           | plain    |             |              | 
 legal_unit_id      | integer                  |           |          |                                           | plain    |             |              | 
 value_int          | integer                  |           |          |                                           | plain    |             |              | 
 value_float        | double precision         |           |          |                                           | plain    |             |              | 
 value_string       | character varying        |           |          |                                           | extended |             |              | 
 value_bool         | boolean                  |           |          |                                           | plain    |             |              | 
 created_at         | timestamp with time zone |           | not null | statement_timestamp()                     | plain    |             |              | 
 edit_comment       | character varying(512)   |           |          |                                           | extended |             |              | 
 edit_by_user_id    | integer                  |           | not null |                                           | plain    |             |              | 
 edit_at            | timestamp with time zone |           | not null | statement_timestamp()                     | plain    |             |              | 
Indexes:
    "ix_stat_for_unit_data_source_id" btree (data_source_id)
    "ix_stat_for_unit_establishment_id" btree (establishment_id)
    "ix_stat_for_unit_legal_unit_id" btree (legal_unit_id)
    "ix_stat_for_unit_stat_definition_id" btree (stat_definition_id)
    "stat_for_unit_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "stat_for_unit_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "stat_for_unit_stat_definition_id_establishment_id_daterang_excl" EXCLUDE USING gist (stat_definition_id WITH =, establishment_id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "stat_for_unit_stat_definition_id_establishment_id_valid_aft_key" UNIQUE CONSTRAINT, btree (stat_definition_id, establishment_id, valid_after, valid_to) DEFERRABLE
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "stat_for_unit_check" CHECK (value_int IS NOT NULL AND value_float IS NULL AND value_string IS NULL AND value_bool IS NULL OR value_int IS NULL AND value_float IS NOT NULL AND value_string IS NULL AND value_bool IS NULL OR value_int IS NULL AND value_float IS NULL AND value_string IS NOT NULL AND value_bool IS NULL OR value_int IS NULL AND value_float IS NULL AND value_string IS NULL AND value_bool IS NOT NULL)
    "stat_for_unit_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "stat_for_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    "stat_for_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "stat_for_unit_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE RESTRICT
Policies:
    POLICY "stat_for_unit_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "stat_for_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "stat_for_unit_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    check_stat_for_unit_values_trigger BEFORE INSERT OR UPDATE ON stat_for_unit FOR EACH ROW EXECUTE FUNCTION admin.check_stat_for_unit_values()
    stat_for_unit_changes_trigger AFTER INSERT OR UPDATE ON stat_for_unit FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    stat_for_unit_deletes_trigger BEFORE DELETE ON stat_for_unit FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    stat_for_unit_establishment_id_valid_fk_insert AFTER INSERT ON stat_for_unit FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('stat_for_unit_establishment_id_valid')
    stat_for_unit_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON stat_for_unit FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('stat_for_unit_establishment_id_valid')
    stat_for_unit_legal_unit_id_valid_fk_insert AFTER INSERT ON stat_for_unit FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('stat_for_unit_legal_unit_id_valid')
    stat_for_unit_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON stat_for_unit FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('stat_for_unit_legal_unit_id_valid')
    trg_stat_for_unit_synchronize_valid_from_after BEFORE INSERT OR UPDATE ON stat_for_unit FOR EACH ROW EXECUTE FUNCTION synchronize_valid_from_after()
    trigger_prevent_stat_for_unit_id_update BEFORE UPDATE OF id ON stat_for_unit FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
