```sql
                 Table "public.sector_used"
 Column |       Type        | Collation | Nullable | Default 
--------+-------------------+-----------+----------+---------
 id     | integer           |           |          | 
 path   | ltree             |           |          | 
 label  | character varying |           |          | 
 code   | character varying |           |          | 
 name   | text              |           |          | 
Indexes:
    "sector_used_key" UNIQUE, btree (path)
Policies:
    POLICY "sector_used_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "sector_used_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "sector_used_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)

```
