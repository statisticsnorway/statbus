```sql
          Table "public.data_source_used"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 id     | integer |           |          | 
 code   | text    |           |          | 
 name   | text    |           |          | 
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

```
