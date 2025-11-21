```sql
                                                  Table "public.activity_category_access"
        Column        |  Type   | Collation | Nullable |           Default            | Storage | Compression | Stats target | Description 
----------------------+---------+-----------+----------+------------------------------+---------+-------------+--------------+-------------
 id                   | integer |           | not null | generated always as identity | plain   |             |              | 
 user_id              | integer |           | not null |                              | plain   |             |              | 
 activity_category_id | integer |           | not null |                              | plain   |             |              | 
Indexes:
    "activity_category_access_pkey" PRIMARY KEY, btree (id)
    "activity_category_access_user_id_activity_category_id_key" UNIQUE CONSTRAINT, btree (user_id, activity_category_id)
    "ix_activity_category_access_activity_category_id" btree (activity_category_id)
    "ix_activity_category_access_user_id" btree (user_id)
Foreign-key constraints:
    "activity_category_access_activity_category_id_fkey" FOREIGN KEY (activity_category_id) REFERENCES activity_category(id) ON DELETE CASCADE
    "activity_category_access_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
Policies:
    POLICY "activity_category_access_admin_policy"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "activity_category_access_read_policy" FOR SELECT
      TO authenticated
      USING (true)
Not-null constraints:
    "activity_category_access_id_not_null" NOT NULL "id"
    "activity_category_access_user_id_not_null" NOT NULL "user_id"
    "activity_category_access_activity_category_id_not_null" NOT NULL "activity_category_id"
Triggers:
    trigger_prevent_activity_category_access_id_update BEFORE UPDATE OF id ON activity_category_access FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
