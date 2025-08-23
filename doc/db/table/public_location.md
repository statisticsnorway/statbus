```sql
                                          Table "public.location"
      Column      |           Type           | Collation | Nullable |               Default                
------------------+--------------------------+-----------+----------+--------------------------------------
 id               | integer                  |           | not null | nextval('location_id_seq'::regclass)
 valid_from       | date                     |           | not null | 
 valid_after      | date                     |           | not null | 
 valid_to         | date                     |           | not null | 'infinity'::date
 type             | location_type            |           | not null | 
 address_part1    | character varying(200)   |           |          | 
 address_part2    | character varying(200)   |           |          | 
 address_part3    | character varying(200)   |           |          | 
 postcode         | character varying(200)   |           |          | 
 postplace        | character varying(200)   |           |          | 
 region_id        | integer                  |           |          | 
 country_id       | integer                  |           | not null | 
 latitude         | numeric(9,6)             |           |          | 
 longitude        | numeric(9,6)             |           |          | 
 altitude         | numeric(6,1)             |           |          | 
 establishment_id | integer                  |           |          | 
 legal_unit_id    | integer                  |           |          | 
 data_source_id   | integer                  |           |          | 
 edit_comment     | character varying(512)   |           |          | 
 edit_by_user_id  | integer                  |           | not null | 
 edit_at          | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "ix_location_country_id" btree (country_id)
    "ix_location_data_source_id" btree (data_source_id)
    "ix_location_edit_by_user_id" btree (edit_by_user_id)
    "ix_location_establishment_id" btree (establishment_id)
    "ix_location_establishment_id_valid_range" gist (establishment_id, daterange(valid_after, valid_to, '(]'::text))
    "ix_location_legal_unit_id" btree (legal_unit_id)
    "ix_location_legal_unit_id_valid_range" gist (legal_unit_id, daterange(valid_after, valid_to, '(]'::text))
    "ix_location_region_id" btree (region_id)
    "ix_location_type" btree (type)
    "location_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "location_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "location_type_establishment_id_daterange_excl" EXCLUDE USING gist (type WITH =, establishment_id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "location_type_establishment_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (type, establishment_id, valid_after, valid_to) DEFERRABLE
    "location_type_legal_unit_id_daterange_excl" EXCLUDE USING gist (type WITH =, legal_unit_id WITH =, daterange(valid_after, valid_to, '(]'::text) WITH &&) DEFERRABLE
    "location_type_legal_unit_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (type, legal_unit_id, valid_after, valid_to) DEFERRABLE
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "altitude requires coordinates" CHECK (
CASE
    WHEN altitude IS NOT NULL THEN latitude IS NOT NULL AND longitude IS NOT NULL
    ELSE true
END)
    "altitude_must_be_positive" CHECK (altitude >= 0::numeric)
    "coordinates require both latitude and longitude" CHECK (latitude IS NOT NULL AND longitude IS NOT NULL OR latitude IS NULL AND longitude IS NULL)
    "latitude_must_be_from_minus_90_to_90_degrees" CHECK (latitude >= '-90'::integer::numeric AND latitude <= 90::numeric)
    "location_valid_check" CHECK (valid_after < valid_to)
    "longitude_must_be_from_minus_180_to_180_degrees" CHECK (longitude >= '-180'::integer::numeric AND longitude <= 180::numeric)
    "postal_locations_cannot_have_coordinates" CHECK (
CASE type
    WHEN 'postal'::location_type THEN latitude IS NULL AND longitude IS NULL AND altitude IS NULL
    ELSE true
END)
Foreign-key constraints:
    "location_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id) ON DELETE RESTRICT
    "location_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    "location_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "location_region_id_fkey" FOREIGN KEY (region_id) REFERENCES region(id) ON DELETE RESTRICT
Policies:
    POLICY "location_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "location_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "location_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
    POLICY "restricted_user_location_access"
      TO restricted_user
      USING ((EXISTS ( SELECT 1
   FROM region_access ra
  WHERE ((ra.user_id = auth.uid()) AND (ra.region_id = ra.region_id)))))
      WITH CHECK ((EXISTS ( SELECT 1
   FROM region_access ra
  WHERE ((ra.user_id = auth.uid()) AND (ra.region_id = ra.region_id)))))
Triggers:
    location_changes_trigger AFTER INSERT OR UPDATE ON location FOR EACH STATEMENT EXECUTE FUNCTION worker.notify_worker_about_changes()
    location_deletes_trigger BEFORE DELETE ON location FOR EACH ROW EXECUTE FUNCTION worker.notify_worker_about_deletes()
    location_establishment_id_valid_fk_insert AFTER INSERT ON location FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('location_establishment_id_valid', 'public.location', 'public', 'location', '{{establishment_id}}', 'valid', 'valid_after', 'valid_to', 'public', 'establishment', '{{id}}', 'valid', 'valid_after', 'valid_to', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    location_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON location FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('location_establishment_id_valid', 'public.location', 'public', 'location', '{{establishment_id}}', 'valid', 'valid_after', 'valid_to', 'public', 'establishment', '{{id}}', 'valid', 'valid_after', 'valid_to', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    location_legal_unit_id_valid_fk_insert AFTER INSERT ON location FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('location_legal_unit_id_valid', 'public.location', 'public', 'location', '{{legal_unit_id}}', 'valid', 'valid_after', 'valid_to', 'public', 'legal_unit', '{{id}}', 'valid', 'valid_after', 'valid_to', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    location_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON location FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('location_legal_unit_id_valid', 'public.location', 'public', 'location', '{{legal_unit_id}}', 'valid', 'valid_after', 'valid_to', 'public', 'legal_unit', '{{id}}', 'valid', 'valid_after', 'valid_to', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    trg_location_synchronize_valid_from_after BEFORE INSERT OR UPDATE ON location FOR EACH ROW EXECUTE FUNCTION synchronize_valid_from_after()
    trigger_prevent_location_id_update BEFORE UPDATE OF id ON location FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
