```sql
                                                       Table "public.contact"
      Column      |           Type           | Collation | Nullable |                            Default                            
------------------+--------------------------+-----------+----------+---------------------------------------------------------------
 id               | integer                  |           | not null | nextval('contact_id_seq'::regclass)
 valid_after      | date                     |           | not null | generated always as ((valid_from - '1 day'::interval)) stored
 valid_from       | date                     |           | not null | CURRENT_DATE
 valid_to         | date                     |           | not null | 'infinity'::date
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
    "contact_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "contact_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "ix_contact_data_source_id" btree (data_source_id)
    "ix_contact_edit_by_user_id" btree (edit_by_user_id)
    "ix_contact_establishment_id" btree (establishment_id)
    "ix_contact_legal_unit_id" btree (legal_unit_id)
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "One information must be provided" CHECK (web_address IS NOT NULL OR email_address IS NOT NULL OR phone_number IS NOT NULL OR landline IS NOT NULL OR mobile_number IS NOT NULL OR fax_number IS NOT NULL)
    "contact_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "contact_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    "contact_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
Policies:
    POLICY "contact_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "contact_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "contact_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    contact_establishment_id_valid_fk_insert AFTER INSERT ON contact FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('contact_establishment_id_valid')
    contact_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON contact FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('contact_establishment_id_valid')
    contact_legal_unit_id_valid_fk_insert AFTER INSERT ON contact FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('contact_legal_unit_id_valid')
    contact_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON contact FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('contact_legal_unit_id_valid')
    trigger_prevent_contact_id_update BEFORE UPDATE OF id ON contact FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
