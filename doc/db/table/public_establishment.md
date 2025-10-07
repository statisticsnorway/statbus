```sql
                                             Table "public.establishment"
         Column         |           Type           | Collation | Nullable |                  Default                  
------------------------+--------------------------+-----------+----------+-------------------------------------------
 id                     | integer                  |           | not null | nextval('establishment_id_seq'::regclass)
 valid_from             | date                     |           | not null | 
 valid_to               | date                     |           |          | 
 valid_until            | date                     |           | not null | 
 short_name             | character varying(16)    |           |          | 
 name                   | character varying(256)   |           | not null | 
 birth_date             | date                     |           |          | 
 death_date             | date                     |           |          | 
 free_econ_zone         | boolean                  |           |          | 
 sector_id              | integer                  |           |          | 
 status_id              | integer                  |           | not null | 
 edit_comment           | character varying(512)   |           |          | 
 edit_by_user_id        | integer                  |           | not null | 
 edit_at                | timestamp with time zone |           | not null | statement_timestamp()
 unit_size_id           | integer                  |           |          | 
 data_source_id         | integer                  |           |          | 
 enterprise_id          | integer                  |           |          | 
 legal_unit_id          | integer                  |           |          | 
 primary_for_legal_unit | boolean                  |           |          | 
 primary_for_enterprise | boolean                  |           |          | 
 invalid_codes          | jsonb                    |           |          | 
Indexes:
    "establishment_pkey" PRIMARY KEY, btree (id, valid_from) DEFERRABLE
    "establishment_enterprise_id_primary_for_enterprise_idx" btree (enterprise_id, primary_for_enterprise) WHERE enterprise_id IS NOT NULL
    "establishment_enterprise_id_primary_valid_excl" EXCLUDE USING gist (enterprise_id WITH =, daterange(valid_from, valid_until) WITH &&) WHERE (primary_for_enterprise IS TRUE) DEFERRABLE
    "establishment_enterprise_id_primary_valid_idx" UNIQUE, btree (enterprise_id, valid_from, valid_until) WHERE primary_for_enterprise IS TRUE
    "establishment_id_idx" btree (id)
    "establishment_id_valid_excl" EXCLUDE USING gist (id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "establishment_legal_unit_id_primary_for_legal_unit_idx" btree (legal_unit_id, primary_for_legal_unit) WHERE legal_unit_id IS NOT NULL
    "establishment_legal_unit_id_primary_valid_excl" EXCLUDE USING gist (legal_unit_id WITH =, daterange(valid_from, valid_until) WITH &&) WHERE (primary_for_legal_unit IS TRUE) DEFERRABLE
    "establishment_legal_unit_id_primary_valid_idx" UNIQUE, btree (legal_unit_id, valid_from, valid_until) WHERE primary_for_legal_unit IS TRUE
    "ix_establishment_data_source_id" btree (data_source_id)
    "ix_establishment_edit_by_user_id" btree (edit_by_user_id)
    "ix_establishment_enterprise_id" btree (enterprise_id)
    "ix_establishment_enterprise_id_valid_range" gist (enterprise_id, daterange(valid_from, valid_until, '[)'::text))
    "ix_establishment_legal_unit_id" btree (legal_unit_id)
    "ix_establishment_legal_unit_id_valid_range" gist (legal_unit_id, daterange(valid_from, valid_until, '[)'::text))
    "ix_establishment_name" btree (name)
    "ix_establishment_sector_id" btree (sector_id)
    "ix_establishment_size_id" btree (unit_size_id)
    "ix_establishment_status_id" btree (status_id)
Check constraints:
    "Must have either legal_unit_id or enterprise_id" CHECK (enterprise_id IS NOT NULL AND legal_unit_id IS NULL OR enterprise_id IS NULL AND legal_unit_id IS NOT NULL)
    "enterprise_id enables sector_id" CHECK (
CASE
    WHEN enterprise_id IS NULL THEN sector_id IS NULL
    ELSE NULL::boolean
END)
    "establishment_valid_check" CHECK (valid_from < valid_until AND valid_from > '-infinity'::date)
    "primary_for_enterprise and enterprise_id must be defined togeth" CHECK (enterprise_id IS NOT NULL AND primary_for_enterprise IS NOT NULL OR enterprise_id IS NULL AND primary_for_enterprise IS NULL)
    "primary_for_legal_unit and legal_unit_id must be defined togeth" CHECK (legal_unit_id IS NOT NULL AND primary_for_legal_unit IS NOT NULL OR legal_unit_id IS NULL AND primary_for_legal_unit IS NULL)
Foreign-key constraints:
    "establishment_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE RESTRICT
    "establishment_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "establishment_enterprise_id_fkey" FOREIGN KEY (enterprise_id) REFERENCES enterprise(id) ON DELETE RESTRICT
    "establishment_sector_id_fkey" FOREIGN KEY (sector_id) REFERENCES sector(id) ON DELETE RESTRICT
    "establishment_status_id_fkey" FOREIGN KEY (status_id) REFERENCES status(id) ON DELETE RESTRICT
    "establishment_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Policies:
    POLICY "establishment_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "establishment_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "establishment_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    activity_establishment_id_valid_uk_delete AFTER DELETE ON establishment FROM activity DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check_c('activity_establishment_id_valid', 'public', 'activity', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    activity_establishment_id_valid_uk_update AFTER UPDATE OF id, valid_from, valid_until ON establishment FROM activity DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check_c('activity_establishment_id_valid', 'public', 'activity', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    contact_establishment_id_valid_uk_delete AFTER DELETE ON establishment FROM contact DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check_c('contact_establishment_id_valid', 'public', 'contact', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    contact_establishment_id_valid_uk_update AFTER UPDATE OF id, valid_from, valid_until ON establishment FROM contact DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check_c('contact_establishment_id_valid', 'public', 'contact', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    establishment_changes_trigger AFTER INSERT OR UPDATE ON establishment FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    establishment_deletes_trigger BEFORE DELETE ON establishment FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    establishment_legal_unit_id_valid_fk_insert AFTER INSERT ON establishment FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('establishment_legal_unit_id_valid', 'public', 'establishment', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    establishment_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_from, valid_until, valid_to ON establishment FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('establishment_legal_unit_id_valid', 'public', 'establishment', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    establishment_synchronize_temporal_columns_trigger BEFORE INSERT OR UPDATE OF valid_from, valid_until, valid_to ON establishment FOR EACH ROW EXECUTE FUNCTION sql_saga.synchronize_temporal_columns('valid_from', 'valid_until', 'valid_to', 'null', 'date', 't')
    location_establishment_id_valid_uk_delete AFTER DELETE ON establishment FROM location DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check_c('location_establishment_id_valid', 'public', 'location', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    location_establishment_id_valid_uk_update AFTER UPDATE OF id, valid_from, valid_until ON establishment FROM location DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check_c('location_establishment_id_valid', 'public', 'location', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    person_for_unit_establishment_id_valid_uk_delete AFTER DELETE ON establishment FROM person_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check_c('person_for_unit_establishment_id_valid', 'public', 'person_for_unit', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    person_for_unit_establishment_id_valid_uk_update AFTER UPDATE OF id, valid_from, valid_until ON establishment FROM person_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check_c('person_for_unit_establishment_id_valid', 'public', 'person_for_unit', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    stat_for_unit_establishment_id_valid_uk_delete AFTER DELETE ON establishment FROM stat_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_delete_check_c('stat_for_unit_establishment_id_valid', 'public', 'stat_for_unit', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    stat_for_unit_establishment_id_valid_uk_update AFTER UPDATE OF id, valid_from, valid_until ON establishment FROM stat_for_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.uk_update_check_c('stat_for_unit_establishment_id_valid', 'public', 'stat_for_unit', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION', 'temporal_to_temporal')
    trigger_prevent_establishment_id_update BEFORE UPDATE OF id ON establishment FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
