```sql
                                                 Table "public.stat_for_unit"
       Column       |       Type        | Collation | Nullable |                            Default                            
--------------------+-------------------+-----------+----------+---------------------------------------------------------------
 id                 | integer           |           | not null | nextval('stat_for_unit_id_seq'::regclass)
 stat_definition_id | integer           |           | not null | 
 valid_after        | date              |           | not null | generated always as ((valid_from - '1 day'::interval)) stored
 valid_from         | date              |           | not null | CURRENT_DATE
 valid_to           | date              |           | not null | 'infinity'::date
 data_source_id     | integer           |           |          | 
 establishment_id   | integer           |           |          | 
 legal_unit_id      | integer           |           |          | 
 value_int          | integer           |           |          | 
 value_float        | double precision  |           |          | 
 value_string       | character varying |           |          | 
 value_bool         | boolean           |           |          | 
Indexes:
    "stat_for_unit_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "stat_for_unit_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "stat_for_unit_stat_definition_id_establishment_id_daterang_excl" EXCLUDE USING gist (stat_definition_id WITH =, establishment_id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "stat_for_unit_stat_definition_id_establishment_id_valid_aft_key" UNIQUE CONSTRAINT, btree (stat_definition_id, establishment_id, valid_after, valid_to) DEFERRABLE
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "stat_for_unit_check" CHECK (value_int IS NOT NULL AND value_float IS NULL AND value_string IS NULL AND value_bool IS NULL OR value_int IS NULL AND value_float IS NOT NULL AND value_string IS NULL AND value_bool IS NULL OR value_int IS NULL AND value_float IS NULL AND value_string IS NOT NULL AND value_bool IS NULL OR value_int IS NULL AND value_float IS NULL AND value_string IS NULL AND value_bool IS NOT NULL)
    "stat_for_unit_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "stat_for_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    "stat_for_unit_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE RESTRICT
Policies:
    POLICY "stat_for_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "stat_for_unit_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "stat_for_unit_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    check_stat_for_unit_values_trigger BEFORE INSERT OR UPDATE ON stat_for_unit FOR EACH ROW EXECUTE FUNCTION admin.check_stat_for_unit_values()
    stat_for_unit_establishment_id_valid_fk_insert AFTER INSERT ON stat_for_unit FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('stat_for_unit_establishment_id_valid')
    stat_for_unit_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON stat_for_unit FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('stat_for_unit_establishment_id_valid')
    trigger_prevent_stat_for_unit_id_update BEFORE UPDATE OF id ON stat_for_unit FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
