```sql
                                                       Table "public.activity"
       Column       |           Type           | Collation | Nullable |                            Default                            
--------------------+--------------------------+-----------+----------+---------------------------------------------------------------
 id                 | integer                  |           | not null | nextval('activity_id_seq'::regclass)
 valid_after        | date                     |           | not null | generated always as ((valid_from - '1 day'::interval)) stored
 valid_from         | date                     |           | not null | CURRENT_DATE
 valid_to           | date                     |           | not null | 'infinity'::date
 type               | activity_type            |           | not null | 
 category_id        | integer                  |           | not null | 
 data_source_id     | integer                  |           |          | 
 updated_by_user_id | integer                  |           | not null | 
 updated_at         | timestamp with time zone |           | not null | statement_timestamp()
 establishment_id   | integer                  |           |          | 
 legal_unit_id      | integer                  |           |          | 
Indexes:
    "activity_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "activity_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "activity_type_category_id_establishment_id_daterange_excl" EXCLUDE USING gist (type WITH =, category_id WITH =, establishment_id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "activity_type_category_id_establishment_id_valid_after_vali_key" UNIQUE CONSTRAINT, btree (type, category_id, establishment_id, valid_after, valid_to) DEFERRABLE
    "activity_type_category_id_legal_unit_id_daterange_excl" EXCLUDE USING gist (type WITH =, category_id WITH =, legal_unit_id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "activity_type_category_id_legal_unit_id_valid_after_valid_t_key" UNIQUE CONSTRAINT, btree (type, category_id, legal_unit_id, valid_after, valid_to) DEFERRABLE
    "ix_activity_category_id" btree (category_id)
    "ix_activity_establishment_id" btree (establishment_id)
    "ix_activity_establishment_valid_after_valid_to" btree (establishment_id, valid_after, valid_to)
    "ix_activity_legal_unit_id" btree (legal_unit_id)
    "ix_activity_updated_by_user_id" btree (updated_by_user_id)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "activity_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "activity_category_id_fkey" FOREIGN KEY (category_id) REFERENCES activity_category(id) ON DELETE CASCADE
    "activity_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    "activity_updated_by_user_id_fkey" FOREIGN KEY (updated_by_user_id) REFERENCES statbus_user(id) ON DELETE CASCADE
Policies:
    POLICY "activity_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_employee_manage"
      TO authenticated
      USING ((auth.has_statbus_role(auth.uid(), 'restricted_user'::statbus_role_type) AND auth.has_activity_category_access(auth.uid(), category_id)))
      WITH CHECK ((auth.has_statbus_role(auth.uid(), 'restricted_user'::statbus_role_type) AND auth.has_activity_category_access(auth.uid(), category_id)))
    POLICY "activity_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "activity_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    activity_establishment_id_valid_fk_insert AFTER INSERT ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('activity_establishment_id_valid')
    activity_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('activity_establishment_id_valid')
    activity_legal_unit_id_valid_fk_insert AFTER INSERT ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('activity_legal_unit_id_valid')
    activity_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('activity_legal_unit_id_valid')
    trigger_prevent_activity_id_update BEFORE UPDATE OF id ON activity FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
