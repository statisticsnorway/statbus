```sql
                 Table "public.region_used"
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
    POLICY "region_used_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "region_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "region_used_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)

```
