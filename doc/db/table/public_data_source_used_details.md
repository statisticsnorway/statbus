```sql
                                Unlogged table "public.data_source_used"
 Column |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer |           |          |         | plain    |             |              | 
 code   | text    |           |          |         | extended |             |              | 
 name   | text    |           |          |         | extended |             |              | 
Indexes:
    "data_source_used_key" UNIQUE, btree (code)
Policies:
    POLICY "data_source_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "data_source_used_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "data_source_used_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Access method: heap

```
