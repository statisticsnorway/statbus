```sql
                                                                      Table "public.settings"
            Column             |  Type   | Collation | Nullable |                   Default                   | Storage | Compression | Stats target | Description 
-------------------------------+---------+-----------+----------+---------------------------------------------+---------+-------------+--------------+-------------
 id                            | integer |           | not null | generated always as identity                | plain   |             |              | 
 activity_category_standard_id | integer |           | not null |                                             | plain   |             |              | 
 country_id                    | integer |           | not null |                                             | plain   |             |              | 
 only_one_setting              | boolean |           |          | generated always as (id IS NOT NULL) stored | plain   |             |              | 
Indexes:
    "settings_pkey" PRIMARY KEY, btree (id)
    "settings_only_one_setting_key" UNIQUE CONSTRAINT, btree (only_one_setting)
Foreign-key constraints:
    "settings_activity_category_standard_id_fkey" FOREIGN KEY (activity_category_standard_id) REFERENCES activity_category_standard(id) ON DELETE RESTRICT
    "settings_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id) ON DELETE RESTRICT
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
Not-null constraints:
    "settings_id_not_null" NOT NULL "id"
    "settings_activity_category_standard_id_not_null" NOT NULL "activity_category_standard_id"
    "settings_country_id_not_null" NOT NULL "country_id"
Triggers:
    trigger_prevent_settings_id_update BEFORE UPDATE OF id ON settings FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
