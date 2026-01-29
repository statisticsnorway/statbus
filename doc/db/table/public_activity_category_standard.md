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
    POLICY "activity_category_standard_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "activity_category_standard_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_category_standard_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Triggers:
    recalculate_activity_category_codes_after_update AFTER UPDATE OF code_pattern ON activity_category_standard FOR EACH ROW WHEN (old.code_pattern IS DISTINCT FROM new.code_pattern) EXECUTE FUNCTION recalculate_activity_category_codes()
    trigger_prevent_activity_category_standard_id_update BEFORE UPDATE OF id ON activity_category_standard FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
