```sql
            Table "public.country_used"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 id     | integer |           |          | 
 iso_2  | text    |           |          | 
 name   | text    |           |          | 
Indexes:
    "country_used_key" UNIQUE, btree (iso_2)
Policies:
    POLICY "country_used_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "country_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "country_used_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)

```
