```sql
                                                      Table "public.report_tree"
     Column     |  Type   | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
----------------+---------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id             | integer |           | not null | generated always as identity | plain    |             |              | 
 title          | text    |           |          |                              | extended |             |              | 
 type           | text    |           |          |                              | extended |             |              | 
 report_id      | integer |           |          |                              | plain    |             |              | 
 parent_node_id | integer |           |          |                              | plain    |             |              | 
 archived       | boolean |           | not null | false                        | plain    |             |              | 
 resource_group | text    |           |          |                              | extended |             |              | 
 report_url     | text    |           |          |                              | extended |             |              | 
Indexes:
    "report_tree_pkey" PRIMARY KEY, btree (id)
Policies:
    POLICY "report_tree_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "report_tree_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "report_tree_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_report_tree_id_update BEFORE UPDATE OF id ON report_tree FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
