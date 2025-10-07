```sql
                                                                     Table "public.activity"
      Column      |           Type           | Collation | Nullable |               Default                | Storage  | Compression | Stats target | Description 
------------------+--------------------------+-----------+----------+--------------------------------------+----------+-------------+--------------+-------------
 id               | integer                  |           | not null | nextval('activity_id_seq'::regclass) | plain    |             |              | 
 valid_from       | date                     |           | not null |                                      | plain    |             |              | 
 valid_to         | date                     |           |          |                                      | plain    |             |              | 
 valid_until      | date                     |           |          |                                      | plain    |             |              | 
 type             | activity_type            |           | not null |                                      | plain    |             |              | 
 category_id      | integer                  |           | not null |                                      | plain    |             |              | 
 data_source_id   | integer                  |           |          |                                      | plain    |             |              | 
 edit_comment     | character varying(512)   |           |          |                                      | extended |             |              | 
 edit_by_user_id  | integer                  |           | not null |                                      | plain    |             |              | 
 edit_at          | timestamp with time zone |           | not null | statement_timestamp()                | plain    |             |              | 
 establishment_id | integer                  |           |          |                                      | plain    |             |              | 
 legal_unit_id    | integer                  |           |          |                                      | plain    |             |              | 
Indexes:
    "activity_pkey" PRIMARY KEY, btree (id, valid_from) DEFERRABLE
    "activity_establishment_id_type_idx" btree (establishment_id, type) WHERE legal_unit_id IS NULL
    "activity_id_idx" btree (id)
    "activity_id_valid_excl" EXCLUDE USING gist (id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "activity_legal_unit_id_establishment_id_type_idx" btree (legal_unit_id, establishment_id, type)
    "activity_legal_unit_id_type_idx" btree (legal_unit_id, type) WHERE establishment_id IS NULL
    "activity_type_establishm_establishment_id_pk_consistency_excl" EXCLUDE USING gist (type WITH =, establishment_id WITH =, id WITH <>) WHERE (establishment_id IS NOT NULL AND legal_unit_id IS NULL)
    "activity_type_establishment_id_valid_establishment_id_excl" EXCLUDE USING gist (type WITH =, establishment_id WITH =, daterange(valid_from, valid_until) WITH &&) WHERE (establishment_id IS NOT NULL AND legal_unit_id IS NULL) DEFERRABLE
    "activity_type_establishment_id_valid_establishment_id_idx" btree (type, establishment_id) WHERE establishment_id IS NOT NULL AND legal_unit_id IS NULL
    "activity_type_establishment_id_valid_legal_unit_id_excl" EXCLUDE USING gist (type WITH =, legal_unit_id WITH =, daterange(valid_from, valid_until) WITH &&) WHERE (legal_unit_id IS NOT NULL AND establishment_id IS NULL) DEFERRABLE
    "activity_type_establishment_id_valid_legal_unit_id_idx" btree (type, legal_unit_id) WHERE legal_unit_id IS NOT NULL AND establishment_id IS NULL
    "activity_type_establishment_legal_unit_id_pk_consistency_excl" EXCLUDE USING gist (type WITH =, legal_unit_id WITH =, id WITH <>) WHERE (legal_unit_id IS NOT NULL AND establishment_id IS NULL)
    "activity_type_legal_unit_id_establishment_id_idx" btree (type, legal_unit_id, establishment_id)
    "ix_activity_category_id" btree (category_id)
    "ix_activity_data_source_id" btree (data_source_id)
    "ix_activity_edit_by_user_id" btree (edit_by_user_id)
    "ix_activity_establishment_id" btree (establishment_id)
    "ix_activity_establishment_id_valid_range" gist (establishment_id, daterange(valid_from, valid_until, '[)'::text))
    "ix_activity_establishment_valid_from_valid_until" btree (establishment_id, valid_from, valid_until)
    "ix_activity_legal_unit_id" btree (legal_unit_id)
    "ix_activity_legal_unit_id_valid_range" gist (legal_unit_id, daterange(valid_from, valid_until, '[)'::text))
    "ix_activity_type" btree (type)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "activity_type_establishment_id_valid_xor_check" CHECK ((
CASE
    WHEN legal_unit_id IS NOT NULL THEN 1
    ELSE 0
END +
CASE
    WHEN establishment_id IS NOT NULL THEN 1
    ELSE 0
END) = 1)
    "activity_valid_check" CHECK (valid_from < valid_until AND valid_from > '-infinity'::date)
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
    activity_establishment_id_valid_fk_insert AFTER INSERT ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('activity_establishment_id_valid', 'public', 'activity', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    activity_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_from, valid_until, valid_to ON activity FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('activity_establishment_id_valid', 'public', 'activity', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    activity_legal_unit_id_valid_fk_insert AFTER INSERT ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('activity_legal_unit_id_valid', 'public', 'activity', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    activity_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_from, valid_until, valid_to ON activity FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('activity_legal_unit_id_valid', 'public', 'activity', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    activity_synchronize_temporal_columns_trigger BEFORE INSERT OR UPDATE OF valid_from, valid_until, valid_to ON activity FOR EACH ROW EXECUTE FUNCTION sql_saga.synchronize_temporal_columns('valid_from', 'valid_until', 'valid_to', 'null', 'date', 't')
    trigger_prevent_activity_id_update BEFORE UPDATE OF id ON activity FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
