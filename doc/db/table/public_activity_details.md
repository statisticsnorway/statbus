```sql
                                                                     Table "public.activity"
      Column      |           Type           | Collation | Nullable |               Default                | Storage  | Compression | Stats target | Description 
------------------+--------------------------+-----------+----------+--------------------------------------+----------+-------------+--------------+-------------
 id               | integer                  |           | not null | nextval('activity_id_seq'::regclass) | plain    |             |              | 
 valid_from       | date                     |           | not null |                                      | plain    |             |              | 
 valid_after      | date                     |           | not null |                                      | plain    |             |              | 
 valid_to         | date                     |           | not null | 'infinity'::date                     | plain    |             |              | 
 type             | activity_type            |           | not null |                                      | plain    |             |              | 
 category_id      | integer                  |           | not null |                                      | plain    |             |              | 
 data_source_id   | integer                  |           |          |                                      | plain    |             |              | 
 edit_comment     | character varying(512)   |           |          |                                      | extended |             |              | 
 edit_by_user_id  | integer                  |           | not null |                                      | plain    |             |              | 
 edit_at          | timestamp with time zone |           | not null | statement_timestamp()                | plain    |             |              | 
 establishment_id | integer                  |           |          |                                      | plain    |             |              | 
 legal_unit_id    | integer                  |           |          |                                      | plain    |             |              | 
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
    activity_establishment_id_valid_fk_insert AFTER INSERT ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('activity_establishment_id_valid')
    activity_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('activity_establishment_id_valid')
    activity_legal_unit_id_valid_fk_insert AFTER INSERT ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('activity_legal_unit_id_valid')
    activity_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('activity_legal_unit_id_valid')
    trg_activity_synchronize_valid_from_after BEFORE INSERT OR UPDATE ON activity FOR EACH ROW EXECUTE FUNCTION synchronize_valid_from_after()
    trigger_prevent_activity_id_update BEFORE UPDATE OF id ON activity FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
