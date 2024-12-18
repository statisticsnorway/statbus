```sql
                                                                              Table "public.activity_category"
   Column    |           Type           | Collation | Nullable |                                Default                                | Storage  | Compression | Stats target | Description 
-------------+--------------------------+-----------+----------+-----------------------------------------------------------------------+----------+-------------+--------------+-------------
 id          | integer                  |           | not null | generated always as identity                                          | plain    |             |              | 
 standard_id | integer                  |           | not null |                                                                       | plain    |             |              | 
 path        | ltree                    |           | not null |                                                                       | extended |             |              | 
 parent_id   | integer                  |           |          |                                                                       | plain    |             |              | 
 level       | integer                  |           |          | generated always as (nlevel(path)) stored                             | plain    |             |              | 
 label       | character varying        |           | not null | generated always as (replace(path::text, '.'::text, ''::text)) stored | extended |             |              | 
 code        | character varying        |           | not null |                                                                       | extended |             |              | 
 name        | character varying(256)   |           | not null |                                                                       | extended |             |              | 
 description | text                     |           |          |                                                                       | extended |             |              | 
 active      | boolean                  |           | not null |                                                                       | plain    |             |              | 
 custom      | boolean                  |           | not null |                                                                       | plain    |             |              | 
 updated_at  | timestamp with time zone |           | not null | statement_timestamp()                                                 | plain    |             |              | 
Indexes:
    "activity_category_pkey" PRIMARY KEY, btree (id)
    "activity_category_standard_id_path_active_key" UNIQUE CONSTRAINT, btree (standard_id, path, active)
    "ix_activity_category_parent_id" btree (parent_id)
Foreign-key constraints:
    "activity_category_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES activity_category(id) ON DELETE RESTRICT
    "activity_category_standard_id_fkey" FOREIGN KEY (standard_id) REFERENCES activity_category_standard(id) ON DELETE RESTRICT
Referenced by:
    TABLE "activity" CONSTRAINT "activity_category_id_fkey" FOREIGN KEY (category_id) REFERENCES activity_category(id) ON DELETE CASCADE
    TABLE "activity_category" CONSTRAINT "activity_category_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES activity_category(id) ON DELETE RESTRICT
    TABLE "activity_category_role" CONSTRAINT "activity_category_role_activity_category_id_fkey" FOREIGN KEY (activity_category_id) REFERENCES activity_category(id) ON DELETE CASCADE
Policies:
    POLICY "activity_category_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_category_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "activity_category_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    lookup_parent_and_derive_code_before_insert_update BEFORE INSERT OR UPDATE ON activity_category FOR EACH ROW EXECUTE FUNCTION lookup_parent_and_derive_code()
    trigger_prevent_activity_category_id_update BEFORE UPDATE OF id ON activity_category FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
