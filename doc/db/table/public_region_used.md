```sql
                                            Table "public.region_used"
 Column |       Type        | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+-------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer           |           |          |         | plain    |             |              | 
 path   | ltree             |           |          |         | extended |             |              | 
 level  | integer           |           |          |         | plain    |             |              | 
 label  | character varying |           |          |         | extended |             |              | 
 code   | character varying |           |          |         | extended |             |              | 
 name   | text              |           |          |         | extended |             |              | 
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
Access method: heap

```
