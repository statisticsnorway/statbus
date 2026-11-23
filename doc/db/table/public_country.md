```sql
                                                                                                                                             Table "public.country"
   Column   |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target |                                                                                Description                                                                                
------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 id         | integer                  |           | not null | generated always as identity | plain    |             |              | 
 iso_2      | text                     |           | not null |                              | extended |             |              | 
 iso_3      | text                     |           | not null |                              | extended |             |              | 
 iso_num    | text                     |           | not null |                              | extended |             |              | 
 name       | text                     |           | not null |                              | extended |             |              | 
 enabled    | boolean                  |           | not null |                              | plain    |             |              | 
 custom     | boolean                  |           | not null |                              | plain    |             |              | 
 created_at | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 updated_at | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 latitude   | numeric(9,6)             |           |          |                              | main     |             |              | The country's centre, degrees north (WGS 84), where a map draws the country as one point, such as the Regions map's world level. Set together with longitude, or neither.
 longitude  | numeric(9,6)             |           |          |                              | main     |             |              | The country's centre, degrees east (WGS 84). Set together with latitude, or neither.
Indexes:
    "country_pkey" PRIMARY KEY, btree (id)
    "country_iso_2_iso_3_iso_num_name_key" UNIQUE CONSTRAINT, btree (iso_2, iso_3, iso_num, name)
    "country_iso_2_key" UNIQUE CONSTRAINT, btree (iso_2)
    "country_iso_3_key" UNIQUE CONSTRAINT, btree (iso_3)
    "country_iso_num_key" UNIQUE CONSTRAINT, btree (iso_num)
    "country_name_key" UNIQUE CONSTRAINT, btree (name)
    "ix_country_enabled" btree (enabled)
    "ix_country_iso_2" UNIQUE, btree (iso_2) WHERE enabled
    "ix_country_iso_3" UNIQUE, btree (iso_3) WHERE enabled
    "ix_country_iso_num" UNIQUE, btree (iso_num) WHERE enabled
Check constraints:
    "country_latitude_and_longitude_together" CHECK (num_nonnulls(latitude, longitude) = ANY (ARRAY[0, 2]))
    "country_latitude_from_minus_90_to_90_degrees" CHECK (latitude >= '-90'::integer::numeric AND latitude <= 90::numeric)
    "country_longitude_from_minus_180_to_180_degrees" CHECK (longitude >= '-180'::integer::numeric AND longitude <= 180::numeric)
Referenced by:
    TABLE "location" CONSTRAINT "location_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id) ON DELETE RESTRICT
    TABLE "person" CONSTRAINT "person_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id)
    TABLE "settings" CONSTRAINT "settings_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id) ON DELETE RESTRICT
Policies:
    POLICY "country_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "country_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "country_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "country_id_not_null" NOT NULL "id"
    "country_iso_2_not_null" NOT NULL "iso_2"
    "country_iso_3_not_null" NOT NULL "iso_3"
    "country_iso_num_not_null" NOT NULL "iso_num"
    "country_name_not_null" NOT NULL "name"
    "country_enabled_not_null" NOT NULL "enabled"
    "country_custom_not_null" NOT NULL "custom"
    "country_created_at_not_null" NOT NULL "created_at"
    "country_updated_at_not_null" NOT NULL "updated_at"
Triggers:
    trigger_prevent_country_id_update BEFORE UPDATE OF id ON country FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
