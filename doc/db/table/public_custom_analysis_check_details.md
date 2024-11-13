```sql
                                                          Table "public.custom_analysis_check"
      Column       |          Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
-------------------+-------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id                | integer                 |           | not null | generated always as identity | plain    |             |              | 
 name              | character varying(64)   |           |          |                              | extended |             |              | 
 query             | character varying(2048) |           |          |                              | extended |             |              | 
 target_unit_types | character varying(16)   |           |          |                              | extended |             |              | 
Indexes:
    "custom_analysis_check_pkey" PRIMARY KEY, btree (id)
Policies:
    POLICY "custom_analysis_check_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "custom_analysis_check_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "custom_analysis_check_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_custom_analysis_check_id_update BEFORE UPDATE OF id ON custom_analysis_check FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
