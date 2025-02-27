```sql
                                  Unlogged table "public.country_used"
 Column |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer |           |          |         | plain    |             |              | 
 iso_2  | text    |           |          |         | extended |             |              | 
 name   | text    |           |          |         | extended |             |              | 
Indexes:
    "country_used_key" UNIQUE, btree (iso_2)
Policies:
    POLICY "country_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "country_used_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "country_used_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Access method: heap

```
