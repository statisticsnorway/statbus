```sql
                               Table "public.activity_category_standard"
    Column    |               Type               | Collation | Nullable |           Default            
--------------+----------------------------------+-----------+----------+------------------------------
 id           | integer                          |           | not null | generated always as identity
 code         | character varying(16)            |           | not null | 
 name         | character varying                |           | not null | 
 description  | character varying                |           | not null | 
 code_pattern | activity_category_code_behaviour |           | not null | 
 obsolete     | boolean                          |           | not null | false
Indexes:
    "activity_category_standard_pkey" PRIMARY KEY, btree (id)
    "activity_category_standard_code_key" UNIQUE CONSTRAINT, btree (code)
    "activity_category_standard_description_key" UNIQUE CONSTRAINT, btree (description)
    "activity_category_standard_name_key" UNIQUE CONSTRAINT, btree (name)
Referenced by:
    TABLE "activity_category" CONSTRAINT "activity_category_standard_id_fkey" FOREIGN KEY (standard_id) REFERENCES activity_category_standard(id) ON DELETE RESTRICT
    TABLE "settings" CONSTRAINT "settings_activity_category_standard_id_fkey" FOREIGN KEY (activity_category_standard_id) REFERENCES activity_category_standard(id) ON DELETE RESTRICT
Policies:
    POLICY "activity_category_standard_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_category_standard_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "activity_category_standard_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_activity_category_standard_id_update BEFORE UPDATE OF id ON activity_category_standard FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
