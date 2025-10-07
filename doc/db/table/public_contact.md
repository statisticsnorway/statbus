```sql
                                          Table "public.contact"
      Column      |           Type           | Collation | Nullable |               Default               
------------------+--------------------------+-----------+----------+-------------------------------------
 id               | integer                  |           | not null | nextval('contact_id_seq'::regclass)
 valid_from       | date                     |           | not null | 
 valid_to         | date                     |           |          | 
 valid_until      | date                     |           | not null | 
 web_address      | character varying(256)   |           |          | 
 email_address    | character varying(50)    |           |          | 
 phone_number     | character varying(50)    |           |          | 
 landline         | character varying(50)    |           |          | 
 mobile_number    | character varying(50)    |           |          | 
 fax_number       | character varying(50)    |           |          | 
 establishment_id | integer                  |           |          | 
 legal_unit_id    | integer                  |           |          | 
 data_source_id   | integer                  |           |          | 
 edit_comment     | character varying(512)   |           |          | 
 edit_by_user_id  | integer                  |           | not null | 
 edit_at          | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "contact_pkey" PRIMARY KEY, btree (id, valid_from) DEFERRABLE
    "contact_id_idx" btree (id)
    "contact_id_valid_excl" EXCLUDE USING gist (id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "contact_legal_unit_id_establishment_id_idx" btree (legal_unit_id, establishment_id)
    "contact_natural_key_vali_establishment_id_pk_consistency_excl" EXCLUDE USING gist (establishment_id WITH =, id WITH <>) WHERE (establishment_id IS NOT NULL AND legal_unit_id IS NULL)
    "contact_natural_key_valid_establishment_id_excl" EXCLUDE USING gist (establishment_id WITH =, daterange(valid_from, valid_until) WITH &&) WHERE (establishment_id IS NOT NULL AND legal_unit_id IS NULL) DEFERRABLE
    "contact_natural_key_valid_establishment_id_idx" btree (establishment_id) WHERE establishment_id IS NOT NULL AND legal_unit_id IS NULL
    "contact_natural_key_valid_legal_unit_id_excl" EXCLUDE USING gist (legal_unit_id WITH =, daterange(valid_from, valid_until) WITH &&) WHERE (legal_unit_id IS NOT NULL AND establishment_id IS NULL) DEFERRABLE
    "contact_natural_key_valid_legal_unit_id_idx" btree (legal_unit_id) WHERE legal_unit_id IS NOT NULL AND establishment_id IS NULL
    "contact_natural_key_valid_legal_unit_id_pk_consistency_excl" EXCLUDE USING gist (legal_unit_id WITH =, id WITH <>) WHERE (legal_unit_id IS NOT NULL AND establishment_id IS NULL)
    "ix_contact_data_source_id" btree (data_source_id)
    "ix_contact_edit_by_user_id" btree (edit_by_user_id)
    "ix_contact_establishment_id" btree (establishment_id)
    "ix_contact_establishment_id_valid_range" gist (establishment_id, daterange(valid_from, valid_until, '[)'::text))
    "ix_contact_legal_unit_id" btree (legal_unit_id)
    "ix_contact_legal_unit_id_valid_range" gist (legal_unit_id, daterange(valid_from, valid_until, '[)'::text))
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "One information must be provided" CHECK (web_address IS NOT NULL OR email_address IS NOT NULL OR phone_number IS NOT NULL OR landline IS NOT NULL OR mobile_number IS NOT NULL OR fax_number IS NOT NULL)
    "contact_natural_key_valid_xor_check" CHECK ((
CASE
    WHEN legal_unit_id IS NOT NULL THEN 1
    ELSE 0
END +
CASE
    WHEN establishment_id IS NOT NULL THEN 1
    ELSE 0
END) = 1)
    "contact_valid_check" CHECK (valid_from < valid_until AND valid_from > '-infinity'::date)
Foreign-key constraints:
    "contact_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    "contact_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
Policies:
    POLICY "contact_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "contact_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "contact_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    contact_changes_trigger AFTER INSERT OR UPDATE ON contact FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    contact_deletes_trigger BEFORE DELETE ON contact FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    contact_establishment_id_valid_fk_insert AFTER INSERT ON contact FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('contact_establishment_id_valid', 'public', 'contact', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    contact_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_from, valid_until, valid_to ON contact FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('contact_establishment_id_valid', 'public', 'contact', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    contact_legal_unit_id_valid_fk_insert AFTER INSERT ON contact FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('contact_legal_unit_id_valid', 'public', 'contact', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    contact_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_from, valid_until, valid_to ON contact FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('contact_legal_unit_id_valid', 'public', 'contact', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    contact_synchronize_temporal_columns_trigger BEFORE INSERT OR UPDATE OF valid_from, valid_until, valid_to ON contact FOR EACH ROW EXECUTE FUNCTION sql_saga.synchronize_temporal_columns('valid_from', 'valid_until', 'valid_to', 'null', 'date', 't')
    trigger_prevent_contact_id_update BEFORE UPDATE OF id ON contact FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
