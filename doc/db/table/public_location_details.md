```sql
                                                                                 Table "public.location"
       Column       |          Type          | Collation | Nullable |                            Default                            | Storage  | Compression | Stats target | Description 
--------------------+------------------------+-----------+----------+---------------------------------------------------------------+----------+-------------+--------------+-------------
 id                 | integer                |           | not null | nextval('location_id_seq'::regclass)                          | plain    |             |              | 
 valid_after        | date                   |           | not null | generated always as ((valid_from - '1 day'::interval)) stored | plain    |             |              | 
 valid_from         | date                   |           | not null | CURRENT_DATE                                                  | plain    |             |              | 
 valid_to           | date                   |           | not null | 'infinity'::date                                              | plain    |             |              | 
 type               | location_type          |           | not null |                                                               | plain    |             |              | 
 address_part1      | character varying(200) |           |          |                                                               | extended |             |              | 
 address_part2      | character varying(200) |           |          |                                                               | extended |             |              | 
 address_part3      | character varying(200) |           |          |                                                               | extended |             |              | 
 postcode           | character varying(200) |           |          |                                                               | extended |             |              | 
 postplace          | character varying(200) |           |          |                                                               | extended |             |              | 
 region_id          | integer                |           |          |                                                               | plain    |             |              | 
 country_id         | integer                |           | not null |                                                               | plain    |             |              | 
 latitude           | numeric(9,6)           |           |          |                                                               | main     |             |              | 
 longitude          | numeric(9,6)           |           |          |                                                               | main     |             |              | 
 altitude           | numeric(6,1)           |           |          |                                                               | main     |             |              | 
 establishment_id   | integer                |           |          |                                                               | plain    |             |              | 
 legal_unit_id      | integer                |           |          |                                                               | plain    |             |              | 
 data_source_id     | integer                |           |          |                                                               | plain    |             |              | 
 updated_by_user_id | integer                |           | not null |                                                               | plain    |             |              | 
Indexes:
    "ix_address_region_id" btree (region_id)
    "ix_location_establishment_id_id" btree (establishment_id)
    "ix_location_legal_unit_id_id" btree (legal_unit_id)
    "ix_location_updated_by_user_id" btree (updated_by_user_id)
    "location_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "location_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "location_type_establishment_id_daterange_excl" EXCLUDE USING gist (type WITH =, establishment_id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "location_type_establishment_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (type, establishment_id, valid_after, valid_to) DEFERRABLE
    "location_type_legal_unit_id_daterange_excl" EXCLUDE USING gist (type WITH =, legal_unit_id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "location_type_legal_unit_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (type, legal_unit_id, valid_after, valid_to) DEFERRABLE
Check constraints:
    "One and only one statistical unit id must be set" CHECK (establishment_id IS NOT NULL AND legal_unit_id IS NULL OR establishment_id IS NULL AND legal_unit_id IS NOT NULL)
    "altitude requires coordinates" CHECK (
CASE
    WHEN altitude IS NOT NULL THEN latitude IS NOT NULL AND longitude IS NOT NULL
    ELSE true
END)
    "coordinates require both latitude and longitude" CHECK (latitude IS NOT NULL AND longitude IS NOT NULL OR latitude IS NULL AND longitude IS NULL)
    "location_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "location_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id) ON DELETE RESTRICT
    "location_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id) ON DELETE SET NULL
    "location_region_id_fkey" FOREIGN KEY (region_id) REFERENCES region(id) ON DELETE RESTRICT
    "location_updated_by_user_id_fkey" FOREIGN KEY (updated_by_user_id) REFERENCES statbus_user(id) ON DELETE RESTRICT
Policies:
    POLICY "location_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "location_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "location_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    location_establishment_id_valid_fk_insert AFTER INSERT ON location FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('location_establishment_id_valid')
    location_establishment_id_valid_fk_update AFTER UPDATE OF establishment_id, valid_after, valid_to ON location FROM establishment DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('location_establishment_id_valid')
    location_legal_unit_id_valid_fk_insert AFTER INSERT ON location FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_insert_check('location_legal_unit_id_valid')
    location_legal_unit_id_valid_fk_update AFTER UPDATE OF legal_unit_id, valid_after, valid_to ON location FROM legal_unit DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION sql_saga.fk_update_check('location_legal_unit_id_valid')
    trigger_prevent_location_id_update BEFORE UPDATE OF id ON location FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
