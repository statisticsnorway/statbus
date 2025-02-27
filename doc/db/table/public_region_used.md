```sql
             Unlogged table "public.region_used"
 Column |       Type        | Collation | Nullable | Default 
--------+-------------------+-----------+----------+---------
 id     | integer           |           |          | 
 path   | ltree             |           |          | 
 level  | integer           |           |          | 
 label  | character varying |           |          | 
 code   | character varying |           |          | 
 name   | text              |           |          | 
Indexes:
    "region_used_key" UNIQUE, btree (path)
Policies:
    POLICY "region_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "region_used_regular_user_read" FOR SELECT
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "region_used_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))

```
