```sql
                                          Table "public.activity"
      Column      |           Type           | Collation | Nullable |               Default                
------------------+--------------------------+-----------+----------+--------------------------------------
 id               | integer                  |           | not null | nextval('activity_id_seq'::regclass)
 valid_from       | date                     |           | not null | 
 valid_after      | date                     |           | not null | 
 valid_to         | date                     |           | not null | 'infinity'::date
 type             | activity_type            |           | not null | 
 category_id      | integer                  |           | not null | 
 data_source_id   | integer                  |           |          | 
 edit_comment     | character varying(512)   |           |          | 
 edit_by_user_id  | integer                  |           | not null | 
 edit_at          | timestamp with time zone |           | not null | statement_timestamp()
 establishment_id | integer                  |           |          | 
 legal_unit_id    | integer                  |           |          | 
Indexes:
    "activity_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "activity_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "activity_type_establishment_id_daterange_excl" EXCLUDE USING gist (type WITH =, establishment_id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "activity_type_establishment_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (type, establishment_id, valid_after, valid_to) DEFERRABLE
    "activity_type_legal_unit_id_daterange_excl" EXCLUDE USING gist (type WITH =, legal_unit_id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "activity_type_legal_unit_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (type, legal_unit_id, valid_after, valid_to) DEFERRABLE
    "ix_activity_category_id" btree (category_id)
    "ix_activity_data_source_id" btree (data_source_id)
    "ix_activity_edit_by_user_id" btree (edit_by_user_id)
    "ix_activity_establishment_id" btree (establishment_id)
    "ix_activity_establishment_valid_after_valid_to" btree (establishment_id, valid_after, valid_to)
    "ix_activity_legal_unit_id" btree (legal_unit_id)
    "ix_activity_legal_unit_id_valid_range" gist (legal_unit_id, daterange(valid_after, valid_to, '(]'::text))
    "ix_activity_type" btree (type)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "activity_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "activity_category_id_fkey" FOREIGN KEY (category_id) REFERENCES activity_category(id) ON DELETE CASCADE
    "activity_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    "activity_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
Policies:
    POLICY "activity_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "activity_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
    POLICY "admin_user_activity_access"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "regular_user_activity_access"
      TO regular_user
      USING (true)
      WITH CHECK (true)
    POLICY "restricted_user_activity_access"
      TO restricted_user
      USING ((EXISTS ( SELECT 1
   FROM activity_category_access aca
  WHERE ((aca.user_id = auth.uid()) AND (aca.activity_category_id = activity.category_id)))))
      WITH CHECK ((EXISTS ( SELECT 1
   FROM activity_category_access aca
  WHERE ((aca.user_id = auth.uid()) AND (aca.activity_category_id = activity.category_id)))))
Triggers:
    activity_changes_trigger AFTER INSERT OR UPDATE ON activity FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    activity_deletes_trigger BEFORE DELETE ON activity FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    activity_establishment_id_valid_fk_insert AFTER INSERT ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('activity_establishment_id_valid', 'public.activity', 'public', 'activity', '{{establishment_id}}', 'valid', 'valid_after', 'valid_to', 'public', 'establishment', '{{id}}', 'valid', 'valid_after', 'valid_to', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    activity_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('activity_establishment_id_valid', 'public.activity', 'public', 'activity', '{{establishment_id}}', 'valid', 'valid_after', 'valid_to', 'public', 'establishment', '{{id}}', 'valid', 'valid_after', 'valid_to', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    activity_legal_unit_id_valid_fk_insert AFTER INSERT ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('activity_legal_unit_id_valid', 'public.activity', 'public', 'activity', '{{legal_unit_id}}', 'valid', 'valid_after', 'valid_to', 'public', 'legal_unit', '{{id}}', 'valid', 'valid_after', 'valid_to', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    activity_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('activity_legal_unit_id_valid', 'public.activity', 'public', 'activity', '{{legal_unit_id}}', 'valid', 'valid_after', 'valid_to', 'public', 'legal_unit', '{{id}}', 'valid', 'valid_after', 'valid_to', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    trg_activity_synchronize_valid_from_after BEFORE INSERT OR UPDATE ON activity FOR EACH ROW EXECUTE FUNCTION synchronize_valid_from_after()
    trigger_prevent_activity_id_update BEFORE UPDATE OF id ON activity FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
