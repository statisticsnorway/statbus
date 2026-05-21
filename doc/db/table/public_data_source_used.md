```sql
                                     Table "public.data_source_used"
 Column |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer |           |          |         | plain    |             |              | 
 code   | text    |           |          |         | extended |             |              | 
 name   | text    |           |          |         | extended |             |              | 
Indexes:
    "data_source_used_key" UNIQUE, btree (code)
Policies:
    POLICY "data_source_used_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "data_source_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "data_source_used_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Access method: heap

```
