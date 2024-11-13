```sql
                                                              Table "public.settings"
            Column             |  Type   | Collation | Nullable |           Default            | Storage | Compression | Stats target | Description 
-------------------------------+---------+-----------+----------+------------------------------+---------+-------------+--------------+-------------
 id                            | integer |           | not null | generated always as identity | plain   |             |              | 
 activity_category_standard_id | integer |           | not null |                              | plain   |             |              | 
 only_one_setting              | boolean |           | not null | true                         | plain   |             |              | 
Indexes:
    "settings_pkey" PRIMARY KEY, btree (id)
    "settings_only_one_setting_key" UNIQUE CONSTRAINT, btree (only_one_setting)
Check constraints:
    "settings_only_one_setting_check" CHECK (only_one_setting)
Foreign-key constraints:
    "settings_activity_category_standard_id_fkey" FOREIGN KEY (activity_category_standard_id) REFERENCES activity_category_standard(id) ON DELETE RESTRICT
Policies:
    POLICY "settings_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "settings_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "settings_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_settings_id_update BEFORE UPDATE OF id ON settings FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
