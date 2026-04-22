```sql
                                           Table "public.settings"
            Column             |  Type   | Collation | Nullable |                   Default                   
-------------------------------+---------+-----------+----------+---------------------------------------------
 id                            | integer |           | not null | generated always as identity
 activity_category_standard_id | integer |           | not null | 
 country_id                    | integer |           | not null | 
 only_one_setting              | boolean |           |          | generated always as (id IS NOT NULL) stored
 region_version_id             | integer |           | not null | 
 required_to_be_enabled        | boolean |           |          | generated always as (true) stored
 partition_count_target        | integer |           | not null | 256
Indexes:
    "settings_pkey" PRIMARY KEY, btree (id)
    "settings_only_one_setting_key" UNIQUE CONSTRAINT, btree (only_one_setting)
Foreign-key constraints:
    "settings_activity_category_standard_enabled_fk" FOREIGN KEY (activity_category_standard_id, required_to_be_enabled) REFERENCES activity_category_standard(id, enabled)
    "settings_activity_category_standard_id_fkey" FOREIGN KEY (activity_category_standard_id) REFERENCES activity_category_standard(id) ON DELETE RESTRICT
    "settings_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id) ON DELETE RESTRICT
    "settings_region_version_enabled_fk" FOREIGN KEY (region_version_id, required_to_be_enabled) REFERENCES region_version(id, enabled)
    "settings_region_version_id_fkey" FOREIGN KEY (region_version_id) REFERENCES region_version(id)
Policies:
    POLICY "settings_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "settings_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "settings_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    trigger_prevent_settings_id_update BEFORE UPDATE OF id ON settings FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
