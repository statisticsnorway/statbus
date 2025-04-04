```sql
                                       Table "public.country_used"
 Column |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer |           |          |         | plain    |             |              | 
 iso_2  | text    |           |          |         | extended |             |              | 
 name   | text    |           |          |         | extended |             |              | 
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
Access method: heap

```
