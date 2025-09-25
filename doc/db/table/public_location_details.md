```sql
                                                                                                             Table "public.location"
      Column      |           Type           | Collation | Nullable |               Default                | Storage  | Compression | Stats target |                                         Description                                         
------------------+--------------------------+-----------+----------+--------------------------------------+----------+-------------+--------------+---------------------------------------------------------------------------------------------
 id               | integer                  |           | not null | nextval('location_id_seq'::regclass) | plain    |             |              | Primary key for the location record (not the temporal era).
 valid_from       | date                     |           | not null |                                      | plain    |             |              | Start date (inclusive) of the validity period for this location era.
 valid_to         | date                     |           | not null |                                      | plain    |             |              | End date (inclusive) of the validity period for this location era. UI-facing.
 valid_until      | date                     |           | not null |                                      | plain    |             |              | End date (exclusive) of the validity period for this location era. Used for temporal logic.
 type             | location_type            |           | not null |                                      | plain    |             |              | Type of location: 'physical' or 'postal'.
 address_part1    | character varying(200)   |           |          |                                      | extended |             |              | First line of the address.
 address_part2    | character varying(200)   |           |          |                                      | extended |             |              | Second line of the address.
 address_part3    | character varying(200)   |           |          |                                      | extended |             |              | Third line of the address.
 postcode         | character varying(200)   |           |          |                                      | extended |             |              | Postal code.
 postplace        | character varying(200)   |           |          |                                      | extended |             |              | Postal place (city/town).
 region_id        | integer                  |           |          |                                      | plain    |             |              | Foreign key to the region table.
 country_id       | integer                  |           | not null |                                      | plain    |             |              | Foreign key to the country table.
 latitude         | numeric(9,6)             |           |          |                                      | main     |             |              | Latitude coordinate (decimal degrees). Only applicable for physical locations.
 longitude        | numeric(9,6)             |           |          |                                      | main     |             |              | Longitude coordinate (decimal degrees). Only applicable for physical locations.
 altitude         | numeric(6,1)             |           |          |                                      | main     |             |              | Altitude coordinate (meters). Only applicable for physical locations.
 establishment_id | integer                  |           |          |                                      | plain    |             |              | Foreign key to the establishment this location belongs to (NULL if linked to legal_unit).
 legal_unit_id    | integer                  |           |          |                                      | plain    |             |              | Foreign key to the legal unit this location belongs to (NULL if linked to establishment).
 data_source_id   | integer                  |           |          |                                      | plain    |             |              | Foreign key to the data source providing this information.
 edit_comment     | character varying(512)   |           |          |                                      | extended |             |              | Comment added during manual edit.
 edit_by_user_id  | integer                  |           | not null |                                      | plain    |             |              | User who last edited this record.
 edit_at          | timestamp with time zone |           | not null | statement_timestamp()                | plain    |             |              | Timestamp of the last edit.
Indexes:
    "location_pkey" PRIMARY KEY, btree (id, valid_from, valid_until) DEFERRABLE
    "ix_location_country_id" btree (country_id)
    "ix_location_data_source_id" btree (data_source_id)
    "ix_location_edit_by_user_id" btree (edit_by_user_id)
    "ix_location_establishment_id" btree (establishment_id)
    "ix_location_establishment_id_valid_range" gist (establishment_id, daterange(valid_from, valid_until, '[)'::text))
    "ix_location_legal_unit_id" btree (legal_unit_id)
    "ix_location_legal_unit_id_valid_range" gist (legal_unit_id, daterange(valid_from, valid_until, '[)'::text))
    "ix_location_region_id" btree (region_id)
    "ix_location_type" btree (type)
    "location_id_idx" btree (id)
    "location_id_valid_excl" EXCLUDE USING gist (id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "location_type_establishment_id_idx" btree (type, establishment_id)
    "location_type_establishment_id_valid_excl" EXCLUDE USING gist (type WITH =, establishment_id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "location_type_establishment_id_valid_uniq" UNIQUE CONSTRAINT, btree (type, establishment_id, valid_from, valid_until) DEFERRABLE
    "location_type_legal_unit_id_idx" btree (type, legal_unit_id)
    "location_type_legal_unit_id_valid_excl" EXCLUDE USING gist (type WITH =, legal_unit_id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "location_type_legal_unit_id_valid_uniq" UNIQUE CONSTRAINT, btree (type, legal_unit_id, valid_from, valid_until) DEFERRABLE
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
    "location_valid_check" CHECK (valid_from < valid_until AND valid_from > '-infinity'::date)
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
    location_establishment_id_valid_fk_insert AFTER INSERT ON location FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('location_establishment_id_valid', 'public', 'location', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    location_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_from, valid_until, valid_to ON location FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('location_establishment_id_valid', 'public', 'location', '{establishment_id}', 'valid', 'valid_from', 'valid_until', 'public', 'establishment', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    location_legal_unit_id_valid_fk_insert AFTER INSERT ON location FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check_c('location_legal_unit_id_valid', 'public', 'location', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    location_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_from, valid_until, valid_to ON location FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check_c('location_legal_unit_id_valid', 'public', 'location', '{legal_unit_id}', 'valid', 'valid_from', 'valid_until', 'public', 'legal_unit', '{id}', 'valid', 'valid_from', 'valid_until', 'SIMPLE', 'NO ACTION', 'NO ACTION')
    location_synchronize_temporal_columns_trigger BEFORE INSERT OR UPDATE OF valid_from, valid_until, valid_to ON location FOR EACH ROW EXECUTE FUNCTION sql_saga.synchronize_temporal_columns('valid_from', 'valid_until', 'valid_to', 'null', 'date', 't')
    trigger_prevent_location_id_update BEFORE UPDATE OF id ON location FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
