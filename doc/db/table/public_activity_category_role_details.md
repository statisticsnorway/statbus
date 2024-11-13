```sql
                                                   Table "public.activity_category_role"
        Column        |  Type   | Collation | Nullable |           Default            | Storage | Compression | Stats target | Description 
----------------------+---------+-----------+----------+------------------------------+---------+-------------+--------------+-------------
 id                   | integer |           | not null | generated always as identity | plain   |             |              | 
 role_id              | integer |           | not null |                              | plain   |             |              | 
 activity_category_id | integer |           | not null |                              | plain   |             |              | 
Indexes:
    "activity_category_role_pkey" PRIMARY KEY, btree (id)
    "activity_category_role_role_id_activity_category_id_key" UNIQUE CONSTRAINT, btree (role_id, activity_category_id)
    "ix_activity_category_role_activity_category_id" btree (activity_category_id)
    "ix_activity_category_role_role_id" btree (role_id)
Foreign-key constraints:
    "activity_category_role_activity_category_id_fkey" FOREIGN KEY (activity_category_id) REFERENCES activity_category(id) ON DELETE CASCADE
    "activity_category_role_role_id_fkey" FOREIGN KEY (role_id) REFERENCES statbus_role(id) ON DELETE CASCADE
Policies:
    POLICY "activity_category_role_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "activity_category_role_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "activity_category_role_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_activity_category_role_id_update BEFORE UPDATE OF id ON activity_category_role FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
