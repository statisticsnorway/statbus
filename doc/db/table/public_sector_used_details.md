```sql
                                        Unlogged table "public.sector_used"
 Column |       Type        | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+-------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer           |           |          |         | plain    |             |              | 
 path   | ltree             |           |          |         | extended |             |              | 
 label  | character varying |           |          |         | extended |             |              | 
 code   | character varying |           |          |         | extended |             |              | 
 name   | text              |           |          |         | extended |             |              | 
Indexes:
    "sector_used_key" UNIQUE, btree (path)
Policies:
    POLICY "sector_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "sector_used_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "sector_used_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Access method: heap

```
