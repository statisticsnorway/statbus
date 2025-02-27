```sql
                                                         Table "public.legal_unit"
          Column          |           Type           | Collation | Nullable |                            Default                            
--------------------------+--------------------------+-----------+----------+---------------------------------------------------------------
 id                       | integer                  |           | not null | nextval('legal_unit_id_seq'::regclass)
 valid_after              | date                     |           | not null | generated always as ((valid_from - '1 day'::interval)) stored
 valid_from               | date                     |           | not null | CURRENT_DATE
 valid_to                 | date                     |           | not null | 'infinity'::date
 active                   | boolean                  |           | not null | true
 short_name               | character varying(16)    |           |          | 
 name                     | character varying(256)   |           |          | 
 birth_date               | date                     |           |          | 
 death_date               | date                     |           |          | 
 free_econ_zone           | boolean                  |           |          | 
 sector_id                | integer                  |           |          | 
 status_id                | integer                  |           |          | 
 legal_form_id            | integer                  |           |          | 
 edit_comment             | character varying(512)   |           |          | 
 edit_by_user_id          | integer                  |           | not null | 
 edit_at                  | timestamp with time zone |           | not null | statement_timestamp()
 unit_size_id             | integer                  |           |          | 
 foreign_participation_id | integer                  |           |          | 
 data_source_id           | integer                  |           |          | 
 enterprise_id            | integer                  |           | not null | 
 primary_for_enterprise   | boolean                  |           | not null | 
 invalid_codes            | jsonb                    |           |          | 
Indexes:
    "ix_legal_unit_data_source_id" btree (data_source_id)
    "ix_legal_unit_edit_by_user_id" btree (edit_by_user_id)
    "ix_legal_unit_enterprise_id" btree (enterprise_id)
    "ix_legal_unit_foreign_participation_id" btree (foreign_participation_id)
    "ix_legal_unit_legal_form_id" btree (legal_form_id)
    "ix_legal_unit_name" btree (name)
    "ix_legal_unit_sector_id" btree (sector_id)
    "ix_legal_unit_size_id" btree (unit_size_id)
    "ix_legal_unit_status_id" btree (status_id)
    "legal_unit_active_idx" btree (active)
    "legal_unit_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "legal_unit_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
Check constraints:
    "legal_unit_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "legal_unit_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    "legal_unit_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
    "legal_unit_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    "legal_unit_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
    "legal_unit_legal_form_id_fkey" FOREIGN KEY (legal_form_id) REFERENCES legal_form(id)
    "legal_unit_sector_id_fkey" FOREIGN KEY (sector_id) REFERENCES sector(id) ON DELETE RESTRICT
    "legal_unit_status_id_fkey" FOREIGN KEY (status_id) REFERENCES status(id) ON DELETE RESTRICT
    "legal_unit_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Policies:
    POLICY "legal_unit_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "legal_unit_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "legal_unit_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    activity_legal_unit_id_valid_uk_delete AFTER DELETE ON legal_unit FROM activity DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('activity_legal_unit_id_valid')
    activity_legal_unit_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON legal_unit FROM activity DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('activity_legal_unit_id_valid')
    contact_legal_unit_id_valid_uk_delete AFTER DELETE ON legal_unit FROM contact DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('contact_legal_unit_id_valid')
    contact_legal_unit_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON legal_unit FROM contact DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('contact_legal_unit_id_valid')
    establishment_legal_unit_id_valid_uk_delete AFTER DELETE ON legal_unit FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('establishment_legal_unit_id_valid')
    establishment_legal_unit_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON legal_unit FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('establishment_legal_unit_id_valid')
    legal_unit_changes_trigger AFTER INSERT OR UPDATE ON legal_unit FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    legal_unit_deletes_trigger BEFORE DELETE ON legal_unit FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    location_legal_unit_id_valid_uk_delete AFTER DELETE ON legal_unit FROM location DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('location_legal_unit_id_valid')
    location_legal_unit_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON legal_unit FROM location DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('location_legal_unit_id_valid')
    person_for_unit_legal_unit_id_valid_uk_delete AFTER DELETE ON legal_unit FROM person_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('person_for_unit_legal_unit_id_valid')
    person_for_unit_legal_unit_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON legal_unit FROM person_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('person_for_unit_legal_unit_id_valid')
    stat_for_unit_legal_unit_id_valid_uk_delete AFTER DELETE ON legal_unit FROM stat_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check('stat_for_unit_legal_unit_id_valid')
    stat_for_unit_legal_unit_id_valid_uk_update AFTER UPDATE OF id, valid_after, valid_to ON legal_unit FROM stat_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check('stat_for_unit_legal_unit_id_valid')
    trigger_prevent_legal_unit_id_update BEFORE UPDATE OF id ON legal_unit FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
